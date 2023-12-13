$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/consumables/aws/"))
require 'consumables/aws/actions/set_desired_capacity'
require 'consumables/aws/aws_autoscale'
require 'consumable'

RSpec.describe SetDesiredCapacity do
  before do
    @args = {
      stage: "PostDeploy",
      step: "01",
      params: {
        "MinSize" => 1,
        "MaxSize" => 2,
        "Timeout" => 200,
        "Target" => "@deployed"
      }
    }
  end

  def _get_action_instance(params: nil, component_type: 'aws/autoscale')
    instance = double Consumable

    allow(instance).to receive(:type).and_return(component_type)
    allow(instance).to receive(:component_name).and_return('my-component')

    allow(instance).to receive(:autoscaling_group).and_return({
      'my-autoscale' => '1'
    })
    allow(instance).to receive(:definition).and_return({ "Type" => "aws/autoheal", "Stage" => "01", "Persist" => false, "Configuration" => { "Features" => { "Type" => "Pipeline::Features", "Properties" => { "Features" => { "DataDog" => "enabled", "Qualys" => { "Enabled" => true, "Recipients" => ["test@qantas.com.au"] } } } } } })

    final_params = { component: instance }.merge(@args)
    if (params != nil)
      final_params = final_params.merge(params)
    end

    SetDesiredCapacity.new(**final_params)
  end

  def _get_valid_action_instance(params = nil, component_type: 'aws/autoscale')
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
            "MinSize" => 1,
            "MaxSize" => 2,
            "Timeout" => 1,
            "Target" => "@released"
          }
        })
      }.not_to raise_error
    end

    it 'fails on non-supported autoheal configiuration' do
      expect {
        _get_action_instance(params: {
          :params => {
            "MinSize" => 2,
            "MaxSize" => 2,
            "Timeout" => 1,
            "Target" => "@released"
          }
        },
                             component_type: 'aws/autoheal')
      }.to raise_error(/aws\/autoheal component only supports '0' and '1' for MinSize, MaxSize, and DesiredCapacity properties/)
    end

    it 'checks parameters' do
      invalid_timeouts = [
        -1,
        3601
      ]

      invalid_desired_capacities = [
        "deployed1",
        "released1"
      ]

      expect {
        _get_action_instance(params: {
          :params => { 'my' => 1 }
        })
      }.to raise_error(/MinSize and MaxSize must be specified/)

      invalid_timeouts.each do |invalid_timeout|
        expect {
          _get_action_instance(params: {
            :params => {
              "MinSize" => 1,
              "MaxSize" => 2,
              "Timeout" => invalid_timeout
            }
          })
        }.to raise_error(/Invalid timeout/)
      end

      invalid_desired_capacities.each do |invalid_desired_capacity|
        expect {
          _get_action_instance(params: {
            :params => {
              "MinSize" => 1,
              "MaxSize" => 2,
              "Timeout" => 1,
              "Target" => invalid_desired_capacity
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
          aws/autoscale
          aws/autoheal
        )
      )
      expect(action.valid_components).to be_a Array
    end
  end

  context '.print_desired_capacity' do
    it 'prints stuff' do
      action = _get_valid_action_instance

      result = nil

      expect { result = action.send(:print_desired_capacity) }.not_to raise_exception
      expect(result).to eq('Executing SetDesiredCapacity (min 1, desired X, max 2) on component my-component @deployed ASG, ')
    end
  end

  context '.invoke' do
    it 'does nothing on-non released build' do
      expect(Context).to receive_message_chain('persist.released_build_number')
        .and_return(nil)

      expect {
        action = _get_action_instance(params: {
          :params => {
            "MinSize" => 1,
            "MaxSize" => 2,
            "Timeout" => 1,
            "Target" => "@released"
          }
        })

        action.invoke
      }.not_to raise_error
    end

    it 'does nothing empty autoscale group name' do
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
            "MinSize" => 1,
            "MaxSize" => 2,
            "Timeout" => 1,
            "Target" => "@released"
          }
        })
        action.invoke
      }.not_to raise_error
    end

    it 'updates autoscale capacity on non-empty autoscale group name' do
      expect(Context).to receive_message_chain('persist.released_build_number')
        .and_return(1)

      allow(Context).to receive_message_chain('component.variable')
        .with('my-component', anything, nil, 1)
        .and_return(1)

      allow(Context).to receive_message_chain('component.stack_id')
        .and_return(2)

      expect {
        action = _get_action_instance(params: {
          :params => {
            "MinSize" => 1,
            "MaxSize" => 2,
            "Timeout" => 1,
            "Target" => "@released"
          }
        })

        allow(action).to receive(:build_template).and_return({
          "Template" => "value"
        })

        allow(action).to receive(:_process_features).and_return(nil)

        allow(AwsHelper).to receive(:cfn_update_stack)
        allow(AwsHelper).to receive(:autoscaling_wait_for_capacity)
        allow(AwsHelper).to receive(:s3_download_objects)

        action.invoke
      }.not_to raise_error
    end

    it 'sets autoscale capacity on non-empty autoscale group name' do
      expect(Context).to receive_message_chain('persist.released_build_number')
        .and_return(1)

      allow(Context).to receive_message_chain('component.variable')
        .with('my-component', anything, nil, 1)
        .and_return(1)

      allow(Context).to receive_message_chain('component.stack_id')
        .and_return(2)

      expect {
        action = _get_action_instance(params: {
          :params => {
            "MinSize" => 1,
            "MaxSize" => 2,
            "Timeout" => 1,
            "Target" => "@released"
          }
        })

        allow(action).to receive(:build_template).and_return(nil)
        allow(JsonTools).to receive(:get).and_return('wait_condition')
        allow(Context).to receive_message_chain('s3.artefact_bucket_name')
        allow(Defaults).to receive_message_chain('log_upload_path')

        allow(AwsHelper).to receive(:autoscaling_set_capacity)
        allow(AwsHelper).to receive(:autoscaling_wait_for_capacity)
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
        .and_return(1)

      allow(Context).to receive_message_chain('component.stack_id')
        .and_return(2)

      action = _get_action_instance(params: {
        :params => {
          "MinSize" => 1,
          "MaxSize" => 2,
          "Timeout" => 1,
          "Target" => "@released"
        }
      })

      allow(action).to receive(:build_template).and_return(nil)
      allow(JsonTools).to receive(:get).and_return('wait_condition')
      allow(Context).to receive_message_chain('s3.artefact_bucket_name')
      allow(Defaults).to receive_message_chain('log_upload_path')

      allow(AwsHelper).to receive(:autoscaling_set_capacity)
      allow(AwsHelper).to receive(:s3_download_objects)
      allow(AwsHelper).to receive(:autoscaling_wait_for_capacity).and_raise('cannot scale - sorry')

      expect {
        action.invoke
      }.to raise_error(/cannot scale - sorry/)
    end

    it 'does not raise on stop_on_error = false' do
      expect(Context).to receive_message_chain('persist.released_build_number')
        .and_return(1)

      allow(Context).to receive_message_chain('component.variable')
        .with('my-component', anything, nil, 1)
        .and_return(1)

      allow(Context).to receive_message_chain('component.stack_id')
        .and_return(2)

      action = _get_action_instance(params: {
        :params => {
          "MinSize" => 1,
          "MaxSize" => 2,
          "Timeout" => 1,
          "Target" => "@released",
          "StopOnError" => false
        }
      })

      allow(action).to receive(:build_template).and_return(nil)
      allow(JsonTools).to receive(:get).and_return('wait_condition')
      allow(Context).to receive_message_chain('s3.artefact_bucket_name')
      allow(Defaults).to receive_message_chain('log_upload_path')

      allow(AwsHelper).to receive(:autoscaling_set_capacity)
      allow(AwsHelper).to receive(:s3_download_objects)
      allow(AwsHelper).to receive(:autoscaling_wait_for_capacity).and_raise('cannot scale - sorry')

      expect {
        action.invoke
      }.to_not raise_error
    end
  end

  context '.build_template' do
    it 'raises on empty resource' do
      action = _get_action_instance(params: {
        :params => {
          "MinSize" => 1,
          "MaxSize" => 2,
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

    it 'returns nil if previous_wait_condition_name = nil' do
      action = _get_action_instance(params: {
        :params => {
          "MinSize" => 1,
          "MaxSize" => 2,
          "Timeout" => 1,
          "Target" => "@released",
          "StopOnError" => false
        }
      })

      allow(AwsHelper).to receive(:cfn_get_template)
      allow(JsonTools).to receive(:get)
        .with(anything, anything, anything)
        .and_return("resource")
      allow(JsonTools).to receive(:get)
        .with(anything, "Metadata.WAIT_CONDITION", anything)
        .and_return(nil)

      expect {
        result = action.send(:build_template)

        expect(result).to eq(nil)
      }.not_to raise_error
    end

    it 'returns template' do
      action = _get_action_instance(params: {
        :params => {
          "MinSize" => 1,
          "MaxSize" => 2,
          "Timeout" => 1,
          "Target" => "@released",
          "StopOnError" => false
        }
      })

      allow(AwsHelper).to receive(:cfn_get_template)
        .and_return({
          "Resources" => {
            "WaitCondition1" => []
          }
        })
      allow(JsonTools).to receive(:get)
        .with(anything, anything, anything)
        .and_return({
          "Properties" => {
            "MaxSize" => 0
          },
          "Metadata" => {

          }
        })

      allow(JsonTools).to receive(:get)
        .with(anything, "Metadata.WAIT_CONDITION", anything)
        .and_return("WaitCondition1")

      result = nil

      expect {
        result = action.send(:build_template)
      }.not_to raise_error

      expect(result).not_to be(nil)
      expect(result.class).to eq(Hash)
    end
  end
end # RSpec.describe
