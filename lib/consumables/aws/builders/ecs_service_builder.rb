require "util/json_tools"

module ECSServiceBuilder
  def _process_ecs_service(
    template:,
    component_name:,
    task_definition_logical_name:,
    service_definition:
  )
    name, definition = service_definition.first

    clustername = JsonTools.get(definition, "Properties.Cluster", { "Fn::ImportValue" => "qcp-ecs-default-cluster" })

    # Removing the LaunchType properties force the target back to the cluster capacity provider settings
    template["Resources"][name] = {
      "Type" => "AWS::ECS::Service",
      "Properties" => {
        "Cluster" => clustername,
        "DesiredCount" => JsonTools.get(definition, "Properties.DesiredCount", 1),
        "EnableECSManagedTags" => true,
        "NetworkConfiguration" => {
          "AwsvpcConfiguration" => {
            "AssignPublicIp" => "DISABLED",
            "SecurityGroups" => [Context.component.sg_id(component_name, "SecurityGroup")],
            "Subnets" => Context.environment.subnet_ids("@private")
          }
        },
        "PropagateTags" => "TASK_DEFINITION",
        "TaskDefinition" => { "Ref" => task_definition_logical_name },
        "EnableExecuteCommand" => true,
      }
    }

    resource = template["Resources"][name]
    loadbalancer = Context.component.replace_variables(
      JsonTools.get(definition, "Properties.LoadBalancers", {})
    )
    if !loadbalancer.nil?
      resource["Properties"]["LoadBalancers"] = loadbalancer.map { |lb|
        lb["ContainerName"] = Context.component.variable(component_name, "ECSContainerName")
        lb
      }
    end

    # Returning Scaling Policy resource id
    return {
      "Fn::Join" => ["/", [
        "service",
        clustername,
        {
          "Fn::GetAtt" => [name, "Name"]
        }
      ]]
    }
  end
end
