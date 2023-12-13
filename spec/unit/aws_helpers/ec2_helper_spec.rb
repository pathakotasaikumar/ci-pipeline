$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'ec2_helper'

describe 'Ec2Helper' do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(Ec2Helper)
    @kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  end

  context 'ec2_client' do
    it 'initialize without error' do
      allow(Aws::EC2::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials).and_return(false)
      allow(AwsHelper).to receive(:_control_credentials).and_return(false)
      expect { AwsHelper._ec2_client }.not_to raise_exception
    end

    it 'initialize with provisioning_credentials' do
      allow(Aws::EC2::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials).and_return(true)
      expect { AwsHelper._ec2_client }.not_to raise_exception
    end

    it 'initialize with control_credentials' do
      allow(Aws::EC2::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials).and_return(true)
      expect { AwsHelper._ec2_client }.not_to raise_exception
    end
  end

  context 'ec2_add_launch_permission' do
    it 'success - adds launch permission' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:modify_image_attribute)
        .with(image_id: 'ami-123456', launch_permission: { add: [{ user_id: '123456789012' }] }).and_return(nil)
      expect {
        AwsHelper.ec2_add_launch_permission(
          image_id: 'ami-123456',
          accounts: ['123456789012']
        )
      }.not_to raise_exception
    end

    it 'fail to add launch permission' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:modify_image_attribute)
        .with(image_id: 'ami-123456', launch_permission: { add: [{ user_id: '123456789012' }] }).and_raise(RuntimeError)
      expect {
        AwsHelper.ec2_add_launch_permission(
          image_id: 'ami-123456',
          accounts: ['123456789012']
        )
      }.to raise_exception(RuntimeError)
    end
  end

  context 'ec2_create_volume_snapshot' do
    it 'succeeds' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      ec2_mock_waiter = double(Object)
      allow(ec2_mock_waiter).to receive(:max_attempts=)
      allow(ec2_mock_waiter).to receive(:delay=)
      allow(ec2_mock_client).to receive(:wait_until) { |&block| block.call(ec2_mock_waiter) }
      allow(ec2_mock_client).to receive(:create_snapshot).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:snapshot_id).and_return('snap-1234567890')
      allow(ec2_mock_client).to receive(:create_tags)
      expect {
        AwsHelper.ec2_create_volume_snapshot(
          volume_id: 'vol-12345678',
          description: 'test snap',
          tags: { key: 'name', value: 'test' }
        )
      }.not_to raise_exception
    end

    it 'fails with ArgumentError' do
      expect { AwsHelper.ec2_create_volume_snapshot() }.to raise_exception(ArgumentError)
    end

    it 'fails with Aws::Waiters::Errors::TooManyAttemptsError' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::TooManyAttemptsError.new(1))
      expect {
        AwsHelper.ec2_create_volume_snapshot(volume_id: 'vol-1234567')
      }.to raise_exception(ActionError, /Unable to snapshot volume cleanly vol-1234567/)
    end

    it 'fails with Aws::Waiters::Errors::WaiterFailed' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::WaiterFailed)
      expect {
        AwsHelper.ec2_create_volume_snapshot(volume_id: 'vol-1234567')
      }.to raise_exception(ActionError, /Unable to snapshot volume cleanly vol-1234567/)
    end

    it 'fails with - Failed to create volume snapshot' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:wait_until)
      allow(ec2_mock_client).to receive(:create_snapshot).and_raise(RuntimeError)
      expect {
        AwsHelper.ec2_create_volume_snapshot(
          volume_id: 'vol-12345678',
          description: 'test snap',
          tags: { key: 'name', value: 'test' }
        )
      }.to raise_error /Failed to create volume snapshot vol-12345678/
    end
  end

  context 'ec2_copy_image' do
    it 'succeeds' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:copy_image).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:image_id).and_return('ami-123456')
      ec2_mock_waiter = double(Object)
      allow(ec2_mock_waiter).to receive(:max_attempts=)
      allow(ec2_mock_waiter).to receive(:delay=)
      allow(ec2_mock_client).to receive(:wait_until) { |&block| block.call(ec2_mock_waiter) }
      allow(AwsHelper).to receive(:ec2_get_snapshot_ids_of_image).and_return([])
      allow(ec2_mock_client).to receive(:create_tags)
      expect {
        AwsHelper.ec2_copy_image(
          source_image_id: 'ami-22222222',
          name: 'test image',
          source_region: 'ap-southeast-2',
          tags: { key: 'name', value: 'test' }
        )
      }.not_to raise_exception
    end

    it 'succeeds' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:copy_image).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:image_id).and_return('ami-123456')
      ec2_mock_waiter = double(Object)
      allow(ec2_mock_waiter).to receive(:max_attempts=)
      allow(ec2_mock_waiter).to receive(:delay=)
      allow(ec2_mock_client).to receive(:wait_until) { |&block| block.call(ec2_mock_waiter) }
      allow(AwsHelper).to receive(:ec2_get_snapshot_ids_of_image).and_return([])
      allow(ec2_mock_client).to receive(:create_tags)
      expect {
        AwsHelper.ec2_copy_image(
          source_image_id: 'ami-22222222',
          name: 'test image',
          source_region: 'ap-southeast-2',
          tags: { key: 'name', value: 'test' },
          encrypted: true
        )
      }.not_to raise_exception
    end

    it 'fails with - Failed to tag AMI and snapshots' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:copy_image).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:image_id).and_return('ami-123456')
      allow(ec2_mock_client).to receive(:wait_until)
      allow(AwsHelper).to receive(:ec2_get_snapshot_ids_of_image).and_return([])
      allow(ec2_mock_client).to receive(:create_tags).and_raise(StandardError)
      expect {
        AwsHelper.ec2_copy_image(
          source_image_id: 'ami-22222222',
          name: 'test image',
          source_region: 'ap-southeast-2',
          tags: { key: 'name', value: 'test' }
        )
      }.to raise_exception(/Failed to tag AMI and snapshots/)
    end

    it 'fails with ArgumentError' do
      expect { AwsHelper.ec2_copy_image }.to raise_exception(ArgumentError)
    end

    it 'fails with Aws::Waiters::Errors::TooManyAttemptsError' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:copy_image).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:image_id).and_return('ami-123456')
      allow(ec2_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::TooManyAttemptsError.new(1))
      expect {
        AwsHelper.ec2_copy_image(
          source_image_id: 'ami-22222222',
          name: 'test image',
          source_region: 'ap-southeast-2',
          tags: { key: 'name', value: 'test' }
        )
      }.to raise_exception(ActionError, /EC2 AMI creation timed out/)
    end

    it 'fails with Aws::Waiters::Errors::WaiterFailed' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:copy_image).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:image_id).and_return('ami-123456')
      allow(ec2_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::WaiterFailed)
      expect {
        AwsHelper.ec2_copy_image(
          source_image_id: 'ami-22222222',
          name: 'test image',
          source_region: 'ap-southeast-2',
          tags: { key: 'name', value: 'test' }
        )
      }.to raise_exception(ActionError, /EC2 AMI creation failed/)
    end

    it 'fails with Failed to copy AMI' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:copy_image).and_raise(RuntimeError)
      expect {
        AwsHelper.ec2_copy_image(
          source_image_id: 'ami-22222222',
          name: 'test image',
          source_region: 'ap-southeast-2',
          tags: { key: 'name', value: 'test' }
        )
      }.to raise_exception /Failed to copy AMI/
    end
  end

  context 'ec2_create_image' do
    it 'succeeds' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:create_image).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:image_id).and_return('ami-123456')
      ec2_mock_waiter = double(Object)
      allow(ec2_mock_waiter).to receive(:max_attempts=)
      allow(ec2_mock_waiter).to receive(:delay=)
      allow(ec2_mock_client).to receive(:wait_until) { |&block| block.call(ec2_mock_waiter) }
      allow(AwsHelper).to receive(:ec2_get_snapshot_ids_of_image).and_return([])
      allow(ec2_mock_client).to receive(:create_tags)
      expect {
        AwsHelper.ec2_create_image(
          'test image',
          'i-123456789012',
          { key: 'name', value: 'test' }
        )
      }.not_to raise_exception
    end

    it 'fails with Failed to tag AMI and snapshots' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:create_image).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:image_id).and_return('ami-123456')
      ec2_mock_waiter = double(Object)
      allow(ec2_mock_waiter).to receive(:max_attempts=)
      allow(ec2_mock_waiter).to receive(:delay=)
      allow(ec2_mock_client).to receive(:wait_until) { |&block| block.call(ec2_mock_waiter) }
      allow(AwsHelper).to receive(:ec2_get_snapshot_ids_of_image).and_return([])
      allow(ec2_mock_client).to receive(:create_tags).and_raise(StandardError)
      expect {
        AwsHelper.ec2_create_image(
          'test image',
          'i-123456789012',
          { key: 'name', value: 'test' }
        )
      }.to raise_exception (/Failed to tag AMI and snapshots/)
    end

    it 'fails with ArgumentError' do
      expect { AwsHelper.ec2_create_image }.to raise_exception(ArgumentError)
    end

    it 'fails with Failed to copy AMI' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:create_image).and_raise(RuntimeError)
      expect {
        AwsHelper.ec2_create_image(
          'test image',
          'i-123456789012',
          { key: 'name', value: 'test' }
        )
      }.to raise_exception /Failed to create AMI /
    end

    it 'fails with Aws::Waiters::Errors::TooManyAttemptsError' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:create_image).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:image_id).and_return('ami-123456')
      allow(ec2_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::TooManyAttemptsError.new(1))
      expect {
        AwsHelper.ec2_create_image(
          'test image',
          'i-123456789012',
          { key: 'name', value: 'test' }
        )
      }.to raise_exception(ActionError, /EC2 AMI creation timed out/)
    end

    it 'fails with Aws::Waiters::Errors::WaiterFailed' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:create_image).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:image_id).and_return('ami-123456')
      allow(ec2_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::WaiterFailed)
      expect {
        AwsHelper.ec2_create_image(
          'test image',
          'i-123456789012',
          { key: 'name', value: 'test' }
        )
      }.to raise_exception(ActionError, /EC2 AMI creation failed/)
    end
  end

  context 'ec2_delete_image' do
    it 'fails with Failed to copy AMI' do
      allow(AwsHelper).to receive(:ec2_get_snapshot_ids_of_image).and_return([])
      allow(AwsHelper).to receive(:ec2_deregister_image)
      allow(AwsHelper).to receive(:ec2_delete_snapshots)
      expect {
        AwsHelper.ec2_delete_image('ami-12345678')
      }.not_to raise_exception
    end

    it 'fails with ArgumentError' do
      expect { AwsHelper.ec2_delete_image }.to raise_exception(ArgumentError)
    end
  end

  context 'ec2_platform_from_image' do
    it 'succeed - rhel' do
      expect(AwsHelper.ec2_platform_from_image 'qf-aws-rhel', nil).to eq(:rhel)
    end

    it 'succeed - amazon' do
      expect(AwsHelper.ec2_platform_from_image 'amazon', nil).to eq(:amazon_linux)
    end

    it 'succeed - windows' do
      expect(AwsHelper.ec2_platform_from_image 'windows', 'windows').to eq(:windows)
    end

    it 'succeed - centos' do
      expect(AwsHelper.ec2_platform_from_image 'centos', nil).to eq(:centos)
      expect(AwsHelper.ec2_platform_from_image 'cent os', nil).to eq(:centos)
      expect(AwsHelper.ec2_platform_from_image 'qf-aws-centos', nil).to eq(:centos)
    end

    it 'succeed - unknown' do
      expect(AwsHelper.ec2_platform_from_image 'ubuntu', 'ubuntu').to eq(:unknown)
    end
  end

  context 'ec2_versioned_image_name' do
    it 'succeeds' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_image = double(Object)

      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_images).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:images).and_return([ec2_mock_image])
      allow(ec2_mock_image).to receive(:name).and_return('dummy-image-name')
      expect {
        AwsHelper.ec2_versioned_image_name(
          prefix: 'dummy-prefix',
          owners: ['123456789012']
        )
      }.not_to raise_exception
    end

    it 'fails with Unable to determine a version for the image prefix' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_images).and_raise(StandardError)
      expect {
        AwsHelper.ec2_versioned_image_name(
          prefix: 'dummy-prefix',
          owners: ['123456789012']
        )
      }.to raise_exception(/Unable to determine a version for the image prefix/)
    end

    it 'fails with ArgumentError' do
      expect {
        AwsHelper.ec2_versioned_image_name(
          owners: ['123456789012']
        )
      }.to raise_exception ArgumentError
    end

    it 'validate the image name if it returns too many images' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_image_1 = double(Object)
      ec2_mock_image_2 = double(Object)

      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_images).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:images).and_return([ec2_mock_image_1, ec2_mock_image_2])
      allow(ec2_mock_image_1).to receive(:name).and_return('dummy-prefix.1')
      allow(ec2_mock_image_2).to receive(:name).and_return('dummy-prefix.2')
      expect(AwsHelper.ec2_versioned_image_name(
               prefix: 'dummy-prefix',
               owners: ['123456789012']
             )).to eq('dummy-prefix.3')
    end

    it 'validate the default image name' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)

      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_images).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:images).and_return([])
      expect(AwsHelper.ec2_versioned_image_name(
               prefix: 'dummy-prefix',
               owners: ['123456789012']
             )).to eq('dummy-prefix.1')
    end
  end

  context 'ec2_get_image_details' do
    it 'succeeds on image id' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_image = double(Object)

      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_images).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:images).and_return([ec2_mock_image])
      allow(AwsHelper).to receive(:ec2_platform_from_image).and_return(:rhel)
      allow(ec2_mock_image).to receive(:name).and_return('dummy-image-name')
      allow(ec2_mock_image).to receive(:image_id).and_return('ami-12345678')
      allow(ec2_mock_image).to receive(:tags).and_return([{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }])
      allow(ec2_mock_image).to receive(:description).and_return('Dummy Image')
      allow(ec2_mock_image).to receive(:state).and_return('Available')
      allow(ec2_mock_image).to receive(:platform).and_return(nil)
      expect(AwsHelper.ec2_get_image_details('ami-12345678')).to eq(
        name: "dummy-image-name",
        id: "ami-12345678",
        description: "Dummy Image",
        tags: [{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }],
        state: "Available",
        platform: :rhel
      )
    end

    it 'succeeds on image name' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_image = double(Object)

      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_images).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:images).and_return([ec2_mock_image])
      allow(AwsHelper).to receive(:ec2_platform_from_image).and_return(:rhel)
      allow(ec2_mock_image).to receive(:name).and_return('dummy-image-name')
      allow(ec2_mock_image).to receive(:image_id).and_return('ami-12345678')
      allow(ec2_mock_image).to receive(:tags).and_return([{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }])
      allow(ec2_mock_image).to receive(:description).and_return('Dummy Image')
      allow(ec2_mock_image).to receive(:state).and_return('Available')
      allow(ec2_mock_image).to receive(:platform).and_return(nil)
      expect(AwsHelper.ec2_get_image_details('Test Image'))
        .to eq(
          name: "dummy-image-name",
          id: "ami-12345678",
          description: "Dummy Image",
          tags: [{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }],
          state: "Available",
          platform: :rhel
        )
    end

    it 'succeeds on multile image id' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_image = double(Object)

      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_images).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:images).and_return([ec2_mock_image, ec2_mock_image])
      allow(AwsHelper).to receive(:ec2_platform_from_image).and_return(:rhel)
      allow(ec2_mock_image).to receive(:creation_date).and_return('dummy-date')
      allow(ec2_mock_image).to receive(:name).and_return('dummy-image-name')
      allow(ec2_mock_image).to receive(:image_id).and_return('ami-12345678')
      allow(ec2_mock_image).to receive(:tags).and_return([{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }])
      allow(ec2_mock_image).to receive(:description).and_return('Dummy Image')
      allow(ec2_mock_image).to receive(:state).and_return('Available')
      allow(ec2_mock_image).to receive(:platform).and_return(nil)
      expect(AwsHelper.ec2_get_image_details('ami-12345678'))
        .to eq(
          name: "dummy-image-name",
          id: "ami-12345678",
          description: "Dummy Image",
          tags: [{ key: "SOE_ID", value: "qf-aws-win2016-x86_64-1000.1" }],
          state: "Available",
          platform: :rhel
        )
    end

    it 'fails with - No images returned from search' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_image = double(Object)

      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_images).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:images).and_return([])
      expect { AwsHelper.ec2_get_image_details('ami-12345678') }
        .to raise_exception /No images returned from search/
    end

    it 'fails with - Unable to find image' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_image = double(Object)

      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_images).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:images).and_raise(RuntimeError)
      expect { AwsHelper.ec2_get_image_details('ami-12345678') }
        .to raise_exception /Unable to find image/
    end
  end

  context 'ec2_get_snapshot_ids_of_image' do
    it 'successful execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_image = double(Object)
      ec2_mock_block_device_mappings = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_images).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:images).and_return([ec2_mock_image])
      allow(ec2_mock_image).to receive(:block_device_mappings).and_return([ec2_mock_block_device_mappings])
      allow(ec2_mock_block_device_mappings).to receive_message_chain('ebs.snapshot_id').and_return('snap-12345678')
      expect {
        AwsHelper.ec2_get_snapshot_ids_of_image('ami-12345678')
      }.not_to raise_exception
    end

    it 'fails with Aws::EC2::Errors::InvalidAMIIDNotFound' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_image = double(Object)
      ec2_mock_block_device_mappings = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_images).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:images).and_return([ec2_mock_image])
      allow(ec2_mock_image).to receive(:block_device_mappings).and_return([ec2_mock_block_device_mappings])
      allow(ec2_mock_block_device_mappings).to receive_message_chain('ebs.snapshot_id').and_raise(Aws::EC2::Errors::InvalidAMIIDNotFound.new(1, 'dummy'))
      expect {
        AwsHelper.ec2_get_snapshot_ids_of_image('ami-12345678')
      }.not_to raise_exception
    end

    it 'fails with RuntimeError' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_image = double(Object)
      ec2_mock_block_device_mappings = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_images).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:images).and_return([ec2_mock_image])
      allow(ec2_mock_image).to receive(:block_device_mappings).and_return([ec2_mock_block_device_mappings])
      allow(ec2_mock_block_device_mappings).to receive_message_chain('ebs.snapshot_id').and_raise(RuntimeError)
      expect {
        AwsHelper.ec2_get_snapshot_ids_of_image('ami-12345678')
      }.to raise_exception /Getting the snapshot IDs of the image with ImageId/
    end

    it 'fails with ArgumentError' do
      expect { AwsHelper.ec2_get_snapshot_ids_of_image }.to raise_exception(ArgumentError)
    end
  end

  context 'ec2_deregister_image' do
    it 'successful execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_image = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_images).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:images).and_return([ec2_mock_image])
      allow(ec2_mock_client).to receive(:deregister_image)
      expect {
        AwsHelper.ec2_deregister_image('ami-12345678')
      }.not_to raise_exception
    end

    it 'fails with Aws::EC2::Errors::InvalidAMIIDNotFound' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_image = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_images).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:images).and_return([ec2_mock_image])
      allow(ec2_mock_client).to receive(:deregister_image).and_raise(Aws::EC2::Errors::InvalidAMIIDNotFound.new(nil, nil))
      expect {
        AwsHelper.ec2_deregister_image('ami-12345678')
      }.not_to raise_exception
    end

    it 'fails with RuntimeError' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_image = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_images).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:images).and_return([ec2_mock_image])
      allow(ec2_mock_client).to receive(:deregister_image).and_raise(RuntimeError)
      expect {
        AwsHelper.ec2_deregister_image('ami-12345678')
      }.to raise_exception /Failed to deregister AMI/
    end

    it 'fails with ArgumentError' do
      expect { AwsHelper.ec2_deregister_image }.to raise_exception(ArgumentError)
    end
  end

  context 'ec2_delete_snapshots' do
    it 'successful execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:delete_snapshot)
      expect {
        AwsHelper.ec2_delete_snapshots(['snap-123456', 'snap-234567'])
      }.not_to raise_exception
    end

    it 'fails with RuntimeError' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:delete_snapshot).and_raise(RuntimeError)
      expect {
        AwsHelper.ec2_delete_snapshots(['snap-123456', 'snap-234567'])
      }.to raise_exception /Failed to delete snapshot /
    end

    it 'fails with ArgumentError' do
      expect { AwsHelper.ec2_delete_snapshots }.to raise_exception(ArgumentError)
    end
  end

  context 'ec2_wait_until_volume_available' do
    it 'successful execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      ec2_mock_waiter = double(Object)
      allow(ec2_mock_waiter).to receive(:max_attempts=)
      allow(ec2_mock_waiter).to receive(:delay=)
      allow(ec2_mock_client).to receive(:wait_until) { |&block| block.call(ec2_mock_waiter) }
      expect {
        AwsHelper.ec2_wait_until_volume_available(volume_id: 'vol-12345678')
      }.not_to raise_exception
    end

    it 'fails with Aws::Waiters::Errors::TooManyAttemptsError' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::TooManyAttemptsError.new(1))
      expect {
        AwsHelper.ec2_wait_until_volume_available(volume_id: 'vol-12345678')
      }.to raise_exception /Timed out waiting for volume to become available /
    end

    it 'fails with Aws::Waiters::Errors::WaiterFailed' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::WaiterFailed)
      expect {
        AwsHelper.ec2_wait_until_volume_available(volume_id: 'vol-12345678')
      }.to raise_exception /Error waiting for volume to become available/
    end

    it 'fails with ArgumentError' do
      expect { AwsHelper.ec2_wait_until_volume_available }.to raise_exception(ArgumentError)
    end
  end

  context 'ec2_wait_for_instance_shutdown' do
    it 'successful execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      ec2_mock_waiter = double(Object)
      allow(ec2_mock_waiter).to receive(:max_attempts=)
      allow(ec2_mock_waiter).to receive(:delay=)
      allow(ec2_mock_client).to receive(:wait_until) { |&block| block.call(ec2_mock_waiter) }
      expect {
        AwsHelper.ec2_wait_for_instance_shutdown(
          instance_id: 'i-1234566789012'
        )
      }.not_to raise_exception
    end

    it 'fails with Aws::Waiters::Errors::TooManyAttemptsError' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::TooManyAttemptsError.new(1))
      expect {
        AwsHelper.ec2_wait_for_instance_shutdown(
          instance_id: 'i-1234566789012'
        )
      }.to raise_exception /Shutdown of instance timed out/
    end

    it 'fails with Aws::Waiters::Errors::WaiterFailed' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::WaiterFailed)
      expect {
        AwsHelper.ec2_wait_for_instance_shutdown(
          instance_id: 'i-1234566789012'
        )
      }.to raise_exception /Shutdown of instance failed/
    end
  end

  context 'ec2_shutdown_instance' do
    it 'successful execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:stop_instances)
      allow(AwsHelper).to receive(:ec2_wait_for_instance_shutdown)
      expect {
        AwsHelper.ec2_shutdown_instance('i-1234566789012')
      }.not_to raise_exception
    end

    it 'fails with ArgumentError' do
      expect { AwsHelper.ec2_shutdown_instance }.to raise_exception(ArgumentError)
    end

    it 'fails with Stopping instance i-1234566789012 has failed' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:stop_instances).and_raise(RuntimeError)
      expect {
        AwsHelper.ec2_shutdown_instance('i-1234566789012')
      }.to raise_exception /Stopping instance "i-1234566789012" has failed/
    end
  end

  context 'ec2_get_instance_status' do
    it 'successful execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      response = double(Object)
      reservation = double(Object)
      instance = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_instances).and_return(response)
      allow(response).to receive(:reservations).and_return([reservation])
      allow(reservation).to receive(:instances).and_return([instance])
      allow(instance).to receive(:state).and_return("Running")
      expect {
        AwsHelper.ec2_get_instance_status('i-1234566789012')
      }.not_to raise_exception
    end

    it 'failed execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      expect {
        AwsHelper.ec2_get_instance_status(
          nil
        )
      }.to raise_exception /Parameter 'instance_name' is mandatory/
    end
  end

  context 'ec2_shutdown_instance_and_create_image' do
    it 'successful execution' do
      allow(AwsHelper).to receive(:ec2_shutdown_instance)
      allow(AwsHelper).to receive(:ec2_create_image)
      expect {
        AwsHelper.ec2_shutdown_instance_and_create_image(
          'i-123456789012',
          'test-image',
          []
        )
      }.not_to raise_exception
    end
  end

  context 'ec2_sg_network_interfaces' do
    it 'successful execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_interface = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_network_interfaces).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:network_interfaces).and_return([ec2_mock_interface])
      expect {
        AwsHelper.ec2_sg_network_interfaces(security_group: 'sg-12345678')
      }.not_to raise_exception
    end

    it 'fails with ArgumentError' do
      expect { AwsHelper.ec2_sg_network_interfaces }.to raise_exception(ArgumentError)
    end

    it 'fails with Failed to retrieve network interfaces for security group' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_network_interfaces).and_raise(RuntimeError)

      expect {
        AwsHelper.ec2_sg_network_interfaces(security_group: 'sg-12345678')
      }.to raise_error /Failed to retrieve network interfaces for security group sg-12345678/
    end
  end

  context 'ec2_lambda_network_interfaces' do
    it 'successful execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_interface = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_network_interfaces).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:network_interfaces).and_return([ec2_mock_interface])
      expect {
        AwsHelper.ec2_lambda_network_interfaces(requester_ids: ['*:testing'])
      }.not_to raise_exception
    end

    it 'fails with ArgumentError' do
      expect { AwsHelper.ec2_sg_network_interfaces }.to raise_exception(ArgumentError)
    end

    it 'fails with Failed to retrieve network interfaces for security group' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_network_interfaces).and_raise(RuntimeError)

      expect {
        AwsHelper.ec2_lambda_network_interfaces(requester_ids: ['*:testing'])
      }.to raise_error /Failed to retrieve network interfaces for requester id/
    end
  end

  context 'ec2_detach_network_interfaces' do
    it 'successful execution' do
      ec2_mock_interface = double(Object)
      ec2_mock_attachment = double(Object)
      allow(ec2_mock_interface).to receive(:attachment).and_return(ec2_mock_attachment)
      allow(ec2_mock_interface).to receive(:network_interface_id).and_return('eni-12345678')
      allow(ec2_mock_attachment).to receive(:attachment_id).and_return('dummy-attachment')

      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:detach_network_interface)
      allow(AwsHelper).to receive(:ec2_wait_for_network_interfaces)
      expect {
        AwsHelper.ec2_detach_network_interfaces(
          network_interfaces: [ec2_mock_interface]
        )
      }.not_to raise_exception
    end

    it 'fails with ArgumentError' do
      expect { AwsHelper.ec2_detach_network_interfaces }.to raise_exception(ArgumentError)
    end

    it 'fails with Unable to detach network interface' do
      ec2_mock_interface = double(Object)
      ec2_mock_attachment = double(Object)
      allow(ec2_mock_interface).to receive(:attachment).and_return(ec2_mock_attachment)
      allow(ec2_mock_interface).to receive(:network_interface_id).and_return('eni-12345678')
      allow(ec2_mock_attachment).to receive(:attachment_id).and_return('dummy-attachment')

      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:detach_network_interface).and_raise(RuntimeError)
      expect {
        AwsHelper.ec2_detach_network_interfaces(
          network_interfaces: [ec2_mock_interface]
        )
      }.to raise_exception /Unable to detach network interface/
    end
  end

  context 'ec2_wait_for_network_interfaces' do
    it 'successful execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      ec2_mock_waiter = double(Object)
      allow(ec2_mock_waiter).to receive(:max_attempts=)
      allow(ec2_mock_waiter).to receive(:delay=)
      allow(ec2_mock_client).to receive(:wait_until) { |&block| block.call(ec2_mock_waiter) }

      expect {
        AwsHelper.ec2_wait_for_network_interfaces(['eni-12345678'])
      }.not_to raise_exception
    end

    it 'fails with Aws::Waiters::Errors::TooManyAttemptsError' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::TooManyAttemptsError.new(1))
      expect {
        AwsHelper.ec2_wait_for_network_interfaces(['eni-12345678'])
      }.to raise_exception /Unable to detach network interface in time \["eni-12345678"\]/
    end

    it 'fails with Aws::Waiters::Errors::WaiterFailed' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::WaiterFailed)
      expect {
        AwsHelper.ec2_wait_for_network_interfaces(['eni-12345678'])
      }.to raise_exception /Unable to detach network interface \["eni-12345678"\]/
    end
  end

  context 'ec2_delete_network_interfaces' do
    it 'successful execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_interface = double(Aws::EC2::Types::NetworkInterface)
      allow(ec2_mock_interface).to receive(:is_a?).and_return(Aws::EC2::Types::NetworkInterface)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(AwsHelper).to receive(:ec2_detach_network_interfaces).and_return(['eni-12345678'])
      allow(ec2_mock_client).to receive(:delete_network_interface)
      expect {
        AwsHelper.ec2_delete_network_interfaces([ec2_mock_interface])
      }.not_to raise_exception
    end

    it 'fails with ArgumentError' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_interface = double(Aws::EC2::Types::NetworkInterface)
      expect {
        AwsHelper.ec2_delete_network_interfaces([ec2_mock_interface])
      }.to raise_exception(ArgumentError)
    end

    it 'fails with - Unable to delete network interface' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_interface = double(Aws::EC2::Types::NetworkInterface)
      allow(ec2_mock_interface).to receive(:is_a?).and_return(Aws::EC2::Types::NetworkInterface)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(AwsHelper).to receive(:ec2_detach_network_interfaces).and_return(['eni-12345678'])
      allow(ec2_mock_client).to receive(:delete_network_interface).and_raise(RuntimeError)
      expect {
        AwsHelper.ec2_delete_network_interfaces([ec2_mock_interface])
      }.to raise_exception /Unable to delete network interface/
    end
  end

  context 'ec2_get_subnets' do
    it 'successful execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_subnet = double(Object)
      ec2_mock_tag = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_subnets).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:subnets).and_return([ec2_mock_subnet])
      allow(ec2_mock_subnet).to receive(:tags).and_return([ec2_mock_tag])
      allow(ec2_mock_tag).to receive(:key).and_return('Name')
      allow(ec2_mock_tag).to receive(:value).and_return('dummy')
      allow(ec2_mock_subnet).to receive(:subnet_id).and_return('subnet-12345678')
      allow(ec2_mock_subnet).to receive(:availability_zone).and_return('ap-southeast-2a')
      allow(ec2_mock_subnet).to receive(:available_ip_address_count).and_return(100)
      expect(AwsHelper.ec2_get_subnets(vpc_id: 'vpc-12345678'))
        .to eq({
          "dummy" => {
            :id => "subnet-12345678",
            :availability_zone => "ap-southeast-2a",
            :available_ips => 100
          }
        })
    end

    it 'successful execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_subnet = double(Object)
      ec2_mock_tag = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_subnets).and_raise(RuntimeError)
      expect {
        AwsHelper.ec2_get_subnets(vpc_id: 'vpc-12345678')
      }.to raise_exception /Failed to retrieve subnets \(VPC id = vpc-12345678\)/
    end
  end

  context 'ec2_get_availability_zones' do
    it 'successful execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_mock_az = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_availability_zones).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:availability_zones).and_return([ec2_mock_az])
      allow(ec2_mock_az).to receive(:zone_name).and_return('ap-southeast-2a')
      expect(AwsHelper.ec2_get_availability_zones).to eq(['ap-southeast-2a'])
    end

    it 'fails with Failed to retrieve availability zones' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_availability_zones).and_raise(RuntimeError)
      expect { AwsHelper.ec2_get_availability_zones }
        .to raise_exception /Failed to retrieve availability zones/
    end
  end

  context '_ip_permissions_to_hash_array' do
    it 'successful execution - ip ranges' do
      ec2_ip_permission = double(Object)
      allow(ec2_ip_permission).to receive(:ip_protocol)
      allow(ec2_ip_permission).to receive(:from_port)
      allow(ec2_ip_permission).to receive(:to_port)
      allow(ec2_ip_permission).to receive(:ip_ranges).and_return(['dummy-ip-range'])
      expect {
        AwsHelper._ip_permissions_to_hash_array [ec2_ip_permission]
      }.not_to raise_exception
    end

    it 'successful execution - ip ranges' do
      ec2_ip_permission = double(Object)
      allow(ec2_ip_permission).to receive(:ip_protocol)
      allow(ec2_ip_permission).to receive(:from_port)
      allow(ec2_ip_permission).to receive(:to_port)
      allow(ec2_ip_permission).to receive(:ip_ranges).and_return([])
      allow(ec2_ip_permission).to receive(:prefix_list_ids).and_return(['dummy-prefix-ds'])
      allow(ec2_ip_permission).to receive(:user_id_group_pairs).and_return([])
      expect {
        AwsHelper._ip_permissions_to_hash_array [ec2_ip_permission]
      }.not_to raise_exception
    end

    it 'successful execution - ip ranges' do
      ec2_ip_permission = double(Object)
      allow(ec2_ip_permission).to receive(:ip_protocol)
      allow(ec2_ip_permission).to receive(:from_port)
      allow(ec2_ip_permission).to receive(:to_port)
      allow(ec2_ip_permission).to receive(:ip_ranges).and_return([])
      allow(ec2_ip_permission).to receive(:prefix_list_ids).and_return([])
      allow(ec2_ip_permission).to receive(:user_id_group_pairs).and_return(['dummy-ip-group-pairs'])
      expect {
        AwsHelper._ip_permissions_to_hash_array [ec2_ip_permission]
      }.not_to raise_exception
    end

    it 'successful execution - default' do
      ec2_ip_permission = double(Object)
      allow(ec2_ip_permission).to receive(:ip_protocol)
      allow(ec2_ip_permission).to receive(:from_port)
      allow(ec2_ip_permission).to receive(:to_port)
      allow(ec2_ip_permission).to receive(:ip_ranges).and_return([])
      allow(ec2_ip_permission).to receive(:prefix_list_ids).and_return([])
      allow(ec2_ip_permission).to receive(:user_id_group_pairs).and_return([])
      expect {
        AwsHelper._ip_permissions_to_hash_array [ec2_ip_permission]
      }.not_to raise_exception
    end
  end

  context 'ec2_clear_security_group_rules' do
    it 'successful execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_security_group = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_security_groups).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:security_groups).and_return([ec2_security_group])
      allow(ec2_security_group).to receive(:group_id).and_return('sg-12345678')
      allow(ec2_security_group).to receive(:ip_permissions).and_return(['dummy-ip-permissions'])
      allow(ec2_mock_client).to receive(:revoke_security_group_ingress)
      allow(AwsHelper).to receive(:_ip_permissions_to_hash_array)
      allow(ec2_security_group).to receive(:ip_permissions_egress).and_return(['dummy-ip-permissions-egress'])
      allow(ec2_mock_client).to receive(:revoke_security_group_egress)
      allow(AwsHelper).to receive(:_ip_permissions_to_hash_array)
      expect {
        AwsHelper.ec2_clear_security_group_rules(['sg-12345678'])
      }.not_to raise_exception
    end

    it 'fails gracefully on InvalidGroupNotFound execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_security_groups).and_raise(Aws::EC2::Errors::InvalidGroupNotFound.new(nil, nil))
      expect {
        AwsHelper.ec2_clear_security_group_rules(['sg-12345678'])
      }.not_to raise_exception
    end

    it 'fails with Failed to clear security group rules' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_security_groups).and_raise(RuntimeError)
      expect {
        AwsHelper.ec2_clear_security_group_rules(['sg-12345678'])
      }.to raise_exception /Failed to clear security group rules/
    end

    it 'fails with execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      ec2_mock_response = double(Object)
      ec2_security_group = double(Object)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:describe_security_groups).and_return(ec2_mock_response)
      allow(ec2_mock_response).to receive(:security_groups).and_return([ec2_security_group])
      allow(ec2_security_group).to receive(:group_id).and_return('sg-12345678')
      expect {
        AwsHelper.ec2_clear_security_group_rules(['sg-02345678'])
      }.to raise_exception /describe_security_groups returned security group "sg-12345678" which is NOT in the requested list \["sg-02345678"\]/
    end
  end

  context 'ec2_detach_volume' do
    it 'successful execution' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:detach_volume)
      expect {
        AwsHelper.ec2_detach_volume('vol-12345678')
      }.not_to raise_exception
    end

    it 'fails with Failed to detach volume' do
      ec2_mock_client = double(Aws::EC2::Client)
      allow(AwsHelper).to receive(:_ec2_client).and_return(ec2_mock_client)
      allow(ec2_mock_client).to receive(:detach_volume).and_raise(RuntimeError)
      expect {
        AwsHelper.ec2_detach_volume('vol-12345678')
      }.to raise_exception /Failed to detach volume/
    end

    it 'fails with ArgumentError' do
      expect { AwsHelper.ec2_detach_volume() }.to raise_exception(ArgumentError)
    end
  end

  context 'ec2_copy_volume_snapshot'  do
    it 'test ec2_copy_volume_snapshot ' do
      client = double(Aws::EC2::Client)
      copySnapshotResponse = double(Aws::EC2::Types::CopySnapshotResult, :snapshot_id => "snapshot-12345")

      allow(@dummy_class).to receive(:_ec2_client).and_return(client)
      allow(client).to receive(:copy_snapshot).and_return(copySnapshotResponse)

      expect(
        @dummy_class.ec2_copy_volume_snapshot(
          source_snapshot_id: "snapshot-123",
          kms_key_id: @kms_key_id
        )
      ).to eq("snapshot-12345")
    end

    it 'fails with Failed to create copy volume snapshot' do
      client = double(Aws::EC2::Client)
      allow(@dummy_class).to receive(:_ec2_client).and_return(client)
      allow(client).to receive(:copy_snapshot).and_raise(RuntimeError)

      expect {
        @dummy_class.ec2_copy_volume_snapshot(
          source_snapshot_id: "snapshot-123",
          kms_key_id: @kms_key_id
        )
      }.to raise_exception(RuntimeError, /Failed to create copy of the volume snapshot snapshot-123/)
    end
  end

  context 'ec2_wait_for_volume_snapshot'  do
    it 'test ec2_wait_for_volume_snapshot ' do
      ec2_mock_client = double(Aws::EC2::Client)

      allow(@dummy_class).to receive(:_ec2_client).and_return(ec2_mock_client)
      ec2_mock_waiter = double(Object)
      allow(ec2_mock_waiter).to receive(:max_attempts=)
      allow(ec2_mock_waiter).to receive(:delay=)
      allow(ec2_mock_client).to receive(:wait_until) { |&block| block.call(ec2_mock_waiter) }

      expect {
        @dummy_class.ec2_wait_for_volume_snapshot(
          snapshot_id: 'dummy-snap',
          max_attempts: 5,
          delay: 30
        )
      }.not_to raise_exception
    end

    it 'fails ec2_wait_for_volume_snapshot with Aws::Waiters::Errors::TooManyAttemptsError' do
      ec2_mock_client = double(Aws::EC2::Client)

      allow(@dummy_class).to receive(:_ec2_client).and_return(ec2_mock_client)
      ec2_mock_waiter = double(Object)
      allow(ec2_mock_waiter).to receive(:max_attempts=)
      allow(ec2_mock_waiter).to receive(:delay=)
      allow(ec2_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::TooManyAttemptsError.new(1))

      expect {
        @dummy_class.ec2_wait_for_volume_snapshot(
          snapshot_id: 'dummy-snap',
          max_attempts: 5,
          delay: 30
        )
      }.to raise_exception(ActionError, /Unable to create a copy snapshot /)
    end

    it 'fails ec2_wait_for_volume_snapshot with Aws::Waiters::Errors::WaiterFailed ' do
      ec2_mock_client = double(Aws::EC2::Client)

      allow(@dummy_class).to receive(:_ec2_client).and_return(ec2_mock_client)
      ec2_mock_waiter = double(Object)
      allow(ec2_mock_waiter).to receive(:max_attempts=)
      allow(ec2_mock_waiter).to receive(:delay=)
      allow(ec2_mock_client).to receive(:wait_until).and_raise(Aws::Waiters::Errors::WaiterFailed)

      expect {
        @dummy_class.ec2_wait_for_volume_snapshot(
          snapshot_id: 'dummy-snap',
          max_attempts: 5,
          delay: 30
        )
      }.to raise_exception(ActionError, /Unable to create a copy snapshot /)
    end
  end

  context 'ec2_describe_volume_snapshot_attributes' do
    it 'test rds_describe_cluster_snapshot_attributes snapshot' do
      client = double(Aws::EC2::Client)
      volume_snapshot_result = double(Aws::EC2::Types::DescribeSnapshotsResult)
      volume_snapshots_array = [
        double(Aws::EC2::Types::Snapshot),
        double(Aws::EC2::Types::Snapshot)
      ]

      allow(@dummy_class).to receive(:_ec2_client).and_return(client)
      allow(client).to receive(:describe_snapshots).and_return(volume_snapshot_result)

      allow(volume_snapshot_result).to receive(:snapshots).and_return(volume_snapshots_array)
      expect(
        @dummy_class.ec2_describe_volume_snapshot_attributes(snapshot_id: "snapshot-12345")
      )
        .to eq(volume_snapshots_array[0])
    end

    it 'fails rds_describe_cluster_snapshot_attributes snapshot' do
      client = double(Aws::EC2::Client)

      allow(@dummy_class).to receive(:_ec2_client).and_return(client)
      allow(client).to receive(:describe_snapshots).and_raise(RuntimeError)
      expect {
        @dummy_class.ec2_describe_volume_snapshot_attributes(snapshot_id: "snapshot-12345")
      }.to raise_exception /ERROR: Failed to Describe EC2 volume snapshot/
    end
  end

  context 'validate_ebs_snapshot_id' do
    it 'throws expection if kms key arn are not exist' do
      mock_tag_ams = double(Object)
      allow(mock_tag_ams).to receive(:key).and_return('AMSID')
      allow(mock_tag_ams).to receive(:value).and_return('AMS01')
      mock_tag_qda = double(Object)
      allow(mock_tag_qda).to receive(:key).and_return('EnterpriseAppID')
      allow(mock_tag_qda).to receive(:value).and_return('C031')
      mock_tag_as = double(Object)
      allow(mock_tag_as).to receive(:key).and_return('ApplicationServiceID')
      allow(mock_tag_as).to receive(:value).and_return('99')
      mock_tag_ase = double(Object)
      allow(mock_tag_ase).to receive(:key).and_return('Environment')
      allow(mock_tag_ase).to receive(:value).and_return('DEV')
      mock_tag_branch = double(Object)
      allow(mock_tag_branch).to receive(:key).and_return('Branch')
      allow(mock_tag_branch).to receive(:value).and_return('master')

      describe_snapshot_response = double(Aws::EC2::Types::Snapshot, :encrypted => true, :kms_key_id => @kms_key_id)
      allow(@dummy_class).to receive(:ec2_describe_volume_snapshot_attributes).and_return(describe_snapshot_response)

      allow(describe_snapshot_response).to receive(:tags).and_return(
        [mock_tag_ams, mock_tag_qda, mock_tag_as, mock_tag_ase, mock_tag_branch]
      )

      sections = { ams: 'ams01', qda: 'c031', as: '99', branch: 'master', ase: 'dev', build: '05' }
      expect {
        @dummy_class.ec2_validate_or_copy_snapshot(
          snapshot_id: "snapshot-12345",
          component_name: "Test-Component",
          sections: sections,
        )
      }.to raise_error(RuntimeError, /KMS key for application service/)
    end

    it 'return the same snapshot id if ebs snapshot is encrypted and with same cmk key ' do
      mock_tag_ams = double(Object)
      allow(mock_tag_ams).to receive(:key).and_return('AMSID')
      allow(mock_tag_ams).to receive(:value).and_return('AMS01')
      mock_tag_qda = double(Object)
      allow(mock_tag_qda).to receive(:key).and_return('EnterpriseAppID')
      allow(mock_tag_qda).to receive(:value).and_return('C031')
      mock_tag_as = double(Object)
      allow(mock_tag_as).to receive(:key).and_return('ApplicationServiceID')
      allow(mock_tag_as).to receive(:value).and_return('99')
      mock_tag_ase = double(Object)
      allow(mock_tag_ase).to receive(:key).and_return('Environment')
      allow(mock_tag_ase).to receive(:value).and_return('DEV')
      mock_tag_branch = double(Object)
      allow(mock_tag_branch).to receive(:key).and_return('Branch')
      allow(mock_tag_branch).to receive(:value).and_return('master')

      client = double(Aws::EC2::Client)
      describe_snapshot_response = double(Aws::EC2::Types::Snapshot, :encrypted => true, :kms_key_id => @kms_key_id)
      allow(@dummy_class).to receive(:_ec2_client).and_return(client)

      allow(@dummy_class).to receive(:ec2_describe_volume_snapshot_attributes).and_return(describe_snapshot_response)
      allow(describe_snapshot_response).to receive(:tags).and_return(
        [mock_tag_ams, mock_tag_qda, mock_tag_as, mock_tag_ase, mock_tag_branch]
      )
      sections = { ams: 'ams01', qda: 'c031', as: '99', branch: 'master', ase: 'dev', build: '05' }
      expect(
        @dummy_class.ec2_validate_or_copy_snapshot(
          snapshot_id: "snapshot-12345",
          component_name: "Test-Component",
          sections: sections,
          cmk_arn: @kms_key_id
        )
      ).to eq("snapshot-12345")
    end

    it 'return the copysnapshot id if the snapshot is unecrypted' do
      mock_tag_ams = double(Object)
      allow(mock_tag_ams).to receive(:key).and_return('AMSID')
      allow(mock_tag_ams).to receive(:value).and_return('AMS01')
      mock_tag_qda = double(Object)
      allow(mock_tag_qda).to receive(:key).and_return('EnterpriseAppID')
      allow(mock_tag_qda).to receive(:value).and_return('C031')
      mock_tag_as = double(Object)
      allow(mock_tag_as).to receive(:key).and_return('ApplicationServiceID')
      allow(mock_tag_as).to receive(:value).and_return('99')
      mock_tag_ase = double(Object)
      allow(mock_tag_ase).to receive(:key).and_return('Environment')
      allow(mock_tag_ase).to receive(:value).and_return('DEV')
      mock_tag_branch = double(Object)
      allow(mock_tag_branch).to receive(:key).and_return('Branch')
      allow(mock_tag_branch).to receive(:value).and_return('master')

      client = double(Aws::EC2::Client)
      describe_snapshot_response = double(Aws::EC2::Types::Snapshot, :encrypted => false)
      allow(@dummy_class).to receive(:_ec2_client).and_return(client)
      allow(Context).to receive_message_chain("kms.secrets_key_arn").and_return(@kms_key_id)
      allow(@dummy_class).to receive(:ec2_describe_volume_snapshot_attributes).and_return(describe_snapshot_response)
      allow(@dummy_class).to receive(:ec2_copy_volume_snapshot).and_return("snapshot-54321")
      allow(@dummy_class).to receive(:ec2_wait_for_volume_snapshot).and_return(true)
      allow(describe_snapshot_response).to receive(:tags).and_return(
        [mock_tag_ams, mock_tag_qda, mock_tag_as, mock_tag_ase, mock_tag_branch]
      )
      sections = { ams: 'ams01', qda: 'c031', as: '99', branch: 'master', ase: 'dev', build: '05' }
      expect(
        @dummy_class.ec2_validate_or_copy_snapshot(
          snapshot_id: "snapshot-12345",
          component_name: "Test-Component",
          sections: sections,
          cmk_arn: 'dummy-kms-key'
        )
      ).to eq("snapshot-54321")
    end

    it 'return the copysnapshot id if the snapshot is encrypted with different kms key' do
      mock_tag_ams = double(Object)
      allow(mock_tag_ams).to receive(:key).and_return('AMSID')
      allow(mock_tag_ams).to receive(:value).and_return('AMS01')
      mock_tag_qda = double(Object)
      allow(mock_tag_qda).to receive(:key).and_return('EnterpriseAppID')
      allow(mock_tag_qda).to receive(:value).and_return('C031')
      mock_tag_as = double(Object)
      allow(mock_tag_as).to receive(:key).and_return('ApplicationServiceID')
      allow(mock_tag_as).to receive(:value).and_return('99')
      mock_tag_ase = double(Object)
      allow(mock_tag_ase).to receive(:key).and_return('Environment')
      allow(mock_tag_ase).to receive(:value).and_return('DEV')
      mock_tag_branch = double(Object)
      allow(mock_tag_branch).to receive(:key).and_return('Branch')
      allow(mock_tag_branch).to receive(:value).and_return('master')
      client = double(Aws::EC2::Client)
      describe_snapshot_response = double(Aws::EC2::Types::Snapshot, :encrypted => false, :kms_key_id => "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-12")

      allow(@dummy_class).to receive(:_ec2_client).and_return(client)
      allow(Context).to receive_message_chain("kms.secrets_key_arn").and_return(@kms_key_id)
      allow(@dummy_class).to receive(:ec2_describe_volume_snapshot_attributes).and_return(describe_snapshot_response)
      allow(@dummy_class).to receive(:ec2_copy_volume_snapshot).and_return("snapshot-54321")
      allow(@dummy_class).to receive(:ec2_wait_for_volume_snapshot).and_return(true)
      allow(describe_snapshot_response).to receive(:tags).and_return(
        [mock_tag_ams, mock_tag_qda, mock_tag_as, mock_tag_ase, mock_tag_branch]
      )
      sections = { ams: 'ams01', qda: 'c031', as: '99', branch: 'master', ase: 'dev', build: '05' }
      expect(
        @dummy_class.ec2_validate_or_copy_snapshot(
          snapshot_id: "snapshot-12345",
          component_name: "Test-Component",
          sections: sections,
          cmk_arn: 'dummy-kms-key'
        )
      ).to eq("snapshot-54321")
    end

    it 'throws expection if snapshot does not belongs to current app id' do
      mock_tag_ams = double(Object)
      allow(mock_tag_ams).to receive(:key).and_return('AMSID')
      allow(mock_tag_ams).to receive(:value).and_return('AMS01')
      mock_tag_qda = double(Object)
      allow(mock_tag_qda).to receive(:key).and_return('EnterpriseAppID')
      allow(mock_tag_qda).to receive(:value).and_return('C036')
      mock_tag_as = double(Object)
      allow(mock_tag_as).to receive(:key).and_return('ApplicationServiceID')
      allow(mock_tag_as).to receive(:value).and_return('99')
      mock_tag_ase = double(Object)
      allow(mock_tag_ase).to receive(:key).and_return('Environment')
      allow(mock_tag_ase).to receive(:value).and_return('DEV')
      mock_tag_branch = double(Object)
      allow(mock_tag_branch).to receive(:key).and_return('Branch')
      allow(mock_tag_branch).to receive(:value).and_return('master')

      describe_snapshot_response = double(Aws::EC2::Types::Snapshot, :encrypted => true, :kms_key_id => @kms_key_id)
      allow(@dummy_class).to receive(:ec2_describe_volume_snapshot_attributes).and_return(describe_snapshot_response)

      allow(describe_snapshot_response).to receive(:tags).and_return(
        [mock_tag_ams, mock_tag_qda, mock_tag_as, mock_tag_ase, mock_tag_branch]
      )

      sections = { ams: 'ams01', qda: 'c031', as: '99', branch: 'master', ase: 'dev', build: '05' }
      expect {
        @dummy_class.ec2_validate_or_copy_snapshot(
          snapshot_id: "snapshot-12345",
          component_name: "Test-Component",
          sections: sections,
        )
      }.to raise_error(RuntimeError, /The Snapshot ID "snapshot-12345" does not belong to the current Application Service ID/)
    end
  end

  context 'ec2_latest_snapshot'  do
    it 'returns latest snapshot' do
      client = double(Aws::EC2::Client)
      tag = double(Aws::EC2::Types::Tag)

      volume_snapshot_result = double(Aws::EC2::Types::DescribeSnapshotsResult)
      volume_snapshot1 = double(Aws::EC2::Types::Snapshot)
      volume_snapshot2 = double(Aws::EC2::Types::Snapshot)
      volume_snapshot3 = double(Aws::EC2::Types::Snapshot)
      volume_snapshots_array = [volume_snapshot1, volume_snapshot2]
      volume_snapshots_array2 = [volume_snapshot3]

      allow(volume_snapshot1).to receive(:snapshot_id).and_return("Snapshot1")
      allow(volume_snapshot2).to receive(:snapshot_id).and_return("Snapshot2")
      allow(volume_snapshot3).to receive(:snapshot_id).and_return("Snapshot3")

      allow(volume_snapshot1).to receive(:start_time).and_return(Time.parse("2013-05-31 00:00").utc.iso8601)
      allow(volume_snapshot2).to receive(:start_time).and_return(Time.parse("2016-05-31 00:00").utc.iso8601)
      allow(volume_snapshot3).to receive(:start_time).and_return(Time.parse("2017-05-31 00:00").utc.iso8601)

      allow(volume_snapshot1).to receive(:tags).and_return([tag, tag, tag, tag, tag, tag])
      allow(volume_snapshot2).to receive(:tags).and_return([tag, tag, tag, tag, tag, tag])
      allow(volume_snapshot3).to receive(:tags).and_return([tag, tag, tag, tag, tag, tag])

      allow(@dummy_class).to receive(:_ec2_client).and_return(client)
      allow(client).to receive(:describe_snapshots).and_return(volume_snapshot_result)
      allow(volume_snapshot_result).to receive(:snapshots).and_return(volume_snapshots_array, volume_snapshots_array2)
      allow(volume_snapshot_result).to receive(:next_token).and_return("has_more", "")
      allow(tag).to receive(:key).and_return('Name', 'Name', 'Name')
      allow(tag).to receive(:value) .and_return("dummy-volume", "dummy-volume", "dummy-volume")

      expect(@dummy_class.ec2_latest_snapshot(volume_name: "dummy-volume")).to eq "Snapshot3"
    end

    it 'fails latest snapshot' do
      client = double(Aws::EC2::Client)
      tag = double(Aws::EC2::Types::Tag)

      volume_snapshot_result = double(Aws::EC2::Types::DescribeSnapshotsResult)
      allow(@dummy_class).to receive(:_ec2_client).and_return(client)
      allow(client).to receive(:describe_snapshots).and_return(volume_snapshot_result)
      allow(volume_snapshot_result).to receive(:next_token).and_return(nil)
      allow(volume_snapshot_result).to receive(:snapshots).and_return({})

      expect(@dummy_class.ec2_latest_snapshot(volume_name: "dummy-volume")).to eq nil
    end
  end
end
