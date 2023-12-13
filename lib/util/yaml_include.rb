require 'yaml'
require 'json'
require 'nokogiri'

module Util
  module YAMLInclude
    extend self

    # Domain type for including YAML files
    #  Example: Payload: !include/yaml platform/api/apiconf.yaml
    def yaml(basedir)
      YAML.add_domain_type(nil, 'include/yaml') do |_, filename|
        file_path = File.join basedir, filename
        next Log.warn "Unable to locate #{file_path}" unless File.exist? file_path

        begin
          next YAML.load_file(file_path, aliases: true)
        rescue => error
          raise "Unable to parse #{file_path} as YAML - #{error}"
        end
      end
    end

    # Domain type for including YAML files
    #  Example: Payload: !include/json platform/api/swagger.json
    def json(basedir)
      YAML.add_domain_type(nil, 'include/json') do |_, filename|
        file_path = File.join basedir, filename
        next Log.warn "Unable to locate #{file_path}" unless File.exist? file_path

        begin
          next JSON.parse(File.read(file_path))
        rescue => error
          raise "Unable to parse #{file_path} as JSON - #{error}"
        end
      end
    end

    # Raw text domain type for including YAML files
    #  Example: Payload: !include/json platform/api/dump.txt
    def text(basedir)
      YAML.add_domain_type(nil, 'include/text') do |_, filename|
        file_path = File.join basedir, filename
        next Log.warn "Unable to locate #{file_path}" unless File.exist? file_path

        begin
          next File.read(file_path)
        rescue => error
          raise "Unable to parse #{file_path} as text - #{error}"
        end
      end
    end

    # Domain type for including xml files
    # Example: Payload: !include/xml platform/api/configuration.xml
    def xml(basedir)
      YAML.add_domain_type(nil, 'include/xml') do |_, filename|
        file_path = File.join basedir, filename
        next Log.warn "Unable to locate #{file_path}" unless File.exist? file_path

        begin
          next File.read(file_path) if Nokogiri::XML(File.read(file_path)) { |config| config.strict }
        rescue => error
          raise "Unable to parse #{file_path} as XML - #{error}"
        end
      end
    end
  end
end
