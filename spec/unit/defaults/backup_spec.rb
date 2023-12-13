require 'defaults/backup'

RSpec.describe Defaults::Backup do
  context 'backup_engine_topic_name' do
    it 'successfully return backup_engine_topic_name' do
      allow(Context).to receive_message_chain('environment.variable').with('backup_engine_topic_name', 'BackupEngineNotify').and_return('dummy-key')
      expect(Defaults.backup_engine_topic_name).to eq('dummy-key')
    end

    it 'successfully return default backup_engine_topic_name' do
      expect(Defaults.backup_engine_topic_name).to eq('BackupEngineNotify')
    end

    it 'fails to return backup_engine_topic_name' do
      allow(Context).to receive_message_chain('environment.variable').with('backup_engine_topic_name', 'BackupEngineNotify').and_return(nil)
      expect(Defaults.backup_engine_topic_name).to eq(nil)
    end
  end
end
