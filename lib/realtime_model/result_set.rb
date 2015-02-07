module RealtimeModel

  class ResultSet
    include Enumerable

    attr_accessor :buffer
    attr_accessor :key
    attr_accessor :min_buffer_size
    attr_accessor :max_buffer_size

    def each
      if @buffer
        cursor = 0
        buffer_size = @min_buffer_size
        begin
          results = redis_result_set[cursor..(cursor + buffer_size - 1)]
          cursor = cursor + buffer_size
          results.each do |r|
            yield @item_class.new(:id => r.to_i)
          end
          if (new_buffer_size = buffer_size * 2) > @max_buffer_size
            buffer_size = @max_buffer_size
          else
            buffer_size = new_buffer_size
          end
        end until cursor >= size
      else
        results = Redis.current.zrangebyscore(@key, '-inf', '+inf')
        results.each do |r|
          yield @item_class.new(:id => r.to_i)
        end
      end
    end

    def empty?
      size == 0
    end

    def initialize(args)
      @key = args[:key]
      @buffer = args[:buffer] || false
      @min_buffer_size = args[:min_buffer_size] || 1
      @max_buffer_size = args[:max_buffer_size] || 1024
      @item_class = args[:item_class]
    end

    def remove(item)
      Redis.current.zrem(@key, item.id)
    end

    def remove_at(index)
      Redis.current.zremrangebyrank(@key, index, index)
    end

    def size
      Redis.current.zcard(self.key)
    end

    def [](start, length=1)
      ids = redis_result_set[start, length]
      items = []
      ids.each do |id|
        items << @item_class.new(:id => id.to_i)
      end
      length > 1 ? items : items.first
    end

    private

    def redis_result_set
      @redis_result_set ||= Redis::SortedSet.new(self.key)
    end

  end
  
end