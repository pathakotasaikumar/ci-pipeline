require "action"
require "aws_helpers/ec2_helper"

# Extends Action class
# Action enables sharing of generated AMI with account specified in shared_accounts environment variable
class AddLaunchPermission < Action
  # @param (see Action::Initialize)
  def initialize(component: nil, params: [], stage: nil, step: nil)
    super

    raise ArgumentError %(Action AddLaunchPermission does not accept parameters
      Set shared_accounts variable in Bamboo with a list of valid account numbers) unless params.empty?

    @shared_accounts = Context.environment.variable('shared_accounts', [])

    # Check if shared accounts variable is configured and contains valid account numbers
    if @shared_accounts.empty? || (@shared_accounts.select { |i| i.to_s =~ /[0-9]{12}/ }).size < @shared_accounts.size
      raise "AddLaunchPermission action requires shared_accounts variable"
    end
  end

  # @return [Array] List of valid stages during which this action can be invoked
  def valid_stages
    [
      "PostDeploy",
      "PreRelease",
      "PostRelease",
    ]
  end

  # @return [Array] List of valid component types which may invoke this action
  def valid_components
    [
      "aws/image",
    ]
  end

  # Executes EC2 add launch permission API to add specified accounts to the launch list
  def invoke
    bake_instance_name = component.bake_instance_name
    image_id = Context.component.variable(@component.component_name, "ImageId", nil)
    Log.debug "Running AddLaunchPermission with #{image_id} and #{@shared_accounts}"
    raise ActionError, "Unable to determine ImageId for #{bake_instance_name}" if image_id.nil?

    begin
      AwsHelper.ec2_add_launch_permission(
        image_id: image_id,
        accounts: @shared_accounts
      )
      Log.output "SUCCESS: Added launch permission for #{@component.component_name} #{image_id} to #{@shared_accounts}"
    rescue => e
      Log.error "FAIL: Failed to execute AddLaunchPermission on #{@component.component_name} - #{e}"
      raise "Failed to execute AddLaunchPermission on #{@component.component_name} - #{e}"
    end
  end
end
