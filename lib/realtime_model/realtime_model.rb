module RealtimeModel

  def self.included(klass)
    klass.extend ClassMethods
    klass.include InstanceMethods
  end 

  module Utils
    def self.blank?(val)
      if val.class == NilClass
        true
      elsif val.class == String
        val == ""
      else
        false
      end
    end

    def self.try(obj, method_name)
      if obj.respond_to?(method_name)
        obj.send(method_name)
      else
        nil
      end
    end

  	def self.underscore!(string)
    	string.gsub!(/(.)([A-Z])/,'\1_\2')
    	string.downcase!
  	end

    def self.underscore(string)
      string.dup.tap { |s| underscore!(s) }
    end
  end

end