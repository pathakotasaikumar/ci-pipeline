require 'aws-sdk'
require 'util/string_utils'
module Ec2Helper
  def _ec2_helper_init
    @ec2_client = nil
  end

  # Creates a volume snapshot
  # @param image_id [String] AMI ID to add permissions to
  # @param accounts [List] List of accounts to be added to the AMI launch permissions
  def ec2_add_launch_permission(image_id:, accounts:)
    # convert array of accounts to a parameter hash required for ec2client
    permissions = accounts.map { |account| { user_id: account.to_s } }

    begin
      Log.debug "Running _ec2_client.modify_image_attribute(image_id: #{image_id} - {add:#{accounts}})"
      _ec2_client.modify_image_attribute(
        image_id: image_id,
        launch_permission: {
          add: permissions
        }
      )
    rescue => e
      Log.snow "ERROR: Failed to add launch permission to AMI (ImageId = #{image_id.inspect} - #{e}"
      raise "ERROR: Failed to add launch permission to AMI (ImageId = #{image_id.inspect} - #{e}"
    end
  end

  # Creates a volume snapshot
  # @param [String] volume_id
  # @param [String] description
  # @param [Object] tags
  # @param [Boolean] check_volume_status
  # @return [String] Snapshot ID
  def ec2_create_volume_snapshot(volume_id:, description: nil, tags: nil, check_volume_status: true)
    if check_volume_status
      Log.debug "Waiting for volume #{volume_id} to become available"
      begin
        _ec2_client.wait_until(:volume_available, { volume_ids: [volume_id] }) do |waiter|
          waiter.max_attempts = 5
          waiter.delay = 30
        end
      rescue Aws::Waiters::Errors::TooManyAttemptsError => e
        raise ActionError.new, "Unable to snapshot volume cleanly #{volume_id} - #{e}"
      rescue Aws::Waiters::Errors::WaiterFailed => e
        raise ActionError.new, "Unable to snapshot volume cleanly #{volume_id}) - #{e}"
      end
    end

    begin
      params = {
        volume_id: volume_id,
        description: description
      }

      Log.debug "Creating a new snapshot for volume #{volume_id}"
      response = _ec2_client.create_snapshot(params)

      unless tags.nil? || tags.empty?
        _ec2_client.create_tags(
          resources: [response.snapshot_id],
          tags: tags
        )
      end
    rescue => e
      Log.snow "ERROR: Failed to create volume snapshot (VolumeId = #{volume_id})"
      raise "Failed to create volume snapshot #{volume_id} - #{e}"
    end

    return response.snapshot_id
  end

  # Creates a copy of an EC2 image
  # @param source_image_id [String] Source Image ID
  # @param name [String] Name for target image
  # @param source_region [String] Region for source image
  # @param tags [Tags] Tags to be assigned to the result image
  def ec2_copy_image(
    source_image_id:,
    name:,
    source_region: nil,
    tags: nil,
    encrypted: false,
    kms_key_id: nil
  )

    begin
      outputs = {}
      params = {
        source_image_id: source_image_id,
        source_region: (source_region || @region),
        name: name,
        encrypted: encrypted
      }

      # Only set KMS key in hash if one has been provided
      params[:kms_key_id] = kms_key_id unless kms_key_id.nil?

      Log.debug "Creating a copy of EC2 AMI #{source_image_id.inspect}"
      response = _ec2_client.copy_image(params)

      outputs = {
        "ImageName" => name,
        "ImageId" => response.image_id,
      }
    rescue => e
      Log.snow "ERROR: Failed to copy AMI #{source_image_id.inspect}"
      raise "Failed to copy AMI #{source_image_id.inspect} - #{e}"
    end

    # Wait for image creation to complete/fail/timeout
    Log.debug "Waiting for AMI image #{response.image_id} to become available"
    begin
      _ec2_client.wait_until(:image_available, { image_ids: [response.image_id] }) do |waiter|
        waiter.max_attempts = 150
        waiter.delay = 10
      end
    rescue Aws::Waiters::Errors::TooManyAttemptsError => e
      Log.snow "ERROR: EC2 AMI creation timed out (ImageId = #{response.image_id.inspect})"
      raise ActionError.new(outputs), "EC2 AMI creation timed out (ImageId = #{response.image_id.inspect}) - #{e}"
    rescue Aws::Waiters::Errors::WaiterFailed => e
      Log.snow "ERROR: EC2 AMI creation failed (ImageId = #{response.image_id.inspect})"
      raise ActionError.new(outputs), "EC2 AMI creation failed (ImageId = #{response.image_id.inspect}) - #{e}"
    end

    # Tag all image snapshots
    unless tags.empty?
      resource_ids = [response.image_id]
      begin
        resource_ids += ec2_get_snapshot_ids_of_image(response.image_id)
        _ec2_client.create_tags(resources: resource_ids, tags: tags)
      rescue => e
        Log.snow "ERROR: Failed to tag AMI and snapshots (Resources = #{resource_ids.inspect})"
        raise "Failed to tag AMI and snapshots (Resources = #{resource_ids.inspect}) - #{e}"
      end
    end

    # Retrieve and save the image's outputs
    Log.snow "Created AMI (ImageId = #{response.image_id.inspect}, ImageName = #{name.inspect})"
    Log.info "Created AMI (ImageId = #{response.image_id.inspect}, ImageName = #{name.inspect})"

    return outputs
  end

  # Creates EC2 image (AMI)
  # @param name [String] Target image name
  # @param instance_id [String] Originating instance id
  # @param tags [Array] List of tags to be assigned to the instance
  def ec2_create_image(name, instance_id, tags = [])
    raise ArgumentError, "Parameter 'name' is mandatory" if name.nil? or name.empty?
    raise ArgumentError, "Parameter 'instance_id' is mandatory" if instance_id.nil? or instance_id.empty?

    outputs = {}

    begin
      params = {
        instance_id: instance_id,
        name: name
      }

      Log.debug "Creating a new EC2 AMI of the instance with id #{instance_id.inspect} with name #{name.inspect}"
      response = _ec2_client.create_image(params)

      outputs = {
        "ImageName" => name,
        "ImageId" => response.image_id,
      }
    rescue => e
      Log.snow "ERROR: Failed to create AMI (InstanceId = #{instance_id.inspect}; ImageName = #{name.inspect})"
      raise "Failed to create AMI (InstanceId = #{instance_id.inspect}; ImageName = #{name.inspect}) - #{e}"
    end

    # Wait for image creation to complete/fail/timeout
    Log.debug "Waiting for AMI image #{response.image_id} to become available"
    begin
      _ec2_client.wait_until(:image_available, { image_ids: [response.image_id] }) do |waiter|
        waiter.max_attempts = 240
        waiter.delay = 30
      end
    rescue Aws::Waiters::Errors::TooManyAttemptsError => e
      Log.snow "ERROR: EC2 AMI creation timed out (ImageId = #{response.image_id.inspect})"
      raise ActionError.new(outputs), "EC2 AMI creation timed out (ImageId = #{response.image_id.inspect}) - #{e}"
    rescue Aws::Waiters::Errors::WaiterFailed => e
      Log.snow "ERROR: EC2 AMI creation failed (ImageId = #{response.image_id.inspect})"
      raise ActionError.new(outputs), "EC2 AMI creation failed (ImageId = #{response.image_id.inspect}) - #{e}"
    end

    # Tag all image snapshots
    unless tags.empty?
      resource_ids = [response.image_id]
      begin
        resource_ids += ec2_get_snapshot_ids_of_image(response.image_id)
        _ec2_client.create_tags(resources: resource_ids, tags: tags)
      rescue => e
        Log.snow "ERROR: Failed to tag AMI and snapshots (Resources = #{resource_ids.inspect})"
        raise "Failed to tag AMI and snapshots (Resources = #{resource_ids.inspect}) - #{e}"
      end
    end

    # Retrieve and save the image's outputs
    Log.snow "Created AMI (ImageId = #{response.image_id.inspect}, ImageName = #{name.inspect})"
    Log.info "Created AMI (ImageId = #{response.image_id.inspect}, ImageName = #{name.inspect})"

    return outputs
  end

  # Deletes existing EC2 image
  # @param [String] Image id to be deleted
  def ec2_delete_image(image_id)
    raise ArgumentError, "Parameter 'image_id' is mandatory" if image_id.nil? or image_id.empty?

    Log.debug "Deleting image with ImageId=#{image_id.inspect} and associated snapshots"

    # snapshots need to be deleted after the AMI has been deregistered, but can only be deleted after
    # the AMI has been deleted
    snapshot_ids = ec2_get_snapshot_ids_of_image(image_id)

    ec2_deregister_image(image_id)

    ec2_delete_snapshots(snapshot_ids)

    Log.debug "Image with ImageId=#{image_id.inspect} deleted"
  end

  # Takes a prefix for an image name, with optional list of owner-ids (accounts)
  # Returns image name name with an incremented version number
  # @param prefix [String] Prefix for a result an image name
  # @param owners [Array] List of accounts ids to filter the image list with
  # @return [String] Composite name consisting of the supplied prefix and latest available version id
  def ec2_versioned_image_name(prefix:, owners: [])
    params = {}
    params[:owners] = owners unless owners.nil? or owners.empty?
    response = _ec2_client.describe_images(owners: owners)

    image_versions = response.images.map do |image|
      split = image.name.match "^#{prefix}.(?<version>[0-9]+)$"
      next split[:version].to_i unless split.nil?

      next
    end

    latest_version = image_versions.compact.uniq.sort.last || 0
    Log.debug "No previous version found for #{prefix}" if latest_version.zero?

    "#{prefix}.#{latest_version + 1}"
  rescue => e
    raise "Unable to determine a version for the image prefix '#{prefix}' - #{e}"
  end

  # Query image (AMI) details
  # @param image_id [String] Target image id
  # @return [Hash] Key/Values pairs for image attributes:
  #   name, id, description, state, platform
  def ec2_get_image_details(image_id)
    params = if image_id.start_with? 'ami-'
               # Lookup image by id
               { image_ids: [image_id] }
             else
               # Lookup image by name
               { filters: [{ name: 'Name', values: [image_id], }] }
             end

    begin
      response = _ec2_client.describe_images(params)
      raise "No images returned from search (image_id = #{image_id.inspect})" if response.nil? or response.images.empty?
    rescue => e
      raise "Unable to find image (image_id = #{image_id.inspect}) - #{e}"
    end

    if response.images.length > 1
      Log.warn "Image search returned #{response.images.length} images for #{image_id.inspect} - using the latest result"
      image_details = (response.images.sort_by { |image| image.creation_date })[0]
    else
      image_details = response.images[0]
    end

    # Work out the image OS based on its name
    platform = ec2_platform_from_image(image_details.name.downcase, image_details.platform)

    {
      name: image_details.name,
      id: image_details.image_id,
      tags: image_details.tags,
      description: image_details.description,
      state: image_details.state,
      platform: platform
    }
  end

  # Obtain platform (OS) from the image (AMI)
  # @param image_name [String] Name if the image to query
  # @return [Symbol] platform type as a Symbol (:rhel, :centos, :amazon_linux, :windows, :linux :unknown)
  def ec2_platform_from_image(image_name, platform)
    case image_name
    when /qf-aws-rhel|red hat|rhel/
      :rhel
    when /qf-aws-centos|cent os|centos|cent/
      :centos
    when /qf-aws-alsp|amazon|amzn|al/
      :amazon_linux
    when /qf-aws-win|microsoft|windows/
      :windows
    else
      # Handeling the platform type when it get's restored from an image
      if platform.downcase == "windows"
        :windows
      elsif platform.nil?
        :linux
      else
        Log.warn "Unable to determine OS type of image (name = #{image_name})"
        :unknown
      end
    end
  end

  # Obtain snapshot ids from the image
  # @param image_id [String] AWS image id value
  # @return [Array] List of snapshot ids
  def ec2_get_snapshot_ids_of_image(image_id)
    raise ArgumentError, "Parameter 'image_id' is mandatory" if image_id.nil? or image_id.empty?

    snapshot_ids = []

    Log.debug "Getting snapshot IDs of image with ImageId=#{image_id.inspect}"

    begin
      response = _ec2_client.describe_images(image_ids: [image_id])
      return [] unless response.images.length == 1

      response.images[0].block_device_mappings.each do |block_device_mapping|
        snapshot_ids << block_device_mapping.ebs.snapshot_id unless block_device_mapping.ebs.nil?
      end

      Log.debug "SnapshotIds of image with ImageId=#{image_id.inspect}: #{snapshot_ids.inspect}"
    rescue Aws::EC2::Errors::InvalidAMIIDNotFound => e
      Log.warn "Unable to locate Image with ID #{image_id.inspect}. Probably deleted - #{e}"
      return []
    rescue => e
      raise "Getting the snapshot IDs of the image with ImageId=#{image_id.inspect} has failed: #{e}"
    end

    return snapshot_ids
  end

  # Deregeisters image from the account
  # @param image_id [String] Target image id
  def ec2_deregister_image(image_id)
    raise ArgumentError, "Parameter 'image_id' is mandatory" if image_id.nil? or image_id.empty?

    begin
      Log.debug "Deregistering AMI #{image_id.inspect}"
      response = _ec2_client.describe_images(image_ids: [image_id])
      if response.images.length == 1
        _ec2_client.deregister_image(image_id: image_id)
        Log.snow "Deregistered AMI (ImageId = #{image_id.inspect})"
      end
    rescue Aws::EC2::Errors::InvalidAMIIDNotFound => e
      Log.debug "Unable to locate image with id #{image_id.inspect}, skipping deregistration - #{e}"
    rescue => e
      Log.snow "ERROR: Failed to deregister AMI (ImageId = #{image_id.inspect})"
      raise "Failed to deregister AMI (ImageId = #{image_id.inspect}) - #{e}"
    end
  end

  # Deletes EC2 snapshots
  # @param snapshot_ids [List] List of snapshots to be deleted
  def ec2_delete_snapshots(snapshot_ids)
    raise ArgumentError, "Parameter 'snapshot_ids' is mandatory" if snapshot_ids.nil?

    Log.debug "Deleting snapshots #{snapshot_ids.inspect}"

    snapshot_ids.each do |snapshot_id|
      Log.debug "Deleting snapshot #{snapshot_id.inspect}"
      begin
        params = {
          snapshot_id: snapshot_id
        }
        _ec2_client.delete_snapshot(params)
        Log.snow "Deleted snapshot (SnapshotId = #{snapshot_id.inspect})"
      rescue => e
        Log.snow "ERROR: Failed to delete snapshot (SnapshotId = #{snapshot_id.inspect})"
        raise "Failed to delete snapshot (SnapshotId = #{snapshot_id.inspect}) - #{e}"
      end
    end
  end

  # Waits for an EBS volume to reach status - available
  # @param volume_id [String] Target volume id
  # @param max_attempts [Integer] Number of maximum attempts
  # @param delay [Integer] Number of seconds between each attempt
  def ec2_wait_until_volume_available(volume_id:, max_attempts: 5, delay: 30)
    return if volume_id.nil? || volume_id.empty?

    Log.debug "Waiting for volume to become available/detached (VolumeId = #{volume_id.inspect})"
    _ec2_client.wait_until(:volume_available, { volume_ids: [volume_id] }) do |waiter|
      waiter.max_attempts = max_attempts
      waiter.delay = delay
    end
  rescue Aws::Waiters::Errors::TooManyAttemptsError => e
    raise "Timed out waiting for volume to become available (VolumeId = #{volume_id.inspect}) - #{e}"
  rescue Aws::Waiters::Errors::WaiterFailed => e
    raise "Error waiting for volume to become available (VolumeId = #{volume_id.inspect}) - #{e}"
  end

  # Wait for an EC2 instance to reach shutdown status
  # @param instance_id [String] Target instance id
  # @param delay [Integer] number of seconds to wait between each attempt
  # @param max_attempts [Integer] number of attempts
  def ec2_wait_for_instance_shutdown(instance_id: nil, delay: 15, max_attempts: 120)
    # Wait for instance to shut down
    Log.debug "Waiting for instance #{instance_id.inspect} to shutdown"
    begin
      _ec2_client.wait_until(:instance_stopped, { instance_ids: [instance_id] }) do |waiter|
        waiter.max_attempts = max_attempts
        waiter.delay = delay
      end
    rescue Aws::Waiters::Errors::TooManyAttemptsError => e
      raise "Shutdown of instance timed out (InstanceId = #{instance_id.inspect}) - #{e}"
    rescue Aws::Waiters::Errors::WaiterFailed => e
      raise "Shutdown of instance failed (InstanceId = #{instance_id.inspect}) - #{e}"
    end
  end

  # Returns the running status of an instance by name
  # @param instance_name [String] Instance Name to check
  # @return [Array] Array of hashes containing the Running status and status code of the matching instances
  def ec2_get_instance_status(instance_name)
    raise ArgumentError, "Parameter 'instance_name' is mandatory" if instance_name.nil? or instance_name.empty?

    begin
      params = {
        filters: [
          { name: 'tag:Name', values: [instance_name] }
        ]
      }
      Log.debug "Checking status for instance with name #{instance_name.inspect}"

      response = _ec2_client.describe_instances(params)

      instances = []
      response.reservations.each do |reservation|
        if reservation.instances.count > 0
          reservation.instances.each do |instance|
            instances.push(instance.state)
          end
        end
      end
      instances.empty? ? nil : instances
    rescue => e
      raise "Could not determine instance with name #{instance_name} status : #{e}"
    end
  end

  def ec2_shutdown_instance(instance_id)
    raise ArgumentError, "Parameter 'instance_id' is mandatory" if instance_id.nil? or instance_id.empty?

    begin
      params = {
        instance_ids: [instance_id]
      }

      Log.debug "Stopping the instance with id #{instance_id.inspect}"
      response = _ec2_client.stop_instances(params)
    rescue => e
      raise "Stopping instance #{instance_id.inspect} has failed: #{e}"
    end

    ec2_wait_for_instance_shutdown(instance_id: instance_id)

    # Retrieve and save the image's outputs
    Log.debug "Instance successfully stopped (InstanceId = #{instance_id.inspect})"
  end

  def ec2_shutdown_instance_and_create_image(instance_id, image_name, tags = [])
    ec2_shutdown_instance(instance_id)
    return ec2_create_image(image_name, instance_id, tags)
  end

  # Returns network interfaces assigned to a security group
  # @param security_group [String] Target security group
  # @return [Array] List of network interfaces
  def ec2_sg_network_interfaces(security_group:)
    response = _ec2_client.describe_network_interfaces(
      filters: [
        { name: 'group-id', values: [security_group] }
      ]
    )
    response.nil? ? [] : response.network_interfaces
  rescue => e
    raise "Failed to retrieve network interfaces for security group #{security_group} - #{e}"
  end

  # Returns network interfaces assigned to a security group
  # @param requester_ids [Array] Target security group
  # @return [Array] List of network interfaces
  def ec2_lambda_network_interfaces(requester_ids:)
    raise 'Request ids values should be array' unless requester_ids.is_a?(Array)

    response = _ec2_client.describe_network_interfaces(
      filters: [
        { name: 'requester-id', values: requester_ids }
      ]
    )
    response.nil? ? [] : response.network_interfaces
  rescue => e
    raise "Failed to retrieve network interfaces for requester id  #{requester_ids.inspect} - #{e}"
  end

  def ec2_detach_network_interfaces(network_interfaces:, force: true)
    # Scan and detach interfaces
    network_interfaces.each do |network_interface|
      next if network_interface.attachment.nil?

      Log.debug "Detaching network interface - #{network_interface.network_interface_id}"
      begin
        _ec2_client.detach_network_interface(
          attachment_id: network_interface.attachment.attachment_id,
          force: force
        )
      rescue => e
        raise "Unable to detach network interface #{network_interface.inspect} - #{e}"
      end
    end

    # wait for and return network interfaces once detached
    ec2_wait_for_network_interfaces(network_interfaces.map(&:network_interface_id))
  end

  def ec2_wait_for_network_interfaces(network_interface_ids)
    return if network_interface_ids.nil? || network_interface_ids.empty?

    _ec2_client.wait_until(:network_interface_available, network_interface_ids: network_interface_ids) do |waiter|
      waiter.max_attempts = 5
      waiter.delay = 30
    end
    return network_interface_ids
  rescue Aws::Waiters::Errors::TooManyAttemptsError => e
    raise ActionError.new, "Unable to detach network interface in time #{network_interface_ids.inspect} - #{e}"
  rescue Aws::Waiters::Errors::WaiterFailed => e
    raise ActionError.new, "Unable to detach network interface #{network_interface_ids.inspect}) - #{e}"
  end

  # Detach and remove network interfaces
  # @param network_interfaces [Array] List of Aws::EC2::Types::NetworkInterface
  def ec2_delete_network_interfaces(network_interfaces)
    return if network_interfaces.nil? || network_interfaces.empty?
    unless network_interfaces.all? { |i| i.is_a? Aws::EC2::Types::NetworkInterface }
      raise ArgumentError, "Expected AWS::EC2::Types::NetworkInterface, received #{network_interfaces.inspect}"
    end

    network_interface_ids = ec2_detach_network_interfaces(
      network_interfaces: network_interfaces,
      force: true
    )

    network_interface_ids.each do |eni_id|
      begin
        Log.debug "Deleting network interface - #{eni_id}"
        _ec2_client.delete_network_interface(network_interface_id: eni_id)
      rescue => e
        raise "Unable to delete network interface #{eni_id} - #{e}"
      end
    end
  end

  def ec2_get_subnets(vpc_id: nil)
    params = {
      filters: [
        # Subnets in this VPC
        { name: "vpc-id", values: [vpc_id] },
        # Subnets with a Name tag
        { name: "tag-key", values: ["Name"] },
      ]
    }

    begin
      response = _ec2_client.describe_subnets(params)
    rescue => e
      raise "Failed to retrieve subnets (VPC id = #{vpc_id}) - #{e}"
    end

    # Extract subnet details into a name-indexed hash
    subnet_map = {}
    response.subnets.each do |subnet|
      name = subnet.tags.select { |tag| tag.key == "Name" }[0].value.downcase
      subnet_map[name] = {
        id: subnet.subnet_id,
        availability_zone: subnet.availability_zone,
        available_ips: subnet.available_ip_address_count
      }
    end

    return subnet_map
  end

  def ec2_get_availability_zones
    begin
      response = _ec2_client.describe_availability_zones
      zones = response.availability_zones.map { |zone| zone.zone_name }
    rescue => e
      raise "Failed to retrieve availability zones - #{e}"
    end

    alias_to_zone_map = {}

    return zones
  end

  def _ip_permissions_to_hash_array(ip_permissions)
    return ip_permissions.map do |ip_permission|
      permission = {
        ip_protocol: ip_permission.ip_protocol,
        from_port: ip_permission.from_port,
        to_port: ip_permission.to_port,
      }
      if !ip_permission.ip_ranges.empty?
        permission[:ip_ranges] = ip_permission.ip_ranges
      elsif !ip_permission.prefix_list_ids.empty?
        permission[:prefix_list_ids] = ip_permission.prefix_list_ids
      elsif !ip_permission.user_id_group_pairs.empty?
        permission[:user_id_group_pairs] = ip_permission.user_id_group_pairs
      else
        next
      end

      next permission
    end
  end

  def ec2_clear_security_group_rules(security_group_ids)
    security_group_ids = Array(security_group_ids).compact
    return if security_group_ids.empty?

    begin
      sg_info = _ec2_client.describe_security_groups(group_ids: security_group_ids)
      sg_info.security_groups.each do |security_group|
        unless security_group_ids.include? security_group.group_id
          raise "describe_security_groups returned security group #{security_group.group_id.inspect} which is NOT in the requested list #{security_group_ids.inspect}"
        end

        Log.debug "Clearing rules for security group #{security_group.group_id.inspect}"

        # Clear ingress rules
        unless security_group.ip_permissions.empty?
          _ec2_client.revoke_security_group_ingress(
            group_id: security_group.group_id,
            ip_permissions: _ip_permissions_to_hash_array(security_group.ip_permissions),
          )
        end

        # Clear egress rules
        unless security_group.ip_permissions_egress.empty?
          _ec2_client.revoke_security_group_egress(
            group_id: security_group.group_id,
            ip_permissions: _ip_permissions_to_hash_array(security_group.ip_permissions_egress),
          )
        end
      end
    rescue Aws::EC2::Errors::InvalidGroupNotFound => e
      # If group is not found. skip processing
      Log.warn "One or more security groups not found - #{e}"
    rescue => e
      raise "Failed to clear security group rules - #{e} - #{e.class}"
    end
  end

  def ec2_detach_volume(volume_id, force = true)
    raise "Parameter volume_id must be specified" if volume_id.nil? or volume_id.empty?

    begin
      _ec2_client.detach_volume(volume_id: volume_id, force: force)
    rescue => e
      raise "Failed to detach volume (id = #{volume_id}, force = #{force}) - #{e}"
    end
  end

  def _ec2_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @ec2_client.nil?

        # Create the EC2 client
        Log.debug "Creating a new AWS EC2 client"

        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?

        if _provisioning_credentials
          # We have specific provisioning credentials to use
          params[:credentials] = _provisioning_credentials
        elsif _control_credentials
          # No provisioning credentials but we do have control credentials to use
          params[:credentials] = _control_credentials
        end

        @ec2_client = Aws::EC2::Client.new(params)
      end
    end

    return @ec2_client
  end

  # Query and return snapshot attributes
  # @param snapshot_id [String] Physical snapshot id
  # @return [Object] Snapshot attributes response object
  def ec2_describe_volume_snapshot_attributes(snapshot_id:)
    response = _ec2_client.describe_snapshots(snapshot_ids: [snapshot_id])
    return response.snapshots.first
  rescue => e
    message = "ERROR: Failed to Describe EC2 volume snapshot (EBS Snapshot id = #{snapshot_id})"
    Log.snow "#{message} - #{e}"
    Log.error "#{message} - #{e}"
    raise "#{message} - #{e}"
  end

  # Execute copy of RDS snapshot with optional re-encryption parameter
  # @param source_snapshot_id [String] Source physical snapshot id
  # @param kms_key_id [String] KMS CMK Arn to be used for encryption
  # @param tags [Hash] Key/Value pairs to be assigned as tags on the snapshot
  def ec2_copy_volume_snapshot(source_snapshot_id:, kms_key_id: nil, tags: nil)
    params = {
      source_snapshot_id: source_snapshot_id,
      encrypted: true,
      kms_key_id: kms_key_id
    }
    params[:source_region] = @region unless @region.nil?
    response = _ec2_client.copy_snapshot(params)
    _ec2_client.create_tags(resources: [response.snapshot_id], tags: tags) unless tags.nil? or tags.empty?
    Log.info "Creating a a copy of #{source_snapshot_id} snapshot -> #{response.snapshot_id}"
    return response.snapshot_id
  rescue => e
    Log.snow "ERROR: Failed to create copy of the volume snapshot (EBS SnapshotID = #{source_snapshot_id})"
    Log.error "ERROR: Failed to create copy of the volume snapshot (EBS SnapshotID = #{source_snapshot_id})"
    raise "Failed to create copy of the volume snapshot #{source_snapshot_id} - #{e}"
  end

  # Wait for a volume snapshot to reach status 'available'
  # @param snapshot_id [String] Physical snapshot id
  # @param max_attempts [Integer] Maximum number of attempts
  # @param delay [Integer] Delay in seconds between each query attempt
  def ec2_wait_for_volume_snapshot(
    snapshot_id:,
    max_attempts: 5,
    delay: 30
  )
    Log.debug "Waiting for the snapshot #{snapshot_id} to become available"
    _ec2_client.wait_until(:snapshot_completed, { snapshot_ids: [snapshot_id] }) do |waiter|
      waiter.max_attempts = max_attempts
      waiter.delay = delay
    end
  rescue Aws::Waiters::Errors::TooManyAttemptsError => e
    raise ActionError.new, "Unable to create a copy snapshot #{snapshot_id} - #{e}"
  rescue Aws::Waiters::Errors::WaiterFailed => e
    raise ActionError.new, "Unable to create a copy snapshot  #{snapshot_id}) - #{e}"
  end

  # Validates if snapshot is correctly encrypted
  # Initiates snapshot copy with valid kms_key_id for re-encryption
  # @param snapshot_id [String] Physical snapshot id
  # @param component_name [String] Target component name
  def ec2_validate_or_copy_snapshot(
    snapshot_id:,
    component_name: nil,
    sections:,
    cmk_arn: nil
  )

    snapshot_attributes = ec2_describe_volume_snapshot_attributes(snapshot_id: snapshot_id)
    tags = {}
    snapshot_attributes.tags.each do |tag|
      tags[tag.key] = tag.value
    end

    raise "ERROR: Couldn't find tags on the snapshot #{snapshot_id.inspect}" if tags.empty?

    unless StringUtils.compare_upcase(tags['AMSID'], sections[:ams]) and
           StringUtils.compare_upcase(tags['EnterpriseAppID'], sections[:qda]) and
           StringUtils.compare_upcase(tags['ApplicationServiceID'], sections[:as])
      raise "ERROR: The Snapshot ID #{snapshot_id.inspect} does not belong to "\
            "the current Application Service ID #{sections[:qda].upcase}-#{sections[:as].upcase}"
    end

    raise "KMS key for application service #{Defaults.kms_secrets_key_alias} is not found." if cmk_arn.nil?

    if snapshot_attributes.encrypted && cmk_arn == snapshot_attributes.kms_key_id
      Log.info "Component #{component_name} snapshot #{snapshot_id} is encrypted"\
        " with the correct CMK: #{cmk_arn}"
      return snapshot_id
    end

    Log.info "Component #{component_name} snapshot #{snapshot_id} IS NOT"\
      " encrypted with the correct CMK: #{cmk_arn}"

    copy_snapshot_identifier = ec2_copy_volume_snapshot(
      source_snapshot_id: snapshot_id,
      kms_key_id: cmk_arn,
      tags: Defaults.get_tags(component_name)
    )

    ec2_wait_for_volume_snapshot(
      snapshot_id: copy_snapshot_identifier,
      delay: 120,
      max_attempts: 240
    )

    # Return the new RDS snapshot id with KMS keu id
    copy_snapshot_identifier
  rescue => e
    Log.error "FAIL: Unable to copy or validate snapshot #{component_name} - #{e}"
    raise "Unable to copy or validate snapshot #{snapshot_id} - #{e}"
  end

  # Obtain latest snapshot id based on supplied volume_id
  # @param volume_name [String] Original volume name (tag)
  def ec2_latest_snapshot(volume_name:)
    Log.info "Querying EBS snapshots for volume '#{volume_name}'"
    latest_snapshot = nil
    params = {
      filters: [
        { name: "tag-value", values: [volume_name] },
        { name: "tag-key", values: ['Name'] }
      ]
    }

    next_token = nil
    loop do
      params[:next_token] = next_token

      # Iterate over the many pages of possible results from the RDS API
      resp = _ec2_client.describe_snapshots(params)

      next_token = resp.next_token
      resp.snapshots.each do |snapshot|
        if latest_snapshot.nil? || snapshot.start_time > latest_snapshot.start_time
          latest_snapshot = snapshot
        end
      end
      break if next_token.nil? || next_token.empty?
    end

    if latest_snapshot.nil?
      Log.warn "Unable to find the latest snapshot for volume '#{volume_name}'"
    else
      Log.info "Found snapshot #{latest_snapshot.snapshot_id.inspect} created on"\
        " '#{latest_snapshot.start_time}' "
      latest_snapshot.snapshot_id
    end
  end
end
