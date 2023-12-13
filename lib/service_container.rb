require "#{BASE_DIR}/lib/services/service_base"
require "#{BASE_DIR}/lib/util/object_space_utils"

include Qantas::Pipeline::Services

# depending on where in the code ServiceContainer.instance is called, we might or might not load all requerements already
# normally, ServiceContainer.instance will be called very late allowing all require 'xxx' execute
# under unit tests, however, we might have different initialization flow

# hence enforcing pre-load of all 'services' from /lib/services
def _include_files(folders, is_debug = false)
  folders.each do |folder|
    Dir.glob("#{folder}/**/*.rb").each { |file_path|
      if is_debug
        puts "  - including service file: #{file_path}"
      end
      require file_path
    }
  end
end

_include_files [
  "#{BASE_DIR}/lib/services"
]

module Qantas
  module Pipeline
    class ServiceContainer
      @services
      @excluded_classes

      @@instance = nil

      def initialize
        @services = {}
        _init_services(services: @services)
      end

      def self.instance
        if (@@instance == nil)
          @@instance = ServiceContainer.new
        end

        return @@instance
      end

      def register_service(service_type, service_instance)
        @services[service_type] = service_instance
      end

      def get_service_by_name(service_name)
        result = nil

        @services.each { |key, value|
          if (value.name == service_name)
            result = value
          end
        }

        if result == nil
          raise _compose_not_found_trace(
            "Can't find service instance for requested name: #{service_name}"
          )
        end

        result
      end

      def get_service(service_type)
        result = @services.fetch(service_type, nil)

        if result == nil
          raise _compose_not_found_trace(
            "Can't find service instance for requested type: #{service_type}"
          )
        end

        result
      end

      def _compose_not_found_trace(message)
        service_list = @services.keys.map { |s| s }
        service_list_string = " - " + service_list.join("\n - ")

        error_message = [
          message,
          "Services list:",
          service_list_string
        ].join("\n")
      end

      def get_services(service_type)
        result = []

        @services.each { |service, impl|
          if service <= service_type
            result << impl
          end
        }

        result
      end

      private

      def _excluded_classes
        if @excluded_classes.nil?
          @excluded_classes = [
            ServiceBase
          ]
        end

        @excluded_classes
      end

      def _init_services(services:)
        service_classes = _load_classes(parent_class: ServiceBase)

        service_classes.each do |service_class|
          if _excluded_classes.include?(service_class)
            next
          end

          # log services aren't awailable here yet
          puts "  - pipeline container, creating instance: #{service_class}"

          service_instance = service_class.new
          services[service_class] = service_instance
        end
      end

      def _load_classes(parent_class:)
        ObjectSpaceUtils.load_pipeline_classes(parent_class: parent_class)
      end
    end
  end
end
