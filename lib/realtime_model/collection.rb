module RealtimeModel

  class Collection
    extend Forwardable
    include Enumerable

    attr_accessor :scope
    attr_reader :buffer

    def_delegators :result_set, :empty?, :key, :size, :[]

    def add(item, args={})
      @owner.realtime_model_lock(:flag => args[:lock_flag], :lock => @owner.send('lock')) do
        item.send('lock').value = @owner.send('lock').value
        item.send('dependant_version_counter_key').value = @owner.send('version').key
        item.send(@foreign_key+'=', @owner.id, :lock_flag => false, :index_position => args[:position])
      end
      item
    end; alias :<< :add

    def buffer=(flag)
      @buffer = flag
      @result_set.buffer = @buffer if @result_set 
    end

    def delete
      self.each do |item|
        item.delete
      end
    end

    def each
      result_set.each do |r|
        yield r
      end
    end

     def initialize(args)
      @buffer = args[:buffer] || false
      @item_class = args[:item_class]
      @owner = args[:owner]
      @foreign_key = "#{Utils.underscore(@owner.class.name)}_id"
      @scope = args[:scope] || {}
      if !@item_class.respond_to?(@foreign_key)
        @item_class.rt_attr(@foreign_key, :as => Integer, :index => true)
      end
    end

    def insert(position, item)
      add(item, {:position => position})
    end

    def move_to(position, item, args={})
      @owner.realtime_model_lock(:flag => args[:lock_flag]) do
        add(item, args.merge({:position => position, :lock_flag => false}))
      end
    end 

    def remove(item, args={})
      @owner.realtime_model_lock(:flag => args[:lock_flag]) do
        item.send('lock').value = nil
        item.send('dependant_version_counter_key').value = nil
        result_set.remove(item)
        item.send(@foreign_key+'=', nil)
      end
      nil
    end

    def remove_at(index, args={})
      @owner.realtime_model_lock(:flag => args[:lock_flag]) do
        result_set.remove_at(index)
      end
      nil
    end

    def reset
      @result_set = nil
      true
    end

    private

    def result_set
      opts = {:buffer => @buffer}
      query = {@foreign_key.to_sym => @owner.id}.merge(@scope)
      if @result_set.nil? || @result_set.class == Array
        @result_set = @item_class.search(query, opts)
      else
        @result_set
      end
    end

  end

end