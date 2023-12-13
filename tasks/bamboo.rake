require 'rake'
require 'aws-sdk-core'
require 'json'
require "#{BASE_DIR}/lib/aws_helper_class"

Aws.config.update(
  region: 'ap-southeast-2'
)

task :bamboo do
  env_name = "bamboo_PIPELINE_EXEC"
  Log.info("Checking if the pipeline is run from bamboo")
  params = {
    proxy: Defaults.proxy,
    region: Defaults.region,
    control_role: Defaults.control_role
  }
  if ENV.has_key?(env_name)
    case ENV[env_name]

      when "limited"
        data, _ = AwsHelper.s3_get_object('qcp-pipeline','toggle/whitelist.json')
        whitelist = JSON.parse(data)
        # Split the plan name in to base + branch index (if it exists)  
        # "P000S113DEV" -> P000S113DEV/P000S113/DEV/nil
        # "P000S113DEV0" -> P000S113DEV0/P000S113/DEV/0
        shortkey = ENV['bamboo_shortPlanKey']
        planbase = nil
        planregex = shortkey.match(/^(.*?)([A-Z]+)([0-9]+)?$/)

        if planregex
          planbase = planregex[1]
        end

        Log.info("Checking plan #{shortkey} against whitelist")
        if whitelist.include?(shortkey)
          Log.info("Plan #{shortkey} has been explicitly enabled")
        elsif whitelist.include?(planbase) 
          Log.info("Plan #{planbase} has been whitelisted, for now ")
        else
          Log.error("Plan #{planbase} is not whitelisted, run denied")
          Log.error("You are no longer able to deploy using bamboo, please see https://confluence.qantas.com.au/display/QOP/QCP+Deployment+Pipeline+Migration")
          exit 1
        end

      when "disabled"
        Log.error("You are no longer able to deploy using bamboo, please see https://confluence.qantas.com.au/display/QOP/QCP+Deployment+Pipeline+Migration")
        raise("You are no longer able to deploy using bamboo, please see https://confluence.qantas.com.au/display/QOP/QCP+Deployment+Pipeline+Migration")
        exit 1
      end

  end

end

Rake::Task['bamboo'].invoke
