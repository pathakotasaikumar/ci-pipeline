#
# BART/Backup parameters
#

module Defaults
  module Backup
    # Returns Qantas Backup engine topic name
    # @return [String] Backup engine topic name (local to account)
    def backup_engine_topic_name
      Context.environment.variable('backup_engine_topic_name', 'BackupEngineNotify')
    end
  end
end
