require "util/json_tools"

module EmrStepBuilder
  def _process_emr_steps(
    template: nil,
    step_definitions: nil,
    cluster_name: nil,
    component_name: nil,
    depends_on: nil
  )

    # Create a dependency map for the EMR steps. First step runs after depends_on parameter, if specified.
    dependency_map = {}
    step_definitions.keys.sort.each do |name|
      dependency_map[name] = dependency_map.keys.last || depends_on
    end

    step_definitions.each do |name, definition|
      sections = Defaults.sections
      template["Resources"][name] = {
        "Type" => "AWS::EMR::Step",
        "Properties" => {
          "ActionOnFailure" => JsonTools.get(definition, "Properties.ActionOnFailure"),
          "HadoopJarStep" => JsonTools.get(definition, "Properties.HadoopJarStep"),
          "JobFlowId" => { "Ref" => cluster_name },
          "Name" => "#{sections[:ams]}-#{sections[:qda]}-#{sections[:as]}-#{sections[:ase]}-#{sections[:branch]}-#{sections[:build]}-#{name}"[0..128]
        },
      }
      resource = template["Resources"][name]

      resource["DependsOn"] = dependency_map[name] unless dependency_map[name].nil?

      # Process argument context lookups
      args = JsonTools.get(resource, "Properties.HadoopJarStep.Args", [])
      new_args = []
      args.each do |arg|
        if arg.start_with? "@@"
          # @@ escapes the first @ - return without the first @
          new_args << arg[1..-1]
        elsif arg.start_with? "@" and arg.include? "."
          # Perform a context lookup
          new_args << Context.component.replace_variables(arg)
        else
          new_args << arg
        end
      end
      resource["Properties"]["HadoopJarStep"]["Args"] = new_args

      template["Outputs"]["#{name}Id"] = {
        "Description" => "EMR step id",
        "Value" => { "Ref" => name }
      }
    end
  end
end
