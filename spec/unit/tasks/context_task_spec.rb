$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'tasks/context_task.rb'

RSpec.describe Action do
  def _get_task
    ContextTask.new
  end

  def _get_sections
    {

    }
  end

  context '.instantiate' do
    it 'can create an instance' do
      task = _get_task

      expect(task).not_to eq(nil)
    end
  end

  context '.name' do
    it 'returns value' do
      task = _get_task

      expect(task.name).to eq("context")
    end
  end

  context '.read' do
    it 'sets context values' do
      task = _get_task

      allow(Context).to receive_message_chain('s3.set_pipeline_bucket_details')
      allow(Context).to receive_message_chain('s3.set_legacy_bucket_details')
      allow(Context).to receive_message_chain('s3.set_artefact_bucket_details')
      allow(Context).to receive_message_chain('s3.set_lambda_artefact_bucket_details')
      allow(Context).to receive_message_chain('s3.set_ams_bucket_details')
      allow(Context).to receive_message_chain('s3.set_qda_bucket_details')
      allow(Context).to receive_message_chain('s3.set_as_bucket_details')
      allow(Context).to receive_message_chain('s3.set_pipeline_bucket_details')
      allow(Context).to receive_message_chain('s3.set_secret_bucket_details')
      allow(Context).to receive_message_chain('asir.set_dynamo_table_details')
      allow(Context).to receive_message_chain('pipeline.set_trend_dsm_url_details')
      allow(Context).to receive_message_chain('pipeline.set_trend_dsm_tenant_id_details')
      allow(Context).to receive_message_chain('pipeline.set_trend_dsm_token_details')
      allow(Context).to receive_message_chain('pipeline.set_trend_dsm_saas_proxy_details')
      allow(Context).to receive_message_chain('pipeline.set_trend_agent_activation_url_details')

      allow(Context).to receive_message_chain('environment.set_variables')

      allow(Defaults).to receive(:pipeline_bucket_name)
      allow(Defaults).to receive(:legacy_bucket_name)
      allow(Defaults).to receive(:artefact_bucket_name)
      allow(Defaults).to receive(:lambda_artefact_bucket_name)
      allow(Defaults).to receive(:ams_bucket_name)
      allow(Defaults).to receive(:qda_bucket_name)
      allow(Defaults).to receive(:as_bucket_name)
      allow(Defaults).to receive(:asir_dynamodb_table_name)
      allow(Defaults).to receive(:trend_dsm_url)
      allow(Defaults).to receive(:trend_dsm_tenant_id)
      allow(Defaults).to receive(:trend_dsm_token)
      allow(Defaults).to receive(:trend_dsm_saas_proxy)
      allow(Defaults).to receive(:trend_agent_activation_url)

      allow(Defaults).to receive(:secrets_bucket_name)

      expect { task.read }.not_to raise_error
    end
  end

  context '.flush' do
    it 'flushes context' do
      task = _get_task

      allow(Context).to receive(:flush)
      expect { task.write }.not_to raise_error
    end
  end

  context '.last_build' do
    it 'get no build number' do
      task = _get_task
      allow(AwsHelper).to receive(:s3_list_objects).and_return([])
      expect(task.last_build).to eq(0)
    end

    it 'get the last number build number' do
      task = _get_task
      allow(Defaults).to receive(:sections).and_return(
        ams: 'ams99',
        qda: 'C088',
        as: '077',
        ase: 'dev',
        branch: 'master',
        env: 'NONP',
      )
      allow(AwsHelper).to receive(:s3_list_objects).and_return([
                                                                 'ams99/C088/077/dev/master/3',
                                                                 'ams99/C088/077/dev/master/1'
                                                               ])
      expect(task.last_build).to eq(3)
    end
  end
end
