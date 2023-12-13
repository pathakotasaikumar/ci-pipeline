# $LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/pipeline/helpers/"))
require 'pipeline/helpers/http'

RSpec.describe Pipeline::Helpers::HTTP do
  before do
    @args = {
      url: "http://www.dummy.com",
      ssl: true,
      user: 'dummy',
      pass: 'dummy',
      headers: {}
    }
  end

  it 'http' do
    http = double(Net::HTTP)
    uri = URI('http://www.dummy.com')
    allow(http).to receive(:new)
    expect(Pipeline::Helpers::HTTP.send(:http, uri, false)).to be_a(Net::HTTP)
  end

  it 'http_ssl' do
    http = double(Net::HTTP)
    uri = URI('http://www.dummy.com')
    allow(http).to receive(:new)
    expect(Pipeline::Helpers::HTTP.send(:http, uri, true)).to be_a(Net::HTTP)
  end

  it 'add_headers' do
    req = Net::HTTP::Get.new('dummy_msg')
    headers = { 'this' => 'that', 'that' => 'this' }
    result = Pipeline::Helpers::HTTP.send(:add_headers, request: req, headers: headers)
    expect(result).to be_a(Net::HTTP::Get)
    expect(result['this']).to eq('that')
    expect(result['that']).to eq('this')
  end

  it 'get' do
    http_client = double(Net::HTTP)
    http_ok = double(Net::HTTPOK)
    allow(Pipeline::Helpers::HTTP).to receive(:http).and_return(http_client)
    allow(http_client).to receive(:request).and_return(http_ok)
    expect(Pipeline::Helpers::HTTP.get(url: 'http://www.dummyasdasdasd.com', ssl: false)).to eq(http_ok)
  end

  it 'post' do
    http_client = double(Net::HTTP)
    http_ok = double(Net::HTTPOK)
    allow(Pipeline::Helpers::HTTP).to receive(:http).and_return(http_client)
    allow(http_client).to receive(:request).and_return(http_ok)
    expect(Pipeline::Helpers::HTTP.post(url: 'http://www.dummyasdasdasd.com', ssl: false)).to eq(http_ok)
  end

  it 'put' do
    http_client = double(Net::HTTP)
    http_ok = double(Net::HTTPOK)
    allow(Pipeline::Helpers::HTTP).to receive(:http).and_return(http_client)
    allow(http_client).to receive(:request).and_return(http_ok)
    expect(Pipeline::Helpers::HTTP.put(url: 'http://www.dummyasdasdasd.com', ssl: false)).to eq(http_ok)
  end
end # RSpec.describe
