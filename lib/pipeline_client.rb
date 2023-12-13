require 'aws_helper_class'
require 'context_class'
require 'defaults'
require 'util/json_tools'
require 'types'
require 'service_now_api'
require 'log_class'
require 'util/splunk_client'

# Suppress outputs of FileUtils module
verbose(false)

# Simple method override to allow for empty or nil check
class Object
  def blank?; respond_to?(:empty?) ? empty? : !self; end
end

def trace_args(args)
  Log.debug 'Tracing arguments used:'

  args.each do |arg|
    Log.debug " - argument: #{arg}"
  end
end

def trace_runtime
  Log.debug 'Tracing environment used:'
  Log.debug "  Running under Ruby: #{RUBY_VERSION}"

  Log.debug 'Here are the environment used:'

  sys_calls = [
    'which ruby',
    'ruby --version',

    'which bundler',
    'bundler --version',

    'which gem',
    'gem --version',

    'gem list',
  ]

  sys_calls.each do |sys_call|
    begin
      Log.debug ("Calling: #{sys_call}")
      system(sys_call)
    rescue => e
      Log.debug "Failed sys call [#{sys_call}] with error: #{e}"
    end
  end
end

# A single point to initialize and interface with pipeline
# Currently, it exports the following variables to a global namespace due to backward compatibility
# - Log
# - AwsHelper
# - Context
# - ServiceNow
# This will be refactored in the upcoming PRs
class PipelineClient
  # Initializes pipeline environment, exports the following variables to a global namespace
  # - Log
  # - AwsHelper
  # - Context
  # - ServiceNow
  def initialize(disable_log_output = nil)
    # Create global Logger object
    Object.const_set(:Log, LogClass.new)

    # optionally, disable log trace locally for unit testing/QA
    if ENV['bamboo_disable_log_output'].nil? || (disable_log_output.nil? || !disable_log_output)
      trace_args(ARGV)
      trace_runtime
    end

    # update ARGV to make it globally available within the pipeline
    Defaults.set_argv(ARGV)

    # pipeline parses ARGV to understand on which CI/CD task we are
    # SSM params are fetched before any of rake tasks are initialized
    # therefore, we can only rely on incoming ARGV for early initialization
    Defaults.parse_argv

    Log.disable = ENV['bamboo_disable_log_output'].nil? != true

    # Create global AwsHelper object
    Object.const_set(:AwsHelper, AwsHelperClass.new(
                                   proxy: Defaults.proxy,
                                   region: Defaults.region,
                                   control_role: Defaults.control_role,
                                   provisioning_role: Defaults.provisioning_role
                                 ))

    # Create a global Context object
    Object.const_set(:Context, ContextClass.new(
                                 bucket: Defaults.pipeline_bucket_name,
                                 storage_type: Defaults.context_storage,
                                 plan_key: Defaults.plan_key,
                                 branch_name: Defaults.branch,
                                 build_number: Defaults.build,
                                 environment: Defaults.environment
                               ))

    # Create global ServiceNow object
    Object.const_set(:ServiceNow, ServiceNowApi.new(
                                    enabled: Defaults.snow_enabled,
                                    endpoint: Defaults.snow_endpoint,
                                    username: Defaults.snow_user,
                                    password: Defaults.snow_password,
                                    proxy: Defaults.proxy,
                                    build_user: Defaults.build_user
                                  ))
  end
end
