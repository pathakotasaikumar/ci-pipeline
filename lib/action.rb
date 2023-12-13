# Abstract class definition for Component actions
class Action
  attr_reader :component, :stage, :step

  def initialize(component: nil, params: nil, stage: nil, step: nil)
    raise ArgumentError, "Action #{name} can only run at #{valid_stages.to_s}" unless run_at? stage
    raise ActionError, "Action #{name} can only by invoked by #{valid_components.to_s}" unless run_by? component.type

    @component = component
    @stage = stage
    @step = step
  end

  # Returns name of the action
  # @return [String] Name of the action
  def name
    self.class.inspect
  end

  # Returns true or false if action can be executed in the stage
  # @param stage [String] Execution stage.
  # @return [Bool]
  def run_at?(stage)
    return true if valid_stages.first == :all

    valid_stages.include? stage
  end

  # Returns true or false if action can be executed by the component type
  # @param component [String] Component type
  # @return [Bool]
  def run_by?(component)
    return true if valid_components.first == :all

    valid_components.include? component
  end

  # Returns a list of valid execution stages for the action class
  # @return [Array] List of valid execution stages
  def valid_stages
    raise "Must override method 'valid_stages' in consumable sub class"
  end

  # Returns a list of valid component types which can execute this action type
  # @return [Array] List of valid component types
  def valid_components
    raise "Must override method 'valid_components' in consumable sub class"
  end

  # Invokes execution of the action instance.
  def invoke
    raise "Must override method 'invoke' in consumable sub class"
  end

  # Returns instance of an action type based on supplied parameters
  # @param name [String] Action type name
  # @param stage [String] Execution stage
  # @param component [Object] Reference to component
  # @param params [Hash] Collection of parameters for action initialisation
  # @param step [String] Step used for ordering actions executed within the same Stage
  # @return [Object] Instance of an action sub class based on supplied parameters
  def self.instantiate(name: nil, **args)
    raise ArgumentError, "Action #{name} must be specified" if name.nil?

    case name
    when "AddLaunchPermission"
      require 'consumables/aws/actions/add_launch_permission'
      AddLaunchPermission.new(**args)
    when "ExecuteStateMachine"
      require 'consumables/aws/actions/execute_state_machine'
      ExecuteStateMachine.new(**args)
    when "HTTPRequest"
      require 'consumables/aws/actions/http_request'
      HTTPRequest.new(**args)
    when "InvokeLambda"
      require 'consumables/aws/actions/invoke_lambda'
      InvokeLambda.new(**args)
    when "RegisterApi"
      require 'consumables/aws/actions/register_api'
      RegisterApi.new(**args)
    when "SetDesiredCapacity"
      require 'consumables/aws/actions/set_desired_capacity'
      SetDesiredCapacity.new(**args)
    when "Snapshot"
      require 'consumables/aws/actions/snapshot'
      Snapshot.new(**args)
    when "SetWeightRoutePolicy"
      require 'consumables/aws/actions/set_weight_route_policy'
      SetWeightRoutePolicy.new(**args)
    when "QualysWAS"
      require 'consumables/aws/actions/qualys_was'
      QualysWAS.new(**args)
    when "SetScalableTarget"
      require 'consumables/aws/actions/set_scalable_target'
      SetScalableTarget.new(**args)
    when "WaitForHTTPResponse"
      require 'consumables/aws/actions/wait_for_http_response'
      WaitForHttpResponse.new(**args)
    else
      raise "Unknown action #{name.inspect}"
    end
  end
end
