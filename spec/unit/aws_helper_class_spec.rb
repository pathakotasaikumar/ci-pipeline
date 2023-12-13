$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'time'
require 'aws_helper_class'

RSpec.describe AwsHelperClass do
  before(:context) do
    @aws_helper = AwsHelperClass.new()
    @mock_arn = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
    @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/#{File.basename(__FILE__, ".*")}.yaml"))
  end

  context '.initialize' do
    it 'does something', :skip => true do
      pending
      AwsHelper.initialize(proxy: nil, region: 'ap-southeast-2', control_role: nil, provisioning_role: nil)
      expect { 1 }.eq 1
    end

    it 'initializes retry service' do
      service = @aws_helper.retry_service
      expect(service).not_to be(nil)
    end
  end

  context '.s3_put_object' do
    it 'does something', :skip => true do
      pending
      AwsHelper.s3_put_object(bucket, key, data)
      expect { 1 }.eq 1
    end
  end

  context '.s3_upload_file' do
    it 'does something', :skip => true do
      pending
      AwsHelper.s3_upload_file(bucket, key, file_path)
      expect { 1 }.eq 1
    end
  end

  context '.s3_get_object' do
    it 'does something', :skip => true do
      pending
      AwsHelper.s3_get_object(bucket, key, version = nil)
      expect { 1 }.eq 1
    end
  end

  context '.s3_delete_object' do
    it 'does something', :skip => true do
      pending
      AwsHelper.s3_delete_object(bucket, key, version = nil)
      expect { 1 }.eq 1
    end
  end

  context '.cfn_create_stack' do
    it 'does something', :skip => true do
      pending
      AwsHelper.cfn_create_stack(stack_name: stack_name, template: template_body, tags: tags)
      expect { 1 }.eq 1
    end
  end

  context '.cfn_parameter_list' do
    it 'creates params Array from Hash' do
      test_data = {
        'test_1' => 'test_value_1',
        'test_2' => 'test_value_2'
      }

      result = AwsHelper.cfn_parameter_list(test_data)

      expect(result).to be_a(Array)

      expect(result[0]).to eq({ parameter_key: 'test_1', parameter_value: 'test_value_1' })
      expect(result[1]).to eq({ parameter_key: 'test_2', parameter_value: 'test_value_2' })
    end

    it 'raises on wrong param' do
      expect { AwsHelper.cfn_parameter_list('test') }.to raise_error(/Parameters argument must be a Hash/)
    end
  end

  context '.cfn_update_stack' do
    it 'does something', :skip => true do
      pending
      AwsHelper.cfn_update_stack(stack_name: stack_name, template: template_body)
      expect { 1 }.eq 1
    end
  end

  context '.cfn_stack_exists' do
    it 'does something', :skip => true do
      pending
      AwsHelper.cfn_stack_exists(stack_name)
      expect { 1 }.eq 1
    end
  end

  context '.cfn_get_stack_outputs' do
    it 'does something', :skip => true do
      pending
      AwsHelper.cfn_get_stack_outputs(stack_name)
      expect { 1 }.eq 1
    end
  end

  context '.cfn_delete_stack' do
    it 'does something', :skip => true do
      pending
      AwsHelper.cfn_delete_stack(stack_name)
      expect { 1 }.eq 1
    end
  end

  context '.create_image' do
    it 'does something', :skip => true do
      pending
      AwsHelper.create_image(instance_id)
      expect { 1 }.eq 1
    end
  end

  context '.delete_image' do
    it 'does something', :skip => true do
      pending
      AwsHelper.delete_image(image_id)
      expect { 1 }.eq 1
    end
  end
end # RSpec.describe
