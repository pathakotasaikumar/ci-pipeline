#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'json'
require 'aws-sdk'

SNOW_URL = ENV['SNOW_URL'] || 'https://qantas.service-now.com'

def snow_request(uri, user, password)
  request = Net::HTTP::Get.new(uri)
  request['Accept'] = 'application/json'
  req_options = {
    use_ssl: uri.scheme == 'https',
  }
  request.basic_auth user, password
  response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
    http.request(request)
  end
  return JSON.parse(response.body)
end

def query_snow_table(table, user, password, qs)
  # See the following for query string operators
  # https://docs.servicenow.com/bundle/rome-platform-user-interface/page/use/common-ui-elements/reference/r_OpAvailableFiltersQueries.html
  uri = URI.parse("#{SNOW_URL}/api/now/table/#{table}?sysparm_query=#{qs}")
  snow_request(uri, user, password)
end

def get_ssm_parameters
  role_credentials = Aws::AssumeRoleCredentials.new(
    client: Aws::STS::Client.new,
    role_arn: 'arn:aws:iam::221295517176:role/CD-Control',
    role_session_name: 'get-ssm-parameters'
  )
  ssm = Aws::SSM::Client.new(credentials: role_credentials)
  params = {}
  response = ssm.get_parameters({
    names: ['/pipeline/snow_user', '/pipeline/snow_password', '/pipeline/splunk_token_password'],
    with_decryption: true
  })
  response.parameters.each do |param|
    if param.name == '/pipeline/snow_user'
      params[:snow_user] = param.value
    elsif param.name == '/pipeline/snow_password'
      params[:snow_password] = param.value
    elsif param.name == '/pipeline/splunk_token_password'
      params[:splunk_hec] = param.value
    end
  end
  return params
end

def run
  if ARGV.empty?
    STDERR.puts 'Usage: ./bin/app_info.rb <repository-name>'
    exit 1
  end

  ssm_parameters = get_ssm_parameters()
  user = ssm_parameters[:snow_user]
  password = ssm_parameters[:snow_password]
  splunk_token_password = ssm_parameters[:splunk_hec]

  if ARGV[0] == "--splunk-token-only"
    puts JSON.generate({
      :splunk_token_password => splunk_token_password,
    })
    exit 0
  end

  repository = ARGV[0].delete_prefix('qantas-cloud/').delete_prefix 'qcp-test/'
  app_id, service_name = repository.split('-', 2)
  app_id = app_id.upcase
  
  if app_id == 'C000'
    ams_id = 'AMS01'
  else
    qda_info = query_snow_table(
      'u_ams_application',
      user,
      password,
      "u_app_inventory_id=#{app_id}"
    )

    if qda_info['result'].length != 1
      STDERR.puts "Application #{app_id} does not exist in Service Now"
      exit 1
    end

    ams_partner_url = qda_info['result'].first()['u_ams_partner']['link']
    ams_partner_id = qda_info['result'].first()['u_ams_partner']['value']
    ams_info = snow_request(URI.parse(ams_partner_url), user, password)

    ams_id = ams_info['result']['u_number']
  end

  service_info = query_snow_table(
    'u_ams_application_service',
    user,
    password,
    "u_application_service_short_name=#{service_name}^ORu_application_service_short_name=#{service_name.sub('_', '-')}^ORname=#{service_name}^u_app_idSTARTSWITH#{app_id}-"
  )

  if service_info['result'].length != 1
    STDERR.puts "Application Service #{service_name} does not exist in Service Now"
    exit 1
  end

  app_service_id = service_info['result'].first()['u_app_id'].split("-", 2).last

  account_info = query_snow_table(
    'u_qcp_aws_account',
    user,
    password,
    "u_ams_partner=#{ams_partner_id}"
  )

  if account_info['result'].empty?
    STDERR.puts "No AWS accounts found for #{ams_id}"
    exit 1
  end

  accounts = {:prod => {}, :nonprod => {}}

  account_info['result'].each do |account|
    account_id = account['u_aws_account_id']
    account_type = account['u_account_type']
    environment = account['u_account_environment']
    if environment == "Production"
      accounts[:prod][account_type.downcase] = account_id
    elsif environment == "Non Production"
      accounts[:nonprod][account_type.downcase] = account_id
    end
  end

  puts JSON.generate({
    :ams_id => ams_id,
    :app_id => app_id,
    :app_service_name => service_name,
    :app_service_id => app_service_id,
    :splunk_token_password => splunk_token_password,
    :accounts => accounts
  })
end

run if $PROGRAM_NAME == __FILE__
