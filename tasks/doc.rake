require 'util/os'

include Util::OS

task :doc do
  require 'yard'
  YARD::Rake::YardocTask.new(:doc) do |t|
    t.files = ["lib/**/*.rb"]
    t.options = ["--output-dir", "doc", "-", "--title", "QCP Pipeline"]
    t.after = proc{ puts "Full documentation is now generated - open doc/html.index"}
  end
end

# Run YARD docserver
task :docserver do
  Log.info "Starting YARD documentation server"
  windows? ? system("yard server") : system("yard server -d")
end
