require "util/json_tools"
require "util/generate_password"
require "consumable"
require "consumables/aws/aws_rds"

require_relative "aws_rds_aurora"

class AwsRdsAuroraPostgre < AwsRdsAurora
  def initialize(component_name, component)
    super(component_name, component, 'aurora-postgresql')
  end
end
