# Module responsible for generating AWS::Lambda::LayerVersion template
module LambdaLayerBuilder

    # @param template [Hash] template carried into the layer
    # @param layer_definition [Hash] Definition for lambda layer
    # @param resource_name [String] Logical name for Lambda Layer resource
    # @param security_group_ids [Array] List of security groups ids for vpc configuration
    # See CloudFormation AWS::Lambda::LayerVersion documentation for valid property values
    # https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-lambda-layerversion.html
    def _process_lambda_layer(
      template: nil,
      layer_definition: nil,
      resource_name: nil
    )
  
      name, definition = layer_definition.first
      name = resource_name unless resource_name.nil?
  
      # Replace any context variables
      Context.component.replace_variables(definition)
  
      template["Resources"][name] = {
        "Type" => "AWS::Lambda::LayerVersion",
        "Properties" => {
          "CompatibleRuntimes" => JsonTools.get(definition, "Properties.CompatibleRuntimes"),
          "LayerName" => name,
          "Description" => JsonTools.get(definition, "Properties.Description","Properties.LayerName"),
          "LicenseInfo" => "QCP"
        }
      }
  
      resource = template["Resources"][name]
  
      content = JsonTools.get(definition, "Properties.Content")
      raise "Unknown value for content, specify valid package filename" unless content.is_a?(String)
  
      # For local file use ZipFile CF property for layer as construct inline
      # Required for pipeline managed Lambda resources
      cd_artefact_path = Defaults.cd_artefact_path(component_name: @component_name)

      resource["Properties"]["Content"] = {
        "S3Bucket" => Context.s3.lambda_artefact_bucket_name,
        "S3Key" => "#{cd_artefact_path}/#{content}"
      }

    template["Outputs"]["#{name}Arn"] = {
      "Description" => "Arn of the Layer",
      "Value" =>  { "Ref" => name }
    }
  end

  # Return CloudFormation representation of a local layer source file
  # @param filename [String] Location of a local source file
  # @return [Hash] CloudFormation representation of a source file
  def _process_local_file(filename)
    join_array = []
    File.readlines(filename).each { |line| join_array.push(line) }
    { 'Fn::Join' => ['', join_array] }
  end

  # Downloads unpacks and uploads lambda layer artefact to a staging area for deployment
  # @param component_name [String] Artefact file name specified for the lambda layer
  # @param artefacts [List] List of artefacts to be uploaded
  def _upload_package_artefacts(component_name:, artefacts:)
    require 'util/archive'

    download_artefact_bucket = Context.s3.artefact_bucket_name
    upload_artefact_bucket = Context.s3.lambda_artefact_bucket_name

    cd_artefact_path = Defaults.cd_artefact_path(component_name: component_name)
    tmpdir = Dir.mktmpdir
    local_file_name = "#{tmpdir}/app.tar.gz"

    begin
      AwsHelper.s3_download_object(
        bucket: download_artefact_bucket,
        key: "#{cd_artefact_path}/app.tar.gz",
        local_filename: local_file_name
      )
      Util::Archive.untgz!(local_file_name)
    rescue => e
      raise "Unable to download and unpack package " \
        "from #{download_artefact_bucket}/#{cd_artefact_path} - #{e}"
    end

    artefacts.each do |artefact_name|
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
          upload_artefact_bucket,
          "#{cd_artefact_path}/#{file_name}",
          local_artefact_file_name
        )
      rescue => e
        raise "Unable to upload file to #{upload_artefact_bucket}/#{cd_artefact_path}/#{file_name} - #{e}"
      end
    end
  rescue => e
    raise "Unable to unpack and upload lambda artefact - #{e}"
  ensure
    FileUtils.rm_rf tmpdir
  end
end