$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/consumables/aws/"))
require 'consumables/aws/actions/set_weight_route_policy'
require 'consumables/aws/aws_route53'
require 'consumable'

RSpec.describe 'SetWeightRoutePolicy' do
  before do
    @args = {
      params: {
        'Weight' => '5',
        'RecordSet' => 'PrimaryApi',
        'Status' => 'Healthy'
      },
      stage: "PreRelease",
      step: "01"
    }
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end
  it 'valid_stages' do
    route53 = double Consumable
    allow(route53).to receive(:type).and_return('aws/route53')
    expect {
      kwargs = { component: route53 }.merge @args
      @action = SetWeightRoutePolicy.new(**kwargs)
    }.not_to raise_exception

    expect { @action.valid_stages }.not_to raise_exception
    expect(@action.valid_stages).to be_a Array
  end

  it 'Test Unknown targer option' do
    route53 = double Consumable
    allow(route53).to receive(:type).and_return('aws/route53')
    allow(route53).to receive(:component_name).and_return('my-app')
    args = {
      params: {
        'Weight' => '5',
        'RecordSet' => 'PrimaryApi',
        'Status' => 'Healthy',
        'Target' => '@teradown'
      },
      stage: "PreRelease",
      step: "01"
    }
    expect {
      kwargs = { component: route53 }.merge args
      @action = SetWeightRoutePolicy.new(**kwargs)
    }.to raise_exception(RuntimeError, /Unknown value for @teradown, expected/)
  end

  it 'valid_components' do
    route53 = double Consumable
    allow(route53).to receive(:type).and_return('aws/route53')
    expect {
      kwargs = { component: route53 }.merge @args
      @action = SetWeightRoutePolicy.new(**kwargs)
    }.not_to raise_exception

    expect { @action.valid_stages }.not_to raise_exception
    expect(@action.valid_stages).to be_a Array
  end

  context 'invoke' do
    it 'Not to raise exception' do
      route53 = double Consumable
      allow(route53).to receive(:type).and_return('aws/route53')
      expect {
        kwargs = { component: route53 }.merge @args
        @action = SetWeightRoutePolicy.new(**kwargs)
      }.not_to raise_exception

      allow(@action).to receive(:invoke)
    end

    it 'Successful update' do
      route53 = double Consumable
      allow(route53).to receive(:type).and_return('aws/route53')
      allow(route53).to receive(:component_name).and_return('my-app')
      kwargs = { component: route53 }.merge @args
      route53_action = SetWeightRoutePolicy.new(**kwargs)
      allow(route53_action).to receive(:_template).and_return(@test_data["Input"])
      allow(Context).to receive_message_chain('component.stack_id').and_return('ams01-c031-01-dev-master-dns')
      allow(Context).to receive_message_chain("component.variable").and_return("23fsas-24sds")
      allow(AwsHelper).to receive(:_route53_check_health_status)
      allow(AwsHelper).to receive(:cfn_update_stack)
      expect { route53_action.invoke }.not_to raise_exception
    end

    it 'Test failure' do
      route53 = double Consumable
      allow(route53).to receive(:type).and_return('aws/route53')
      allow(route53).to receive(:component_name).and_return('my-app')
      kwargs = { component: route53 }.merge @args
      route53_action = SetWeightRoutePolicy.new(**kwargs)
      allow(route53_action).to receive(:_template).and_return(@test_data["Input"])
      allow(Context).to receive_message_chain('component.stack_id').and_return('ams01-c031-01-dev-master-dns')
      allow(Context).to receive_message_chain("component.variable").and_return("23fsas-24sds")
      allow(AwsHelper).to receive(:_route53_check_health_status).and_raise(RuntimeError)
      allow(AwsHelper).to receive(:cfn_update_stack)
      expect { route53_action.invoke }.to raise_exception RuntimeError
    end

    it 'Test @released' do
      route53 = double Consumable
      allow(route53).to receive(:type).and_return('aws/route53')
      allow(route53).to receive(:component_name).and_return('my-app')
      args = {
        params: {
          'Weight' => '5',
          'RecordSet' => 'PrimaryApi',
          'Status' => 'Healthy',
          'Target' => '@released'
        },
        stage: "PreRelease",
        step: "01"
      }
      kwargs = { component: route53 }.merge args
      route53_action = SetWeightRoutePolicy.new(**kwargs)
      allow(Context).to receive_message_chain('persist.released_build_number').and_return(nil)
      allow(route53_action).to receive(:_template).and_return(@test_data["Input"])
      allow(Context).to receive_message_chain('component.stack_id').and_return('ams01-c031-01-dev-master-dns')
      allow(Context).to receive_message_chain("component.variable").and_return("23fsas-24sds")
      allow(AwsHelper).to receive(:_route53_check_health_status).and_raise(RuntimeError)
      allow(AwsHelper).to receive(:cfn_update_stack)
      expect { route53_action.invoke }.not_to raise_exception
    end

    it 'test nil stack_id without @stop_on_error' do
      route53 = double Consumable
      allow(route53).to receive(:type).and_return('aws/route53')
      allow(route53).to receive(:component_name).and_return('my-app')
      kwargs = { component: route53 }.merge @args
      route53_action = SetWeightRoutePolicy.new(**kwargs)
      allow(route53_action).to receive(:_template).and_return(@test_data["Input"])
      allow(Context).to receive_message_chain('component.stack_id').and_return(nil)
      allow(Context).to receive_message_chain("component.variable").and_return("23fsas-24sds")
      allow(AwsHelper).to receive(:_route53_check_health_status)
      allow(AwsHelper).to receive(:cfn_update_stack)
      expect { route53_action.invoke }.to raise_error /Cannot find stack id for target/
    end

    it 'test nil stack_id with @stop_on_error as false' do
      route53 = double Consumable
      allow(route53).to receive(:type).and_return('aws/route53')
      args = {
        params: {
          'Weight' => '5',
          'RecordSet' => 'PrimaryApi',
          'Status' => 'Healthy',
          'StopOnError' => false
        },
        stage: "PreRelease",
        step: "01"
      }
      allow(route53).to receive(:component_name).and_return('my-app')
      kwargs = { component: route53 }.merge args
      route53_action = SetWeightRoutePolicy.new(**kwargs)
      allow(route53_action).to receive(:_template).and_return(@test_data["Input"])
      allow(Context).to receive_message_chain('component.stack_id').and_return(nil)
      allow(Context).to receive_message_chain("component.variable").and_return("23fsas-24sds")
      allow(AwsHelper).to receive(:_route53_check_health_status)
      allow(AwsHelper).to receive(:cfn_update_stack)
      expect { route53_action.invoke }.not_to raise_exception
    end

    it 'test nil healthcheck  without @stop_on_error' do
      route53 = double Consumable
      allow(route53).to receive(:type).and_return('aws/route53')
      allow(route53).to receive(:component_name).and_return('my-app')
      kwargs = { component: route53 }.merge @args
      route53_action = SetWeightRoutePolicy.new(**kwargs)
      allow(route53_action).to receive(:_template).and_return({})
      allow(Context).to receive_message_chain('component.stack_id').and_return('ams01-c031-01-dev-master-dns')
      allow(Context).to receive_message_chain("component.variable").and_return("23fsas-24sds")
      allow(AwsHelper).to receive(:_route53_check_health_status)
      allow(AwsHelper).to receive(:cfn_update_stack)
      expect { route53_action.invoke }.to raise_error /Cannot find stack healthcheck id for target/
    end

    it 'test nil healthcheck with @stop_on_error as false' do
      route53 = double Consumable
      allow(route53).to receive(:type).and_return('aws/route53')
      args = {
        params: {
          'Weight' => '5',
          'RecordSet' => 'PrimaryApi',
          'Status' => 'Healthy',
          'StopOnError' => false
        },
        stage: "PreRelease",
        step: "01"
      }
      allow(route53).to receive(:component_name).and_return('my-app')
      kwargs = { component: route53 }.merge args
      route53_action = SetWeightRoutePolicy.new(**kwargs)
      allow(route53_action).to receive(:_template).and_return({})
      allow(Context).to receive_message_chain('component.stack_id').and_return('ams01-c031-01-dev-master-dns')
      allow(Context).to receive_message_chain("component.variable").and_return("23fsas-24sds")
      allow(AwsHelper).to receive(:_route53_check_health_status)
      allow(AwsHelper).to receive(:cfn_update_stack)
      expect { route53_action.invoke }.not_to raise_exception
    end

    it 'Testing cfn_update_stack failure with @stop_on_error false' do
      route53 = double Consumable
      allow(route53).to receive(:type).and_return('aws/route53')
      args = {
        params: {
          'Weight' => '5',
          'RecordSet' => 'PrimaryApi',
          'Status' => 'Healthy',
          'StopOnError' => false
        },
        stage: "PreRelease",
        step: "01"
      }
      allow(route53).to receive(:component_name).and_return('my-app')
      kwargs = { component: route53 }.merge args
      route53_action = SetWeightRoutePolicy.new(**kwargs)
      allow(route53_action).to receive(:_template).and_return(@test_data["Input"])
      allow(Context).to receive_message_chain('component.stack_id').and_return('ams01-c031-01-dev-master-dns')
      allow(Context).to receive_message_chain("component.variable").and_return("23fsas-24sds")
      allow(AwsHelper).to receive(:_route53_check_health_status).and_raise(RuntimeError)
      allow(AwsHelper).to receive(:cfn_update_stack)
      expect { route53_action.invoke }.not_to raise_exception
    end
  end

  context '_template' do
    it 'return validate template' do
      route53 = double Consumable
      allow(route53).to receive(:type).and_return('aws/route53')
      kwargs = { component: route53 }.merge @args
      route53_action = SetWeightRoutePolicy.new(**kwargs)

      allow(AwsHelper).to receive(:cfn_get_template).and_return(@test_data["Input"])
      expect(route53_action.send(:_template, stack_id: "stackid-123", weight_value: 5, record_set: 'PrimaryApi')).to eq(@test_data["Output"])
    end

    it 'Expect error' do
      route53 = double Consumable
      allow(route53).to receive(:type).and_return('aws/route53')
      kwargs = { component: route53 }.merge @args
      route53_action = SetWeightRoutePolicy.new(**kwargs)

      allow(AwsHelper).to receive(:cfn_get_template).and_return(@test_data["ErrorInput"])
      expect {
        route53_action.send(:_template, stack_id: "stackid-123", weight_value: 5, record_set: 'PrimaryApi')
      }.to raise_exception /does not have value for Weighted Alias/
    end
  end
end
