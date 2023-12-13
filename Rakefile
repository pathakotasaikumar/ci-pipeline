# Create a global constant pointing to the base of the repository
BASE_DIR = __dir__
LOGGING_SERVICES_DIR = "#{BASE_DIR}/lib/util/logging"

# Add lib to the load path
$LOAD_PATH.unshift("#{BASE_DIR}/lib")
require 'pipeline_client'

# set default pipeline task to 'unit-tests' for unit tests run
# it will later be overwritten from ARGV input
Defaults.set_pipeline_task('unit-tests')

# initialize a new pipeline client
client = PipelineClient.new

# Load Rake namespaces
Dir["#{BASE_DIR}/tasks/*.rake"].each do |file|
  Log.debug "Loading Rake task #{File.basename(file)}"
  import file
end

# Load Rake qa namespaces
pipeline_qa = ENV['bamboo_pipeline_qa']

unless pipeline_qa.nil?
  # Load QA Rake namespaces
  Dir["#{BASE_DIR}/tasks_qa/*.rake"].each do |file|
    Log.debug "Loading QA Rake file #{File.basename(file)}"
    import file
  end
end

task :default => [:test]