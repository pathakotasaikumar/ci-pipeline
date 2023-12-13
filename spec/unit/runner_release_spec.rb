$LOAD_PATH.unshift("#{BASE_DIR}/lib")
require 'runner'

RSpec.describe Runner do
  before(:context) do
    payload_dir = "#{TEST_DATA_DIR}/ciw-4/app/platform"

    components = Component.load_all(payload_dir, Defaults.sections[:ase].upcase)
    @consumables = Consumable.instantiate_all(components)

    Context.component.set_variables("volume", { "MyVolumeId" => "vol-123456789" })
    Context.component.set_variables("rds", { "MySQLMinimalArn" => "arn:aws:rds:ap-southeast-2:1234567890:db:abcdef1234" })
    Context.component.set_variables("autoheal", {
      "AutoScalingGroupName" => "ams01-c031-98-dev-master-10-autoscale-AutoScalingGroup-1WTD3L9X8SYQ0"
    })

    @consumables.each do |name, consumable|
      Context.component.set_variables(name, consumable.dns_records)
    end
  end

  context "release" do
    # it 'runs actions for stage PreRelease' do
    #  expect(Log).to receive(:info).with(/"There are currently no released builds. Will not run SetDesiredCapacity command"/)
    #  expect(Log).to receive(:info).with(/"[PreRelease] : Executing action SetDesiredCapacity [\"autoheal\"]"/)
    #  Runner.run_actions(@consumables, "PreRelease")
    # end

    # it 'runs release' do
    #  Runner.release(@consumables)
    # end
  end
end # RSpec.describe
