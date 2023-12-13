module DbClusterParameterGroupBuilder
  def _process_db_cluster_parameter_group(template: nil, db_cluster_parameter_group: nil)
    db_cluster_parameter_group.each do |name, definition|
      template['Resources'][name] = {
        'Type' => 'AWS::RDS::DBClusterParameterGroup',
        'DeletionPolicy' => JsonTools.get(definition, 'DeletionPolicy', 'Delete'),
        'Properties' => {
          'Description' => JsonTools.get(definition, 'Properties.Description', 'Custom Parameter Group'),
          'Family' => JsonTools.get(definition, 'Properties.Family'),
        }
      }

      JsonTools.transfer(definition, 'Properties.Parameters', template['Resources'][name])

      template['Outputs'][name] = {
        'Description' => 'Customer Cluster Parameter Group',
        'Value' => { 'Ref' => name },
      }
    end
  end
end
