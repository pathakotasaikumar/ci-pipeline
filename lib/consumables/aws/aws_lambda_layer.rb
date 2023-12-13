require_relative '../../consumable'
require_relative '../../util/archive'
require_relative 'builders/lambda_layer_builder'

# Extends Consumable class, builds aws/lambda pipeline component
class AwsLambdaLayer < Consumable
  include Util::Archive
  include LambdaLayerBuilder

  # @param (see Consumable#initialize)
  def initialize(component_name, definition)
    super(component_name, definition)

    @lambda_layer = {}
    @lambda_layer_name = ''
    @lambda_layer_artefact = nil
    # Load resources from the component definition
    (definition['Configuration'] || {}).each do |name, resource|
      type = resource['Type']

      case type
      when 'AWS::Lambda::LayerVersion'
        raise "This component does not support multiple #{type} resources" unless @lambda_layer.empty?
        
        @lambda_layer[name] = resource
        @lambda_layer_name = name
      when 'Pipeline::Features'
        @features[name] = resource
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end
    end

    @lambda_layer_artefact = JsonTools.get(
        @lambda_layer.values.first, 'Properties.Content', nil
      )
  
      # Test if the 'Content' property looks like a zip file
      unless %w(.zip).include?(File.extname(@lambda_layer_artefact.to_s))
        raise "Lambda Layer 'Content' property must be specified as a zip file"
      end
  end

    # @return (see Consumable#security_items)
    def security_items
      []
    end
  
    # @return (see Consumable#security_rules)
    def security_rules
      []
    end

    
  def deploy
    # Unpack and upload specified lambda layer artefact package
    _upload_package_artefact(@lambda_layer_artefact)


    layer_stack_name = Defaults.component_stack_name(@component_name)

    template = _layer_template
    params = {
      stack_name: layer_stack_name,
      template: template,
      wait_delay: 10
    }

    stack_outputs = {}
    begin
      Log.info "Creating Lambda Layer stack - #{layer_stack_name}"
      if AwsHelper.cfn_stack_exists(layer_stack_name).nil?
        tags = Defaults.get_tags(@component_name)
        @pipeline_features.map { |f| tags += f.feature_tags }
        params[:tags] = tags
        stack_outputs = AwsHelper.cfn_create_stack(**params)
      end
      Log.info stack_outputs
    rescue ActionError => e
      stack_outputs = e.partial_outputs
      raise "Failed to create Lambda Layer stack - #{stack_outputs.inspect}- #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)
    end
  end

  def release
    super
  end

  def teardown
    exception = nil

    if Context.persist.released_build_number == Defaults.sections[:build] ||
       Context.persist.released_build_number.nil?
      # Delete release alias stack
      begin
        stack_id = Context.component.stack_id(@component_name)
        AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
      rescue => e
        exception ||= e
        Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
      end
    end
  end


  private

  # Builds out AWS::Lambda::LayerVersion and other required resources
  # @return [Hash] CloudFormation template representation
  def _layer_template
    template = { 'Resources' => {}, 'Outputs' => {} }

    _process_lambda_layer(
    template: template,
    resource_name: @lambda_layer_name,
    layer_definition: @lambda_layer
    )

    template
  end

  # Downloads unpacks and uploads lambda artefact to a staging area for deployment
  # @param artefact_name [String] Artefact file name specified for the lambda function
  def _upload_package_artefact(artefact_name)
    download_artefact_bucket = Context.s3.artefact_bucket_name
    upload_artefact_bucket = Context.s3.lambda_artefact_bucket_name

    cd_artefact_path = Defaults.cd_artefact_path(component_name: @component_name)
    tmpdir = Dir.mktmpdir
    local_file_name = "#{tmpdir}/app.tar.gz"

    begin
      AwsHelper.s3_download_object(
        bucket: download_artefact_bucket,
        key: "#{cd_artefact_path}/app.tar.gz",
        local_filename: local_file_name
      )
      untgz!(local_file_name)
    rescue => e
      raise "Unable to download and unpack #{artefact_name} package " \
        "from #{download_artefact_bucket}/#{cd_artefact_path} - #{e}"
    end

    local_artefact_file_name = File.join tmpdir, artefact_name

    unless File.exist?(local_artefact_file_name)
      raise "Unable to locate #{artefact_name}. " \
        "Ensure lambda code is packaged as a single zip or jar artefact" \
        " into $PAYLOAD_DIR during the upload stage"
    end

    begin

      file_name = File.basename(local_artefact_file_name)

      Log.debug "Uploading file to #{upload_artefact_bucket}/#{cd_artefact_path}/#{file_name}"
      AwsHelper.s3_upload_file(
        upload_artefact_bucket, "#{cd_artefact_path}/#{file_name}", local_artefact_file_name
      )
    rescue => e
      raise "Unable to upload file to #{upload_artefact_bucket}/#{cd_artefact_path}/#{file_name} - #{e}"
    end
  rescue => e
    raise "Unable to unpack and upload layer artefact #{artefact_name} - #{e}"
  ensure
    FileUtils.rm_rf tmpdir
  end
end
