require 'sinatra'
require 'json'

get '/' do
  'Demo Application'
end

get '/qcp-pipeline-dev/build' do
  content_type :json
  {'build' => ENV['instance_amzn_BuildNumber']}.to_json
end

get '/qcp-pipeline-dev/environment' do
  content_type :json
  {'build' => Hash(ENV)}.to_json
end



