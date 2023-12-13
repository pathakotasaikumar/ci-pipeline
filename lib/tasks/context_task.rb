require 'component'
require 'runner'

class ContextTask
  def name
    "context"
  end

  def read
    Context.s3.set_pipeline_bucket_details(Defaults.pipeline_bucket_name)
    Context.s3.set_legacy_bucket_details(Defaults.legacy_bucket_name)
    Context.s3.set_secret_bucket_details(Defaults.secrets_bucket_name)
    Context.s3.set_artefact_bucket_details(Defaults.artefact_bucket_name)
    Context.s3.set_lambda_artefact_bucket_details(Defaults.lambda_artefact_bucket_name)
    Context.s3.set_ams_bucket_details(Defaults.ams_bucket_name)
    Context.s3.set_qda_bucket_details(Defaults.qda_bucket_name)
    Context.s3.set_as_bucket_details(Defaults.as_bucket_name)
    Context.asir.set_dynamo_table_details(Defaults.asir_dynamodb_table_name)
    Context.pipeline.set_trend_dsm_url_details(Defaults.trend_dsm_url)
    Context.pipeline.set_trend_dsm_tenant_id_details(Defaults.trend_dsm_tenant_id)
    Context.pipeline.set_trend_dsm_token_details(Defaults.trend_dsm_token)
    Context.pipeline.set_trend_dsm_saas_proxy_details(Defaults.trend_dsm_saas_proxy)
    Context.pipeline.set_trend_agent_activation_url_details(Defaults.trend_agent_activation_url)

    Context.environment.set_variables(
      "deployment_env" => (Defaults.sections[:env] == "prod") ? "Production" : "NonProduction",
      "ad_access_filter" => "QDA-" + "#{Defaults.sections[:qda].upcase}-" + (Defaults.sections[:env] == "prod" ? "PR-ACCESS" : "NP-ACCESS"),
      "root_sudo_group" => "QDA-" + "#{Defaults.sections[:qda].upcase}-" + (Defaults.sections[:env] == "prod" ? "BG-ACCESS" : "DEVELOPER"),
      "ad_security_group_admin" => "QDA-" + "#{Defaults.sections[:qda].upcase}-" + (Defaults.sections[:env] == "prod" ? "BG-ACCESS" : "DEVELOPER"),
      "ad_security_group_user" => "QDA-" + "#{Defaults.sections[:qda].upcase}-" + (Defaults.sections[:env] == "prod" ? "PR-ACCESS" : "NP-ACCESS"),
    )
  end

  def write
    Context.flush
  end

  def last_build
    read
    prefix = [Defaults.sections[:ams], Defaults.sections[:qda], Defaults.sections[:as], Defaults.sections[:ase], Defaults.sections[:branch]].join('/')
    response = AwsHelper.s3_list_objects(
      bucket: Context.s3.pipeline_bucket_name,
      prefix: prefix
    )

    builds = response.map { |e| e =~ /#{prefix}\/(\d+)/ ? $1.to_i : 0 }

    return builds.max ? builds.max : 0
  end
end
