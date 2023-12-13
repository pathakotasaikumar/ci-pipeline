class PipelineMetadataService
  # Function to save release and active build context to dynamodb
  # @param context_path [Hash] target section variables
  # @param context [Hash] context value
  def self.save_metadata(
    context_name:,
    context:
  )

    context_name = _construct_context_path(context_name)
    table_name = Defaults.pipeline_build_metadata_dynamodb_table_name
    begin
      # load the existing the items from dynamodb
      active_build_items = AwsHelper.dynamodb_query(
        table_name: table_name,
        condition: "context_name = :context_name",
        expression_attribute_values: {
          ":context_name" => context_name,
        }
      )

      active_build_items = nil if active_build_items.items.empty?
      if context.nil?
        Log.info "Deleting context from metadata table"
        AwsHelper.delete_item(
          table_name: table_name,
          key: {
            "context_name" => context_name
          }
        ) unless active_build_items.nil?
      else
        if active_build_items.nil?
          AwsHelper.put_item(
            table_name: table_name,
            item: {
              'context_name' => context_name,
              'context' => context,
              'ams_id' => Defaults.sections[:ams].upcase,
              'enterprise_app_id' => Defaults.sections[:qda].upcase,
              'application_service_id' => Defaults.sections[:as].upcase,
              'environment' => Defaults.sections[:ase].upcase,
              'branch' => Defaults.sections[:branch]
            }
          )
        else
          AwsHelper.update_item(
            table_name: table_name,
            key: {
              'context_name' => context_name
            },
            update_expression: 'set context = :context',
            expression_attribute_values: { ':context' => context }
          )
        end
      end
    rescue => e
      raise "Failed to save the context in dynamodb - #{e}"
    end
  end

  # Function to find the load the release context from dynamodb
  # the arguments must be Hash value or can be empty
  # and the format of arguments _load_release_context(build: 3, ams: ams01)
  # @param section_variables [Hash] target section variables
  def self.load_metadata(**section_variables)
    Log.debug "Loading release context from dynamodb"
    context_name = Context.persist.release_path(**section_variables).join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
    released_build_items = AwsHelper.dynamodb_query(
      table_name: Defaults.pipeline_build_metadata_dynamodb_table_name,
      condition: "context_name = :context_name",
      expression_attribute_values: {
        ":context_name" => context_name,
      }
    )
    if released_build_items.items.empty?
      Log.warn 'Unable to find the released build number from the context.'
      return nil
    end
    released_context = released_build_items.items.first['context']
    released_context['ReleasedBuildNumber']
  end

  private

  # Function to construct the Hash value to string
  # @param context_path [Array] variables
  def self._construct_context_path(context_name)
    return context_name.join('-').gsub(/[^a-zA-Z0-9\-]/, '-')
  end
end
