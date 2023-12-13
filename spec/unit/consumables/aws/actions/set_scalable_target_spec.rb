$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/consumables/aws/"))
require 'consumables/aws/actions/set_scalable_target'
require 'consumables/aws/aws_ecs_task'
require 'consumable'

RSpec.describe SetScalableTarget do
  before do
    @args = {
      stage: "PostDeploy",
      step: "01",
      params: {
        "MinCapacity" => 1,
        "MaxCapacity" => 2,
        "Timeout" => 200,
        "Target" => "@deployed"
      }
    }
  end

  def _get_action_instance(params: nil, component_type: 'aws/ecs-task')
    instance = double Consumable

    allow(instance).to receive(:type).and_return(component_type)
    allow(instance).to receive(:component_name).and_return('my-component')

    allow(instance).to receive(:scalable_target).and_return({
      'my-ScalableTarget' => '1'
    })
   
    allow(instance).to receive(:definition).and_return({ "Type" => "aws/ecs-task", "Stage" => "01", "Persist" => false, "Configuration" => { "Features" => { "Type" => "Pipeline::Features", "Properties" => { "Features" => { "DataDog" => "enabled", "Qualys" => { "Enabled" => true, "Recipients" => ["test@qantas.com.au"] } } } } } })

    final_params = { component: instance }.merge(@args)
    if (params != nil)
      final_params = final_params.merge(params)
    end

    SetScalableTarget.new(**final_params)
  end

  def _get_valid_action_instance(params = nil, component_type: 'aws/ecs-task')
    allow(Context).to receive_message_chain('environment.variable')
      .with('shared_accounts', [])
      .and_return(['123456789012'])

      _get_action_instance(params: params, component_type: component_type)
  end

  context '.initialize' do
    it 'creates an instance' do
      expect {
        action = _get_valid_action_instance
      }.not_to raise_error
    end

    it 'creates released-targeted action' do
      expect(Context).to receive_message_chain('persist.released_build_number')

      expect {
        _get_action_instance(params: {
          :params => {
            "MinCapacity" => 1,
            "MaxCapacity" => 2,
            "Timeout" => 1,
            "Target" => "@released"
          }
        })
      }.not_to raise_error
    end
    
    it 'checks parameters' do
      invalid_timeouts = [
        -1,
        3601
      ]

      invalid_targets = [
        "deployed1",
        "released1"
      ]

      expect {
        _get_action_instance(params: {
          :params => { 'my' => 1 }
        })
      }.to raise_error("MinCapacity and MaxCapacity must be specified")

      invalid_timeouts.each do |invalid_timeout|
        expect {
          _get_action_instance(params: {
            :params => {
              "MinCapacity" => 1,
              "MaxCapacity" => 2,
              "Timeout" => invalid_timeout
            }
          })
        }.to raise_error(/Invalid timeout/)
      end

      invalid_targets.each do |invalid_targets|
        expect {
          _get_action_instance(params: {
            :params => {
              "MinCapacity" => 1,
              "MaxCapacity" => 2,
              "Timeout" => 1,
              "Target" => invalid_targets
            }
          })
        }.to raise_error(/Invalid target/)
      end
    end
  end

  context '.valid_stages' do
    it 'returns value' do
      action = _get_valid_action_instance

      expect { action.valid_stages }.not_to raise_exception
      expect(action.valid_stages).to eq(
        %w(
          PreDeploy
          PostDeploy
          PreRelease
          PostRelease
          PreTeardown
          PostTeardown
        )
      )
      expect(action.valid_stages).to be_a Array
    end
  end

  context '.valid_components' do
    it 'valid_components' do
      action = _get_valid_action_instance

      expect { action.valid_components }.not_to raise_exception
      expect(action.valid_components).to eq(
        %w(
          aws/ecs-task
        )
      )
      expect(action.valid_components).to be_a Array
    end
  end

  context '.print_scalable_target' do
    it 'prints stuff' do
      action = _get_valid_action_instance

      result = nil

      expect { result = action.send(:print_scalable_target) }.not_to raise_exception
      expect(result).to eq("Executing SetScalableTarget (min 1, max 2) on component my-component @deployed")
    end
  end

  context '.invoke' do
    it 'does nothing on-non released build' do
      expect(Context).to receive_message_chain('persist.released_build_number')
        .and_return(nil)

      expect {
        action = _get_action_instance(params: {
          :params => {
            "MinCapacity" => 1,
            "MaxCapacity" => 2,
            "Timeout" => 1,
            "Target" => "@released"
          }
        })

        action.invoke
      }.not_to raise_error
    end

    it 'does nothing empty scalable target name' do
      expect(Context).to receive_message_chain('persist.released_build_number')
        .and_return(1)

      allow(Context).to receive_message_chain('component.variable')
        .with('my-component', anything, nil, 1)
        .and_return(nil)

      allow(Context).to receive_message_chain('component.stack_id')
        .and_return(nil)

      expect {
        action = _get_action_instance(params: {
          :params => {
            "MinCapacity" => 1,
            "MaxCapacity" => 2,
            "Timeout" => 1,
            "Target" => "@released"
          }
        })
        action.invoke
      }.not_to raise_error
    end

    it 'updates scalable target capacity on non-empty scalable target name' do
      expect(Context).to receive_message_chain('persist.released_build_number')
        .and_return(1)

      allow(Context).to receive_message_chain('component.variable')
        .with('my-component', anything, nil, 1)
        .and_return("test|test")

      allow(Context).to receive_message_chain('component.stack_id')
        .and_return(2)

      expect {
        action = _get_action_instance(params: {
          :params => {
            "MinCapacity" => 1,
            "MaxCapacity" => 2,
            "Timeout" => 1,
            "Target" => "@released"
          }
        })

        allow(action).to receive(:build_template).and_return({
          "Resources" => {
            "my-ScalableTarget" => {
              "Properties" =>{
                "ServiceNamespace" => "mock_ServiceNamespace"
              }
            }
          }
        })
        allow(AwsHelper).to receive(:cfn_update_stack)
        allow(AwsHelper).to receive(:_cfn_get_stack_status)                
        allow(AwsHelper).to receive(:scalable_target_wait_for_capacity)
        allow(AwsHelper).to receive(:s3_download_objects)

        allow(action).to receive(:_process_features).and_return(nil)

        action.invoke
      }.not_to raise_error
    end

    it 'raises on stop_on_error = true' do
      expect(Context).to receive_message_chain('persist.released_build_number')
      .and_return(1)

      allow(Context).to receive_message_chain('component.variable')
        .with('my-component', anything, nil, 1)
        .and_return("test|test")

      allow(Context).to receive_message_chain('component.stack_id')
        .and_return(2)
      
      action = _get_action_instance(params: {
        :params => {
          "MinCapacity" => 1,
          "MaxCapacity" => 2,
          "Timeout" => 1,
          "Target" => "@released"
        }
      })

      allow(action).to receive(:build_template).and_return({
        "Resources" => {
          "my-ScalableTarget" => {
            "Properties" =>{
              "ServiceNamespace" => "mock_ServiceNamespace"
            }
          }
        }
      })
      allow(AwsHelper).to receive(:cfn_update_stack)
      allow(AwsHelper).to receive(:_cfn_get_stack_status)                
      allow(AwsHelper).to receive(:scalable_target_wait_for_capacity).and_raise('cannot scale - sorry')
     
      expect {
        action.invoke
      }.to raise_error(/cannot scale - sorry/)
    end

    it 'does not raise on stop_on_error = false' do
      expect(Context).to receive_message_chain('persist.released_build_number')
      .and_return(1)

      allow(Context).to receive_message_chain('component.variable')
        .with('my-component', anything, nil, 1)
        .and_return("test|test")

      allow(Context).to receive_message_chain('component.stack_id')
        .and_return(2)

      action = _get_action_instance(params: {
        :params => {
          "MinCapacity" => 1,
          "MaxCapacity" => 2,
          "Timeout" => 1,
          "Target" => "@released",
          "StopOnError" => false
        }
      })

      allow(action).to receive(:build_template).and_return({
        "Resources" => {
          "my-ScalableTarget" => {
            "Properties" =>{
              "ServiceNamespace" => "mock_ServiceNamespace"
            }
          }
        }
      })
      allow(AwsHelper).to receive(:cfn_update_stack)
      allow(AwsHelper).to receive(:_cfn_get_stack_status)                
      allow(AwsHelper).to receive(:scalable_target_wait_for_capacity).and_raise('cannot scale - sorry')

      expect {
        action.invoke
      }.to_not raise_error
    end
  end

  context '.build_template' do
    it 'raises on empty resource' do
      action = _get_action_instance(params: {
        :params => {
          "MinCapacity" => 1,
          "MaxCapacity" => 2,
          "Timeout" => 1,
          "Target" => "@released",
          "StopOnError" => false
        }
      })

      allow(AwsHelper).to receive(:cfn_get_template)
      allow(JsonTools).to receive(:get).and_return(nil)

      expect {
        result = action.send(:build_template)
      }.to raise_error(/does not exist in target build/)
    end

    it 'returns template' do
      action = _get_action_instance(params: {
        :params => {
          "MinCapacity" => 1,
          "MaxCapacity" => 2,
          "Timeout" => 1,
          "Target" => "@released",
          "StopOnError" => false
        }
      })

      allow(AwsHelper).to receive(:cfn_get_template)
        .and_return({
          "Resources" => {
            "my-ScalableTarget" => {
              "Properties" =>{
                "ServiceNamespace" => "mock_ServiceNamespace",
                "MaxCapacity" => 0,
                "MinCapacity" => 0
              }
            }
          }
        })



      resource = {
        "Properties" => {
        "ServiceNamespace" => "mock_ServiceNamespace",
        "MaxCapacity" => 0,
        "MinCapacity" => 0
        }
      }
      allow(JsonTools).to receive(:get)
        .with(anything, anything, anything)
        .and_return(resource)

      result = nil

      expect {
        result = action.send(:build_template)
      }.not_to raise_error

      expect(result).not_to be(nil)
      expect(result.class).to eq(Hash)
    end
   end
end # RSpec.describe
