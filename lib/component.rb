require 'consumable'
require 'yaml'
require 'date'

class Component
  # Load and process a component from a file
  def self.load(filename, environment, branch)
    Log.debug "Loading component in file #{filename.inspect}"

    # Read in the component definition in the specfied file
    begin
      component_definition = File.read(filename)
      component_definition = YAML.load(component_definition, aliases: true, permitted_classes: [Date])
    rescue StandardError => e
      raise "Failed to read component file #{filename.inspect} - #{e}"
    end

    # Process environment overrides
    if component_definition.has_key? 'Environments' and component_definition['Environments'].has_key? environment
      Log.debug "Merging environment overrides for environment #{environment.inspect}"

      # Perform a deep merge of the component definition and the environment overrides
      merger = proc { |_key, v1, v2| v1.is_a?(Hash) && v2.is_a?(Hash) ? v1.merge(v2, &merger) : v2 }
      if component_definition['Environments'][environment].has_key? 'Branches' and component_definition['Environments'][environment]['Branches'].has_key? branch
        component_definition.merge!(component_definition['Environments'][environment]['Branches'][branch].to_h, &merger)
      else
        component_definition.merge!(component_definition['Environments'][environment].to_h, &merger)
      end
    else
      Log.debug "No enviroment overrides found for environment #{environment.inspect}"
    end
    component_definition.delete('Environments')
    component_definition
  end

  # Load and process all component definition files in a directory
  def self.load_all(directory, environment, branch)
    # Get a list of component filenames in the specified directory
    component_filenames = Dir.entries(directory).select do |file|
      next if File.directory? file
      next if File.extname(file).downcase != '.yaml'

      true
    end

    components = {}

    # Compile component definitions into actions
    component_filenames.each do |component_filename|
      component_definition = Component.load(File.join(directory, component_filename), environment, branch)

      # Create the consumable object
      component_name = component_filename.split('.')[0]
      components[component_name] = component_definition
    end
    components
  end
end
