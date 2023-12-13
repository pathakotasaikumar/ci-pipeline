$LOAD_PATH.unshift("#{BASE_DIR}/lib")
require 'rake'

shared_context 'rake' do
  let(:invoke_task) { Rake.application[task_name] }
  subject { Rake::Task[task_name] }

  def _loaded_task_files task_path, tasks_folder_path
    Dir[tasks_folder_path + '/*.rake'].reject { |file| file.end_with? task_path }
  end

  before do
    tasks_folder_path = "#{BASE_DIR}/tasks"
    task_paths.each do |task_path|
      Rake.application.rake_require(
        task_path,
        [tasks_folder_path],
        _loaded_task_files(task_path, tasks_folder_path)
      )
    end
    Rake::Task.define_task(:environment)
  end
end
