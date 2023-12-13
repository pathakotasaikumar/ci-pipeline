$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib"))
require 'component_validator'

RSpec.describe ComponentValidator do
  before(:context) do
    @component_validator = ComponentValidator.new(
      "#{BASE_DIR}/lib/validation_specs/cloudformation",
      "#{BASE_DIR}/lib/validation_specs/component"
    )
  end

  context '.initialize' do
    it 'initialize without error' do
      ComponentValidator.new(
        "#{BASE_DIR}/lib/validation_specs/cloudformation",
        "#{BASE_DIR}/lib/validation_specs/component"
      )
    end
  end

  context '.reset' do
    it 'reset the warning and error' do
      @component_validator._save_error 'testing error'
      @component_validator._save_warning 'testing warning'
      @component_validator.reset
      expect(@component_validator.errors).to be_empty
      expect(@component_validator.warnings).to be_empty
      expect(@component_validator.last_errors).not_to be_empty
      expect(@component_validator.last_warnings).not_to be_empty
    end
  end
  context '_load_spec_file' do
    it 'invalid _load_spec_file for component' do
      expect { @component_validator._load_spec_file("#{BASE_DIR}/lib/validation_specs/cloudformation/test.xml") }.to raise_error(/Unknown file type for spec file/)
    end
  end
  context '._validate_resource_cardinality' do
    it '_validate_resource_cardinality success scenario for aws/instance' do
      expect(@component_validator).not_to receive(:_save_error)
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_instance_spec.yaml"))['UnitTest']
      spec_resource_map = @test_data['CardinalityTest']['Valid']
      component_spec = @component_validator._load_component_spec('aws/instance')
      @component_validator._validate_resource_cardinality(component_spec, spec_resource_map)
    end

    it '_validate_resource_cardinality failure scenario aws/instance' do
      expect(@component_validator).to receive(:_save_error).at_least(:once)
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_instance_spec.yaml"))['UnitTest']
      spec_resource_map = @test_data['CardinalityTest']['Invalid']
      component_spec = @component_validator._load_component_spec('aws/instance')
      @component_validator._validate_resource_cardinality(component_spec, spec_resource_map)
    end

    it '_validate_resource_cardinality success scenario for aws/autoscale' do
      expect(@component_validator).not_to receive(:_save_error)
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_autoscale_spec.yaml"))['UnitTest']
      spec_resource_map = @test_data['CardinalityTest']['Valid']
      component_spec = @component_validator._load_component_spec('aws/autoscale')
      @component_validator._validate_resource_cardinality(component_spec, spec_resource_map)
    end

    it '_validate_resource_cardinality failure scenario aws/autoscale' do
      expect(@component_validator).to receive(:_save_error).at_least(:once)
      @autoscale_test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_autoscale_spec.yaml"))['UnitTest']
      autoscale_spec_resource_map = @autoscale_test_data['CardinalityTest']['Invalid']
      autoscale_component_spec = @component_validator._load_component_spec('aws/autoscale')
      @component_validator._validate_resource_cardinality(autoscale_component_spec, autoscale_spec_resource_map)
    end
  end

  context '.validate' do
    it 'validate method success scenario for instance' do
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_instance_spec.yaml"))['UnitTest']
      component_definition = @test_data['ValidateMethod']['Valid']
      @component_validator.validate('test-instance', component_definition)
      expect(@component_validator.errors).to be_empty
    end

    it 'validate method success scenario for aws_autoscale' do
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_autoscale_spec.yaml"))['UnitTest']
      component_definition = @test_data['PolicyTest']['Valid']
      @component_validator.validate('test-instance', component_definition)
      expect(@component_validator.errors).to be_empty
    end

    it 'validate method success scenario for aws_autoheal' do
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_autoheal_spec.yaml"))['UnitTest']
      component_definition = @test_data['PolicyTest']['Valid']
      @component_validator.validate('test-instance', component_definition)
      expect(@component_validator.errors).to be_empty
    end
    it 'validate method success scenario for aws_rds_aurora_postgresql' do
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_rds_aurora_postgresql_spec.yaml"))['UnitTest']
      component_definition = @test_data['PolicyTest']['Valid']
      @component_validator.validate('test-instance', component_definition)
      expect(@component_validator.errors).to be_empty
    end
    it 'validate method success scenario for aws_rds_aurora' do
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_rds_aurora_spec.yaml"))['UnitTest']
      component_definition = @test_data['PolicyTest']['Valid']
      @component_validator.validate('test-instance', component_definition)
      expect(@component_validator.errors).to be_empty
    end
    it 'validate method success scenario for aws_rds_mysql' do
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_rds_mysql_spec.yaml"))['UnitTest']
      component_definition = @test_data['PolicyTest']['Valid']
      @component_validator.validate('test-instance', component_definition)
      expect(@component_validator.errors).to be_empty
    end
    it 'validate method success scenario for aws_rds_oracle' do
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_rds_oracle_spec.yaml"))['UnitTest']
      component_definition = @test_data['PolicyTest']['Valid']
      @component_validator.validate('test-instance', component_definition)
      expect(@component_validator.errors).to be_empty
    end
    it 'validate method success scenario for aws_rds_postgresql' do
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_rds_postgresql_spec.yaml"))['UnitTest']
      component_definition = @test_data['PolicyTest']['Valid']
      @component_validator.validate('test-instance', component_definition)
      expect(@component_validator.errors).to be_empty
    end
    it 'validate method success scenario for aws_rds_sqlserver' do
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_rds_sqlserver_spec.yaml"))['UnitTest']
      component_definition = @test_data['PolicyTest']['Valid']
      @component_validator.validate('test-instance', component_definition)
      expect(@component_validator.errors).to be_empty
    end
    it 'validate method success scenario for aws_volume' do
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_volume_spec.yaml"))['UnitTest']
      component_definition = @test_data['PolicyTest']['Valid']
      @component_validator.validate('test-instance', component_definition)
      expect(@component_validator.errors).to be_empty
    end

    it 'validate failure scenario' do
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_rds_mysql_spec.yaml"))['UnitTest']
      component_definition = @test_data['ValidateMethod']['Invalid']
      @component_validator.validate('test-instance', component_definition)
      expect(@component_validator.errors).not_to be_empty
    end
  end

  context '._validate_top_level_properties' do
    it '_validate_top_level_properties capture errors' do
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_instance_spec.yaml"))['UnitTest']
      component_definition = @test_data['TopLevelPropertyMethod']['Invalid']
      @component_validator._validate_top_level_properties('test-component', component_definition)
      expect(@component_validator.errors).not_to be_empty
    end

    it '_validate_top_level_properties invalid component name and top level property' do
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_instance_spec.yaml"))['UnitTest']
      component_definition = @test_data['TopLevelPropertyMethod']['InvalidType']
      @component_validator._validate_top_level_properties('invalid$-components', component_definition)
      expect(@component_validator.errors).not_to be_empty
    end

    it '_validate_top_level_properties invalid Type parameter' do
      @test_data = YAML.load(File.read("#{TEST_DATA_DIR}/component_validation_spec_files/aws_instance_spec.yaml"))['UnitTest']
      component_definition = @test_data['TopLevelPropertyMethod']['Invalid']
      @component_validator._validate_top_level_properties('invalid$-components', component_definition)
      expect(@component_validator.errors).not_to be_empty
    end
  end

  context '._validate_primitive_type' do
    it 'testing non primitive type' do
      property_spec = { 'Required' => false, 'Configurable' => true }
      expect(@component_validator).to receive(:_save_warning).with("Skipping validation of property \"Database.Properties.DBName\" - not a primitive type")
      expect(@component_validator._validate_primitive_type('Database.Properties.DBName', property_spec, 'test')).to be_truthy
    end
    it 'testing bad regex value' do
      property_spec = { 'PrimitiveType' => 'String', 'Regex' => '^@?[a-zA-Z]', 'Required' => true }
      expect(@component_validator).to receive(:_save_error).with("Bad value for property \"Database.Properties.DBName\" - must match regex ^@?[a-zA-Z]")
      expect(@component_validator._validate_primitive_type('Database.Properties.DBName', property_spec, '1234567')).to be_falsey
    end
    it 'testing regex validation with valid value @nonp for Target' do
      property_spec = { 'PrimitiveType' => 'String', 'Regex' => '^@origin|@dr|@nonp|@ams[0-9]{2}-(origin|dr([0-9])?)-(prod|nonp|dev)$' }
      expect(@component_validator._validate_primitive_type('BackupPolicy.Properties.Target', property_spec, '@nonp')).to be_truthy
    end

    it 'testing regex validation with valid value @dr for Target' do
      property_spec = { 'PrimitiveType' => 'String', 'Regex' => '^@origin|@dr|@nonp|@ams[0-9]{2}-(origin|dr([0-9])?)-(prod|nonp|dev)$' }
      expect(@component_validator._validate_primitive_type('BackupPolicy.Properties.Target', property_spec, '@dr')).to be_truthy
    end

    it 'testing regex validation with valid value @dr for Copy Target' do
      property_spec = { 'PrimitiveType' => 'String', 'Regex' => '^@origin|@dr|@nonp|@ams[0-9]{2}-(origin|dr([0-9])?)-(prod|nonp|dev)$' }
      expect(@component_validator._validate_primitive_type('BackupPolicy.Properties.CopyTarget.Target', property_spec, '@dr')).to be_truthy
    end

    it 'testing regex validation with valid value @nop for Copy Target' do
      property_spec = { 'PrimitiveType' => 'String', 'Regex' => '^@origin|@dr|@nonp|@ams[0-9]{2}-(origin|dr([0-9])?)-(prod|nonp|dev)$' }
      expect(@component_validator._validate_primitive_type('BackupPolicy.Properties.CopyTarget.Target', property_spec, '@nonp')).to be_truthy
    end

    it 'testing regex validation with invalid value for Target' do
      property_spec = { 'PrimitiveType' => 'String', 'Regex' => '^@origin|@dr|@nonp|@ams[0-9]{2}-(origin|dr([0-9])?)-(prod|nonp|dev)$' }
      expect(@component_validator._validate_primitive_type('BackupPolicy.Properties.Target', property_spec, '@prod')).to be_falsey
    end

    it 'testing regex validation with invalid value for Copy Target' do
      property_spec = { 'PrimitiveType' => 'String', 'Regex' => '^@origin|@dr|@nonp|@ams[0-9]{2}-(origin|dr([0-9])?)-(prod|nonp|dev)$' }
      expect(@component_validator._validate_primitive_type('BackupPolicy.Properties.CopyTarget.Target', property_spec, '@prod')).to be_falsey
    end

    it 'testing bad PrimitiveType = map ' do
      property_spec = { 'PrimitiveType' => 'map', 'Required' => true }
      expect(@component_validator._validate_primitive_type('Database.Properties.DBName', property_spec, 'map')).to be_falsey
    end

    it 'testing good PrimitiveType = integer ' do
      property_spec = { 'PrimitiveType' => 'integer', 'Required' => true }
      expect(@component_validator).not_to receive(:_save_error).with("Bad type for property \"Database.Properties.DBName\" - expecting integer")
      expect(@component_validator._validate_primitive_type('Database.Properties.DBName', property_spec, 123456)).to be_truthy
    end

    it 'testing bad PrimitiveType = integer ' do
      property_spec = { 'PrimitiveType' => 'integer', 'Required' => true }
      expect(@component_validator).to receive(:_save_error).with("Bad type for property \"Database.Properties.DBName\" - expecting integer")
      expect(@component_validator._validate_primitive_type('Database.Properties.DBName', property_spec, 'integer')).to be_falsey
    end

    it 'testing good PrimitiveType = double ' do
      property_spec = { 'PrimitiveType' => 'double', 'Required' => true }
      expect(@component_validator).not_to receive(:_save_error).with("Bad type for property \"Database.Properties.DBName\" - expecting integer")
      expect(@component_validator._validate_primitive_type('Database.Properties.DBName', property_spec, 12345.12)).to be_truthy
    end

    it 'testing bad PrimitiveType = double ' do
      property_spec = { 'PrimitiveType' => 'double', 'Required' => true }
      expect(@component_validator).to receive(:_save_error).with("Bad type for property \"Database.Properties.DBName\" - expecting double")
      expect(@component_validator._validate_primitive_type('Database.Properties.DBName', property_spec, 'double')).to be_falsey
    end

    it 'testing good PrimitiveType = boolean ' do
      property_spec = { 'PrimitiveType' => 'boolean', 'Required' => true }
      expect(@component_validator).not_to receive(:_save_error).with("Bad type for property \"Database.Properties.DBName\" - expecting integer")
      expect(@component_validator._validate_primitive_type('Database.Properties.DBName', property_spec, true)).to be_truthy
    end

    it 'testing bad PrimitiveType = double ' do
      property_spec = { 'PrimitiveType' => 'boolean', 'Required' => true }
      expect(@component_validator).to receive(:_save_error).with("Bad type for property \"Database.Properties.DBName\" - expecting boolean")
      expect(@component_validator._validate_primitive_type('Database.Properties.DBName', property_spec, 'testing')).to be_falsey
    end

    it 'testing unhandled PrimitiveType' do
      property_spec = { 'PrimitiveType' => 'testing', 'Required' => true }
      expect(@component_validator).to receive(:_save_warning).with("Skipping validation of property \"Database.Properties.DBName\" - unhandled property type testing")
      expect(@component_validator._validate_primitive_type('Database.Properties.DBName', property_spec, 'testing')).to be_falsey
    end
  end

  context '.validate components' do
    def _validate_component_dir(component_dir:)
      validator = ComponentValidator.new(
        "#{BASE_DIR}/lib/validation_specs/cloudformation",
        "#{BASE_DIR}/lib/validation_specs/component"
      )

      component_files = Dir[File.join(component_dir, '*.yaml')]
      component_count = component_files.count
      component_index = 1

      if component_count == 0
        raise "Cannot find any components in folder #{component_dir}"
      end

      Log.info "Validating #{component_count} components in folder #{component_dir}"

      expect {
        component_files.each do |component_file|
          Log.debug "[#{component_index}/#{component_count}] validating component: #{component_file}"

          component_name = File.basename(component_file, '.yaml')
          definition = YAML.load_file(component_file)
          validator.validate(component_name, definition)

          success = validator.errors.empty? && validator.warnings.empty?

          validator.errors.each do |msg|
            Log.debug " - ERROR  : #{msg}"
          end

          validator.warnings.each do |msg|
            Log.debug " - WARNING: #{msg}"
          end

          if !success
            error_message = [
              "Failed to validate component #{component_name}",
              "definition: \n #{definition.to_yaml}",
              "errors   : " + validator.errors.join(' '),
              "warnings : " + validator.warnings.join(' ')
            ]

            raise error_message.join("\n")
          end

          component_index = component_index + 1

          validator.reset
        end
      }.not_to raise_error
    end

    it 'validates /platform dir' do
      _validate_component_dir(
        component_dir: "#{BASE_DIR}/platform"
      )
    end

    it 'validates test/data/component_validator dir' do
      _validate_component_dir(
        component_dir: "#{BASE_DIR}/test/data/component_validator"
      )
    end
  end
end
