module RealtimeModel

  module InstanceMethods

    def attributes
      redis_attrs = attributes_hash.all
      attrs = {}
      self.class.attribute_definitions.each do |attr_name, attr_type|
        val = redis_attrs[attr_name]
        attrs[attr_name] = Utils.blank?(val) ? nil : coherce_type(val, attr_type)
      end
      attrs
    end

    def delete
      self.class.delete(self)
    end

    def initialize(attrs={})
      if (@id = attrs[:id]).nil?
        self.class.highest_id.increment do |val|
          @id = val
          attrs.each do |k, v|
            if k.to_s != 'id' && self.class.attribute_definitions.keys.include?(k.to_s)
              setter = self.class.instance_method("#{k}=").bind(self)
              setter.call(v)
            end
          end
        end
      end     
      self
    end

    def load_snapshot(timestamp=nil)
      snapshot_msgpack = if timestamp
        Redis.current.zrangebyscore(snapshots.key, timestamp, '+inf', :limit => [0,1]).first
      else
        Redis.current.zrevrangebyscore(snapshots.key, '+inf', '-inf', :limit => [0,1]).first
      end
      snapshot_msgpack ? MessagePack.unpack(snapshot_msgpack) : nil
    end

    def lock
      super.value ||= SecureRandom.uuid
      super
    end

    def realtime_model_lock(opts={})
      if(opts[:flag] || opts[:flag].nil?)
        Redis::Lock.new(Utils.try(opts[:lock], :value) || lock.value).lock do
          yield
        end
      else
        yield
      end
    end

    def save_snapshot
      snapshot = self.snapshot
      snapshots[snapshot.to_msgpack] = Time.now.to_f
    end

    def snapshot(args={:lock => true, :include_version => true})
      take_snapshot = lambda{|lock_flag, version_flag|
        new_snapshot = {'id' => id}
        new_snapshot['version'] = version.value if version_flag
        new_snapshot = new_snapshot.merge(attributes)
        if self.respond_to? :collection_names
          self.collection_names.each do |col|
            new_snapshot[col] = []
            self.send(col).each do |item|
              new_snapshot[col] << item.snapshot(:lock => false, :include_version => false)
            end
          end
        end
        new_snapshot
      }
      if args[:lock]
        realtime_model_lock{take_snapshot.call(args[:lock], args[:include_version])}
      else
        take_snapshot.call(args[:lock], args[:include_version])
      end     
    end

    def update_attributes(attrs) #todo add index updating
      realtime_model_lock do
        new_values = {}
        self.class.attribute_definitions.keys.each do |attr_name|
          new_values[attr_name] = attrs[attr_name.to_sym]
        end
        attributes_hash.bulk_set(new_values)
        version.increment
      end
    end

    private

    def coherce_type(val, type)
      case type
      when 'float'
        Float val
      when 'integer'
        Integer val
      when 'string'
        String val
      end
    end

  end

end