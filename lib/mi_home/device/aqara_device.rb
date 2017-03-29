
module MiHome
  module Device
    class AqaraDevice
      include Unobservable::Support
      attr_accessor :gateway, :sid,:platform, :data
      attr_event :on_changed

      def initialize
        @data={}
      end
      def process_message(message)

        @old_values = values
        @data = JSON.parse(message[:data], object_class: HashWithIndifferentAccess)
        @values = values
        if @old_values != @values
          raise_event :on_changed
        end
        (@old_values.to_a - @values.to_a).to_h.each do |property, value|
          raise_event "on_#{property.to_s.gsub('?', '')}".to_sym, @values[property], @old_values[property]
        end

        # only if it report trigger event
        if message[:cmd] == "report"
          event = self.class.events.detect { |event| @data[:status] == event.to_s }

          if event
            raise_event event
          end
        end
      end
      def values
        self.class.properties.map do |property|
          [property,self.send(property)]
        end.to_h
      end
      def as_json
        values.dup.merge(
        {
            device_name: name,
            device_model: model,
            type: type,
            sid: sid,
            data: @data
        })
      end
      alias_method :inspect, :as_json
      def refresh!(sync: false)
        @platform.__request_current_status(self)
        if sync

        end
      end
      def type
        self.class.name.underscore.split('/')[-1]
      end
      def self.create(model)
        MiHome::Device::AqaraDevice.device_class_for(model.to_sym).new
      end
      def self.supported_devices
        AqaraDevice.devices.map do |klass|
          klass.name.underscore
        end
      end
      def self.device_name(name)
        define_method :name do
          name
        end
      end

      def self.device_model(model)
        AqaraDevice.devices[model] = self
        define_method :model do
          model
        end
      end
      def self.devices
        @devices||={}
      end
      def self.device_class_for(model)
        AqaraDevice.devices[model]

      end
      def self.properties
        @properties||=[]
      end
      def self.events
        @events||=[]
      end
      def self.event(*event_names)
        events.push(*event_names)
        event_names.each do |event_name|
          attr_event event_name
        end
      end
      def self.property(property, params=nil, &block)

        properties << property
        is_boolean = property.to_s.include?('?')
        params||={}
        is_writable = params.delete(:changable)
        property_name = property.to_s.gsub('?', '')
        attr_event "on_#{property_name}".to_sym

        if is_writable
          set_method = "#{property_name}=".to_sym
          if is_boolean

            define_method "#{property_name}!".to_sym do
              send set_method, true
            end

          end
          define_method set_method do |value|
            new_data = params
            if is_boolean
              if value
                if params.empty?
                  new_data = {status: property_name}
                end
              else
                raise 'Setting false for ? method is not supported'
              end
            else
              new_data = {property_name => value}
            end

            @platform.__set_current_status self, new_data
          end
        end
        define_method property do
          if block
            block.call(@data)
          else
            if params.empty?
              if is_boolean
                @data[:status] == property_name
              else
                @data[:property]
              end
            else
              params.any? { |k, w| @data[k] == w }
            end
          end
        end
      end
    end
  end
end