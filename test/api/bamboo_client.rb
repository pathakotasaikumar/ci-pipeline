require 'json'

class BambooClient

  def initialize(instance_name)
    require 'httpclient'
    require 'httpclient/webagent-cookie'
    bamboo_config = JSON.parse(File.read(File.join(__dir__, "bamboo_client_config.json")))
    @host = bamboo_config[instance_name]["Host"]
    @port = bamboo_config[instance_name]["Port"]
    @protocol = bamboo_config[instance_name]["Protocol"]
    @base_url = @protocol +"://" + @host +":" + @port+"/rest/api/latest"

    @user = bamboo_config[instance_name]["User"]
    @pass = bamboo_config[instance_name]["Pass"]
    @queue_url  = @base_url + '/queue'
    @result_url = @base_url + '/result'
    @project_id = ""
    @plan_id = ""
    @project_plan_url =""

    @BuildResult = Struct.new(:buildNumber,:failedTestCount,:buildState,:successfulTestCount,:skippedTestCount)
    @clnt = HTTPClient.new

  end

  def set_project_plan(project,plan)
    @project_id =  project
    @plan_id = plan
    @project_plan_url =  "/" + @project_id+'-'+@plan_id
  end

  def pre_validate()
    if @project_id == ""
      raise "project_id not defined, use set_project_plan(project,plan)"
    end
    if @plan_id ==""
      raise "plan_id not defined, use set_project_plan(project,plan)"
    end

  end

  # queue a plan with project and plan id.
  def build_plan(plan_variable_overrides = nil)
    pre_validate()
    if(get_build_result(get_lastest_build_id).buildState == "Unknown")
      raise "Cannot queue a plan when previous build status is still Unknown"
    end

    if plan_variable_overrides!= nil

      # parse variables and make url binder
      variable_overrides = ""
      plan_variable_overrides.each do |variable,value|
        variable_overrides = variable_overrides + "&bamboo.variable.#{variable}=#{value}"
      end

      execute_url(@queue_url + @project_plan_url+"?"+variable_overrides, :post)
    else
      execute_url(@queue_url + @project_plan_url, :post)
    end

    return get_lastest_build_id()
  end

  def get_lastest_build_id()
    pre_validate()
    response = execute_url(@result_url + @project_plan_url + "/?expand=results[0].result&includeAllStates", :get)
    return JSON.parse(response)["results"]["result"][0]["buildNumber"]
  end

  def poll_until_complete(poll_frequency_seconds = 6,time_out_seconds = 60)

    lastest_build_id = get_lastest_build_id

    have_time = true

    t1 = Time.now

    while have_time do

      if time_diff(t1,Time.now) > time_out_seconds
        have_time = false
      end

      if get_build_result(lastest_build_id).buildState != "Unknown"
        return true
      end

      sleep poll_frequency_seconds
    end

      raise "build taking longer than 60 seconds"
  end

  def time_diff(start, finish)
   (finish - start)
  end

  def get_build_logs(build_number,job_key)
    pre_validate()

    # response = execute_url(@result_url+@project_plan_url+"-#{job_key}"+ "/#{build_number}?expand=logEntries",:get)
    # return json_response["logEntries"]["logEntry"].join("\n")

    # this returns full log
    log_url = @protocol +"://" + @host + ":" + @port + "/download/#{@project_id}-#{@plan_id}-#{job_key}/build_logs/#{@project_id}-#{@plan_id}-#{job_key}-#{build_number}.log"
    response = execute_url(log_url,:get)
    return response

  end

  def get_build_result(build_number)

    pre_validate()
    response = execute_url(@result_url+@project_plan_url+ "/#{build_number}",:get)
    json_response = JSON.parse(response)
    build_result = @BuildResult.new
    build_result.buildNumber =  json_response["buildNumber"]
    build_result.successfulTestCount = json_response["successfulTestCount"]
    build_result.failedTestCount = json_response["failedTestCount"]
    build_result.skippedTestCount = json_response["skippedTestCount"]
    build_result.buildState = json_response["buildState"]
    return build_result
  end

  def execute_url(url, method )
    extheader = { 'Accept' => 'Application/json', 'X-Atlassian-Token'=>'nocheck' }
    @clnt.ssl_config.verify_mode = OpenSSL::SSL::VERIFY_NONE
    @clnt.set_auth(nil, @user, @pass)

    if(url.include?'?')
      url = url+"&os_authType=basic"
    else
      url = url+"?os_authType=basic"
    end

    if method == :get
      response = @clnt.get_content(url,query =nil, extheader)
    elsif method == :post
      response = @clnt.post(url,query =nil, extheader)
    end

    return response
  end



private :execute_url,:time_diff

end
