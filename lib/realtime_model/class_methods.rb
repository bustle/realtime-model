module RealtimeModel

  module ClassMethods

    SUPPORTED_VALUE_TYPES = [Float, Integer, String]
    REDIS_COLLECTION_TYPES = [Redis::HashKey, Redis::List, Redis::Set, Redis::SortedSet]
    TEMP_KEYS_POOL = "temp_keys_pool"
    TEMP_KEY_EXPIRATION = 60

    def self.extended(klass)
      klass.send('class_init')
    end

    def attribute_definitions
      @attribute_definitions ||= attribute_definitions_hash.all
    end

    def delete(instance)
      if instance.id
        collection_names.each do |collection_name|
          instance.send(collection_name).delete
        end
        indexes.each do |attr_name|
          update_index(attr_name, instance.send(attr_name), nil, instance.id)
        end
        Redis.current.del instance.send('attributes_hash').key
        Redis.current.del instance.send('snapshots').key
        instance.send('dependant_version_counter_key').delete
        instance.send('version').delete
        instance.send('lock').delete
      end
      nil
    end

    def find(args)
      if args.class == Hash
        search(args)[0]
      else
        self.redis.get("#{Utils.underscore(self.name)}:#{args}:version") ? new(:id => args) : nil
      end
    end

    def find_all(args)
      search(args)
    end

    def get_index(attr_name)
      index_name = "#{attr_name}_index"
      respond_to?(index_name) ? send(index_name) : nil
    end

    def rt_attr(name, args)
      define_realtime_accessors(name.to_s, args[:as], args[:index])
    end

    def has_many(name, args)
      collection_name = name.to_s
      klass = args[:as]
      self.collection_names << collection_name
      instance_eval %{
        define_method :#{collection_name} do
          @#{collection_name} ||= RealtimeModel::Collection.new(
            :owner => self,
            :item_class => klass,
            :buffer => true
          )
          @#{collection_name}
        end
      }
    end

    def has_one(name, args)
      assoc_name = name.to_s
      klass = args[:as]
      rt_attr "#{assoc_name}_id", as: Integer
      instance_eval %{
        define_method :#{assoc_name} do
          @#{assoc_name}_id ||= nil
          @#{assoc_name} ||= klass.find(@#{assoc_name}_id)
        end
        define_method :#{assoc_name}= do |rt_model|
          @#{assoc_name}_id = rt_model ? rt_model.id : nil
          @#{assoc_name} = rt_model
          rt_model
        end
      }

    end

    def search(args, opts={})
      buffer = opts[:buffer] || true
      result_sets = []
      vals_with_results = []
      args.each do |key, val|
        if index = get_index(key)
          if index[val] #can only search on idexed values
            result_sets << Redis::SortedSet.new(index[val]) 
            vals_with_results << index[val]
          end
        end
      end
      if result_sets.empty?
        []
      elsif result_sets.size == 1
        RealtimeModel::ResultSet.new(
          :buffer => buffer, 
          :item_class => self, 
          :key => vals_with_results.first
        )
      else
        result_set_key = opts[:result_set_key] || get_temp_key
        result_sets.first.interstore(result_set_key, *result_sets.drop(1))
        RealtimeModel::ResultSet.new(:buffer => buffer, :item_class => self, :key => result_set_key)
      end
    end

    def update_index(attr_name, old_val, new_val, id, position=nil)
      index = self.send('get_index', attr_name)
      delete_from_index(index, old_val, id)
      write_to_index(index, new_val, id, position) if new_val
    end

    private

    def class_init
      include Redis::Objects
      attr_reader :id
      counter :highest_id, :global => true; private :highest_id
      counter :version; private :version
      hash_key :attribute_definitions_hash, :global => true; private :attribute_definitions_hash
      hash_key :attributes_hash; private :attributes_hash
      set :indexes, :global => true; private :indexes
      sorted_set :snapshots; private :snapshots
      value :dependant_version_counter_key; private :dependant_version_counter_key
      value :lock; private :lock
      set :collection_names, :global => true
    end

    def define_realtime_accessors(attr_name, attr_type, index_flag) 
      if (SUPPORTED_VALUE_TYPES + REDIS_COLLECTION_TYPES).include?(attr_type)
        if SUPPORTED_VALUE_TYPES.include?(attr_type)
          attribute_definitions[attr_name] = Utils.underscore(attr_type.name)
          define_value_getter(attr_name)
          define_value_setter(attr_name)
          create_index(attr_name) if index_flag
        else
          instance_eval "#{Utils.underscore(attr_type.to_s.gsub('Redis::', ''))} :#{attr_name}"
        end
      end
    end

    def define_value_getter(attr_name)
      instance_eval %{
        define_method :#{attr_name} do
          val = attributes_hash[:#{attr_name}]
          Utils.blank?(val) ? nil : coherce_type(val, self.class.attribute_definitions[attr_name])
        end
      }
    end

    def define_value_setter(attr_name)
      define_method "#{attr_name}=" do |val, args={}|
        lock_flag = args[:lock_flag].nil? ? true : args[:lock_flag]
        index_position = args[:index_position]
        begin
          realtime_model_lock(:flag => lock_flag) do
            old_val = attributes_hash[attr_name]
            raise ValueUnchangedError if old_val == val
            if val
              attributes_hash[attr_name] = val
            else
              attributes_hash.delete(attr_name)
            end
            self.class.send('update_index', attr_name, old_val, val, id, index_position) if indexes.include? attr_name  
            version.increment
            if !Utils.blank?(dependant_version_counter_key.value)
              dependant_version_counter = Redis::Counter.new(dependant_version_counter_key.value)
              dependant_version_counter.increment
            end
          end
        rescue ValueUnchangedError
        end
        val
      end
    end

    def create_index(attr_name)
      indexes << attr_name
      hash_key "#{attr_name}_index", :global => true
    end

    def delete_from_index(index, val, id)
      if id_set_key = index[val]
        id_set = Redis::SortedSet.new(id_set_key) 
        id_set.delete id
        if id_set.members.empty?
          Redis.current.del id_set_key 
          index.delete val
        end
      end
    end

    def get_temp_key
      temp_keys = Redis::SortedSet.new(TEMP_KEYS_POOL)
      expired_keys = Redis.current.zrangebyscore(TEMP_KEYS_POOL, 0, Time.now.to_i)
      if expired_keys.empty?
        temp_key = "search_results:#{Time.now.to_i}:#{SecureRandom.uuid}"
      else
        temp_key = expired_keys.first        
      end
      temp_keys[temp_key] = TEMP_KEY_EXPIRATION.seconds.from_now.to_i
      temp_key
    end

    def write_to_index(index, val, id, position=nil)
      id_set_key = index[val] ||= "#{index.key}:#{val}"
      id_set = Redis::SortedSet.new(id_set_key)
      id_set_size = Redis.current.zcard(id_set_key) || 0
      zincrby_lua = %Q{
        local members = redis.call('zrange',KEYS[1],ARGV[1],-1)
        for i, member in ipairs(members) do
          redis.call('zincrby',KEYS[1],1,member)
        end
      }
      if id_set_size == 0
        id_set[id] = 1000
      else
        if position.nil? || (position >= id_set_size)
          highest_score = id_set.score(id_set.last)
          id_set[id] = highest_score + 1
        else
          prev_element_score = (position == 0) ? 0 : id_set.score(id_set[position - 1, 1])
          score_at_position = id_set.score(id_set[position, 1])
          if score_at_position - prev_element_score > 0.1
            id_set[id] = score_at_position - 0.1
          else
            Redis.current.eval(zincrby_lua, [id_set_key], [position])
            next_element_score = id_set.score(id_set[position, 1])
            id_set[id] = next_element_score - 1
          end
        end
      end
    end

  end

  class ValueUnchangedError < RuntimeError; end
  
end