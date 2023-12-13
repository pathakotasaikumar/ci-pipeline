$LOAD_PATH.unshift("#{BASE_DIR}/lib/consumables/aws/builders")
require 'codedeploy_deploymentgroup_builder'

describe 'AwsCodeDeployDeploymentGroupBuilder' do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(AwsCodeDeployDeploymentGroupBuilder)
  end

  context '._create_autoscale_target' do
    it 'raises on empty autoscaling_group_names' do
      expect {
        @dummy_class.__send__(
          :_create_autoscale_target,
          :autoscaling_group_names => nil
        )
      }.to raise_error(/AutoScale Group names are nil or empty/)

      expect {
        @dummy_class.__send__(
          :_create_autoscale_target,
          :autoscaling_group_names => []
        )
      }.to raise_error(/AutoScale Group names are nil or empty/)
    end

    it 'returns autoscaling_group_names' do
      result = nil

      expect {
        result = @dummy_class.__send__(
          :_create_autoscale_target,
          :autoscaling_group_names => ['name1', 'name2']
        )
      }.not_to raise_error

      expect(result).to eq(['name1', 'name2'])
    end
  end
end
