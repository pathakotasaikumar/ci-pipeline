require "util/json_tools"
require_relative "events_rule_builder"

module ECSEventsRuleBuilder
  include EventsRuleBuilder

  def _process_ecs_events_rule(
    component_name:,
    rule_name:,
    template:,
    task_definition_logical_name:,
    event_definition:
  )
    # Removing the LaunchType properties force the target back to the cluster capacity provider settings
    event_definition['Properties']['Targets'] = [{
      'Arn' => { 'Fn::ImportValue' => 'qcp-ecs-default-cluster-arn' },
      'RoleArn' => { 'Fn::GetAtt' => ["#{rule_name}EventRole", "Arn"] },
      'Id' => Defaults.component_stack_name(rule_name),
      'EcsParameters' => {
        # 'LaunchType' => 'FARGATE',
        'NetworkConfiguration' => {
          'AwsVpcConfiguration' => {
            'AssignPublicIp': 'DISABLED',
            'SecurityGroups': [Context.component.sg_id(component_name, "SecurityGroup")],
            'Subnets': Context.environment.subnet_ids("@private")
          }
        },
        'TaskCount' => JsonTools.get(event_definition, 'Properties.Targets.EcsParameters.TaskCount', 1),
        'TaskDefinitionArn' => { 'Ref' => task_definition_logical_name },
      }
    }]

    _process_events_rule(
      template: template,
      definitions: { rule_name => event_definition }
    )

    # We are doing this within the same cloudformation stack as oppose separate stacks in order to target the resource arn
    # The resource arn can change due to the whether the account is with the new ECS arn format or not
    template["Resources"]["#{rule_name}EventRole"] = {
      "Type" => "AWS::IAM::Role",
      "Properties" => {
        "AssumeRolePolicyDocument" => {
          "Version" => "2012-10-17",
          "Statement" => [
            {
              "Effect" => "Allow",
              "Principal" => {
                "Service" => ["events.amazonaws.com"]
              },
              "Action" => ["sts:AssumeRole"]
            }
          ]
        },
        "Path" => "/",
        "PermissionsBoundary" => { "Fn::Sub" => "arn:aws:iam::${AWS::AccountId}:policy/PermissionBoundaryPolicy" },
        "Policies": [
          {
            "PolicyName": "ECSEventRule",
            "PolicyDocument": {
              "Version": "2012-10-17",
              "Statement": [
                {
                  "Effect": "Allow",
                  "Action": [
                    "ecs:RunTask"
                  ],
                  "Resource": [
                    { 'Ref' => task_definition_logical_name }
                  ]
                },
                {
                  "Effect": "Allow",
                  "Action": [
                    "iam:PassRole"
                  ],
                  "Resource": [
                    Context.component.role_arn(component_name, "ExecutionRole"),
                    Context.component.role_arn(component_name, "TaskRole")
                  ],
                  "Condition": {
                    "StringLike": {
                      "iam:PassedToService": "ecs-tasks.amazonaws.com"
                    }
                  }
                }
              ]
            }
          }
        ]
      }
    }
    return template
  end
end
