$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/consumables/aws/"))
require 'consumables/aws/actions/http_request'
require 'consumables/aws/aws_instance'
require 'consumable'

RSpec.describe HTTPRequest do
  before do
    @args = {
      params: {
        'URL' => 'http://www.dummy.com'
      },
      stage: "PreRelease",
      step: "01"
    }
  end

  it 'valid_stages' do
    instance = double Consumable
    allow(instance).to receive(:type).and_return('aws/instance')
    expect {
      kwargs = { component: instance }.merge @args
      @http_request = HTTPRequest.new(**kwargs)
    }.not_to raise_exception

    expect { @http_request.valid_stages }.not_to raise_exception
    expect(@http_request.valid_stages).to be_a Array
  end

  it 'valid_components' do
    instance = double Consumable
    allow(instance).to receive(:type).and_return('aws/instance')
    expect {
      kwargs = { component: instance }.merge(@args)
      @http_request = HTTPRequest.new(**kwargs)
    }.not_to raise_exception

    expect { @http_request.valid_stages }.not_to raise_exception
    expect(@http_request.valid_stages).to be_a Array
  end

  it 'run_at valid stage' do
    instance = double Consumable
    allow(instance).to receive(:type).and_return('aws/instance')
    expect {
      kwargs = { component: instance }.merge @args
      @http_request = HTTPRequest.new(**kwargs)
    }.not_to raise_exception

    expect(@http_request.run_at? 'PreRelease').to eq(true)
    expect(@http_request.run_at? 'PostTeardown').to eq(true)
  end

  it 'run_by valid component' do
    instance = double Consumable
    allow(instance).to receive(:type).and_return('aws/instance')
    expect {
      kwargs = { component: instance }.merge @args
      @http_request = HTTPRequest.new(**kwargs)
    }.not_to raise_exception

    expect(@http_request.run_by? 'aws/instance').to eq(true)
    expect(@http_request.run_by? 'aws/sqs').to eq(true)
  end

  it 'invoke success' do
    instance = double Consumable

    allow(instance).to receive(:type).and_return('aws/instance')

    expect {
      kwargs = { component: instance }.merge @args
      @http_request = HTTPRequest.new(**kwargs)
    }.not_to raise_exception

    response = double(Object)

    allow(Pipeline::Helpers::HTTP).to receive(:public_send).and_return(response)
    allow(response).to receive(:code).and_return('200')
    allow(response).to receive(:body).and_return({ key: 'value' })
    allow(instance).to receive(:component_name).and_return('my-app')
    allow(Log).to receive(:output)
    expect { @http_request.invoke }.not_to raise_exception
  end

  it 'invoke failure' do
    instance = double Consumable

    allow(instance).to receive(:type).and_return('aws/instance')

    expect {
      kwargs = { component: instance }.merge @args
      @http_request = HTTPRequest.new(**kwargs)
    }.not_to raise_exception

    response = double(Object)

    allow(Pipeline::Helpers::HTTP).to receive(:public_send).and_return(response)
    allow(response).to receive(:code).and_return('304')
    allow(response).to receive(:body).and_return({ key: 'value' })
    allow(instance).to receive(:component_name).and_return('my-app')
    allow(Log).to receive(:error)
    expect { @http_request.invoke }.to raise_error RuntimeError
  end

  it 'decrypt_screts_success' do
    instance = double Consumable
    allow(instance).to receive(:type).and_return('aws/instance')
    expect {
      kwargs = { component: instance }.merge @args
      @http_request = HTTPRequest.new(**kwargs)
    }.not_to raise_exception
    allow(AwsHelper).to receive(:kms_decrypt_data).and_return('unencrypted_dummy')
    expect(@http_request.send(:decrypt_secret, 'Username', 'dummy')).to eq('unencrypted_dummy')
  end

  it 'decrypt_screts_failure' do
    instance = double Consumable
    allow(instance).to receive(:type).and_return('aws/instance')
    expect {
      kwargs = { component: instance }.merge @args
      @http_request = HTTPRequest.new(**kwargs)
    }.not_to raise_exception
    allow(AwsHelper).to receive(:kms_decrypt_data).and_raise(ActionError)
    expect { @http_request.send(:decrypt_secret, 'Username', 'dummy') }.to raise_error(RuntimeError)
  end
end # RSpec.describe
