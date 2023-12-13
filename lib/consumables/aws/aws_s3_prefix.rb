require_relative '../../util/archive'
require_relative 'builders/wait_condition_builder'
require 'consumable'
require 'util/json_tools'
require 'services/pipeline_metadata_service'
require 'util/archive'

# Extends Consumable class, builds aws/s3-prefix pipeline component
class AwsS3prefix < Consumable
  include Util::Archive

  def initialize(component_name, definition)
    super(component_name, definition)

    @s3_public_prefix = {}
    @features = {}

    @download_artefact_bucket = Context.s3.artefact_bucket_name
    @aws_region = Defaults.region
    @cd_artefacts = {
      :ams => Defaults.sections[:ams],
      :qda => Defaults.sections[:qda],
      :as => Defaults.sections[:as],
      :ase => Defaults.sections[:ase],
      :branch => Defaults.sections[:branch],
      :build => Defaults.sections[:build],
      :component_name => component_name
    }

    @cd_artefact_path = Defaults.cd_artefact_path(component_name: @component_name)
    @upload_type = nil
    @artefact_path = nil

    # Load resources from the component definition
    (definition["Configuration"] || {}).each do |name, resource|
      raise "Invalid resource name #{name.inspect}" unless name =~ /^[a-zA-Z][a-zA-Z0-9]*$/

      type = resource["Type"]
      case type
      when "AWS::S3::Prefix"
        raise "Multiple #{type} resources found" unless @s3_public_prefix.empty?

        @s3_public_prefix[name] = resource
        @headers = JsonTools.get(resource, "Properties.Headers", {})
        @headers = @headers.inject({}) { |memo, (k, v)| memo[k.to_sym] = v; memo }
      when "Pipeline::Features"
        @features[name] = resource
      when nil
        raise "Must specify a type for resource #{name.inspect}"
      else
        raise "Resource type #{type.inspect} is not supported by this component"
      end

      bucket_type = resource["Properties"]["BucketType"]
      case bucket_type
      when "public".downcase
        @upload_artefact_bucket = Defaults.public_s3_content_bucket
        @upload_type = bucket_type.downcase
        @artefact_path = [
          @cd_artefacts[:ams],
          @cd_artefacts[:qda],
          @cd_artefacts[:as],
          @cd_artefacts[:ase],
          @cd_artefacts[:branch],
          @cd_artefacts[:build],
          @cd_artefacts[:component_name]
        ].join('/')
      when "private".downcase
        @upload_artefact_bucket = Context.s3.as_bucket_name
        @upload_type = bucket_type.downcase
        @artefact_path = [
          @cd_artefacts[:branch],
          @cd_artefacts[:build],
          @cd_artefacts[:component_name]
        ].join('/')
      when nil
        raise "Must specify a property BucketType for resource #{name.inspect}"
      else
        raise "Invalid value provided for the BucketType for resource #{name.inspect}"
      end
    end

    @s3_prefix_name = @s3_public_prefix.keys.first
    Log.info "S3 Prefix Name => #{@s3_prefix_name}"
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
    if @upload_type.eql? "public"
      _check_approved_apps
    end
    _upload_public_s3_artefact

    # Create the stack
    stack_name = Defaults.component_stack_name(@component_name)
    tags = Defaults.get_tags(@component_name)
    @pipeline_features.map { |f| tags += f.feature_tags }
    template = _full_template

    begin
      stack_outputs = {}
      stack_outputs = AwsHelper.cfn_create_stack(
        stack_name: stack_name,
        template: template,
        tags: tags
      )
    rescue => e
      stack_outputs = e.is_a?(ActionError) ? e.partial_outputs : {}
      raise "Failed to create stack - #{e}"
    ensure
      Context.component.set_variables(@component_name, stack_outputs)
    end

    Log.output "The deployment endpoint is:  https://s3-#{@aws_region}.amazonaws.com/#{@upload_artefact_bucket}/#{@artefact_path}"
  end

  def release
    super
    _release_public_s3_artefact
    Log.output "The release endpoint is: https://s3-#{@aws_region}.amazonaws.com/#{@upload_artefact_bucket}/#{_get_release_path(@artefact_path)}"
  end

  def teardown
    _delete_public_s3_artefact

    exception = nil

    # Delete stack
    begin
      stack_id = Context.component.stack_id(@component_name)
      AwsHelper.cfn_delete_stack(stack_id) unless stack_id.nil?
    rescue => e
      exception ||= e
      Log.warn "Failed to delete stack #{stack_id.inspect} during teardown - #{e}"
    end
  end

  def _check_approved_apps
    # Check Context.sections[:qda]
    approved_apps = Defaults.public_s3_content_approved_apps
    approved_apps = approved_apps.split(',')
    app = Defaults.sections[:qda]

    if approved_apps.include? app.upcase
      Log.info "The application #{app} is approved for public s3 access"
    else
      Log.error "The application is not approved for the public s3 access. Please contect CSI Team for the access."
      raise "Application not in approved list"
    end
  end

  # Retruns the release path for public S3
  def _get_release_path(artf_path)
    if !artf_path.nil?
      artf_path = artf_path.split("/")
      artf_path.delete_at(-2)
      artf_path.push("current")
      copy_path = artf_path.join("/")
      return copy_path
    else
      raise "Null value for Artefact Path"
    end
  end

  # Create an AwsHelper with custom s3 upload role
  # Note: Ensures upload takes in the account / role where shared public s3 bucket lives
  # @return [Object] AwsHelper object used as a wrapper for AWS APIs

  def _upload_s3_role
    params = {
      proxy: Defaults.proxy,
      region: Defaults.region,
      control_role: Defaults.control_role
    }

    # if a custom invocation role is specified, use it as a provisioning role
    if @upload_type.eql? "public"
      upload_client = nil
      params[:s3_role] = Defaults.public_s3_content_upload_role
      Log.info "Using provisioning role - #{params[:s3_role]}"
      upload_client =  AwsHelperClass.new(**params)
    elsif @upload_type.eql? "private"
      params[:proxy] = Context.environment.variable("aws_proxy", "")
      params[:s3_role] = Defaults.provisioning_role
      Log.info "Using provisioning role - #{params[:s3_role]}"
      upload_client = AwsHelperClass.new(**params)
    else
      Log.info "Using control role"
    end

    return upload_client
  end

  def _full_template
    template = { "Resources" => {}, "Outputs" => {} }

    template["Resources"][@s3_prefix_name] = {
      "Type" => "AWS::CloudFormation::WaitConditionHandle",
      "Properties" => {},
    }

    template["Outputs"]["DeployPrefixPath"] = {
      "Description" => "Deploy S3 Prefix Path",
      "Value" => @artefact_path,
    }

    template["Outputs"]["ReleasePrefixPath"] = {
      "Description" => "Release S3 Prefix Path",
      "Value" => _get_release_path(@artefact_path),
    }

    return template
  end

  # Downloads unpacks and uploads public content into public s3 bucket
  # @param artefact_name [String] Artefact file name specified for the public content
  def _upload_public_s3_artefact
    tmpdir = Dir.mktmpdir
    local_file_name = "#{tmpdir}/app.tar.gz"

    begin
      AwsHelper.s3_download_object(
        bucket: @download_artefact_bucket,
        key: "#{@cd_artefact_path}/app.tar.gz",
        local_filename: local_file_name
      )
      untgz!(local_file_name)
    rescue => e
      raise "Unable to download and unpack package " \
        "from #{@download_artefact_bucket}/#{@cd_artefact_path} - #{e}"
    end

    unless File.exist?(tmpdir)
      raise "Unable to locate #{tmpdir}. " \
        "Ensure public content is packaged as a single tar.gz file" \
        " into $PAYLOAD_DIR during the upload stage"
    end

    begin
      files = Dir.glob(File.join(tmpdir, '/', '**/*'), File::FNM_DOTMATCH)
      s3_client = _upload_s3_role
      Log.info "#{s3_client}"
      files.each do |file_name|
        if File.file?(file_name)
          relative_file = file_name.sub((tmpdir + File::Separator).to_s, '')
          Log.info "Uploading file to #{@upload_artefact_bucket}/#{@artefact_path}/#{relative_file}"
          s3_client.s3_upload_file(@upload_artefact_bucket, "#{@artefact_path}/#{relative_file}", file_name, headers: @headers)
          Log.info "Uploaded file to #{@upload_artefact_bucket}/#{@artefact_path}/#{relative_file}"
        else
          Log.info "Skipping #{file_name}"
        end
      end
      Log.output "S3 Content Uploaded to #{@upload_artefact_bucket} bucket #{@artefact_path} prefix"
    rescue => e
      Log.error "Unable to upload: #{e}"
    end
  rescue => e
    raise "Unable to upload: #{e}"
  ensure
    FileUtils.rm_rf tmpdir
  end

  def _delete_public_s3_artefact
    begin
      if Context.persist.released_build_number == Defaults.sections[:build]
        override_variable = 'force_teardown_of_released_build'
        if Context.environment.variable(override_variable, nil) == 'true'
          Log.info "Removing public content from latest releases build"
          _upload_s3_role.s3_delete_objects(@upload_artefact_bucket, @artefact_path)
          _upload_s3_role.s3_delete_objects(@upload_artefact_bucket, _get_release_path(@artefact_path))
        else
          raise "ERROR: Teardown of the released build is rejected by pipeline" \
          " - variable #{override_variable.inspect} is set to \"false\""
        end
      else
        Log.info "Removing public s3 artefacts from #{@upload_artefact_bucket}/#{@artefact_path}"
        _upload_s3_role.s3_delete_objects(@upload_artefact_bucket, @artefact_path)
        Log.output "S3 Content Deleted from #{@upload_artefact_bucket} bucket #{@artefact_path} prefix"
      end
    rescue => e
      raise "Failed to delete artefacts: #{e}"
    end
  end

  def _get_rlease_copy_path(path)
    if !path.nil?
      path = path.split(@component_name)[1]
    else
      raise "Null value for the path"
    end
    return path
  end

  def _release_public_s3_artefact
    # List objects from build specific public app bucket folder
    s3_client = _upload_s3_role
    Log.debug "Creating #{s3_client} client"
    release_number = Context.persist.released_build_number
    if (!release_number.nil? && release_number != Defaults.sections[:build])
      Log.info "Clearing artefacts from previous release build: #{release_number}"
      s3_client.s3_delete_objects(@upload_artefact_bucket, _get_release_path(@artefact_path))
      Log.info "The artefact from previous release have been deleted"
    else
      Log.info "This is the first released build"
    end

    begin
      objects = s3_client.s3_list_objects(bucket: @upload_artefact_bucket, prefix: @artefact_path).map { |k| { key: k } }
      objects.each do |object|
        release_path = "#{_get_release_path(@artefact_path)}#{_get_rlease_copy_path(object[:key])}"
        Log.info "Copying artefacts from deployment path #{object[:key]} to release path #{release_path}"
        s3_client.s3_copy_object(@upload_artefact_bucket, object[:key], @upload_artefact_bucket, release_path)
      end
    rescue => e
      raise "Unable to copy the artefacts to release path #{e}"
    end
  end
end
