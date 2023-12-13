require 'aws-sdk'

module DynamoDbHelper
  def _dynamodb_helper_init
    @dynamodb_client = nil
    @dynamodb_credentials = nil
  end

  # Function to update the existing dynamodb table
  # @param table_name [String] table name
  # @param item [Hash]
  def put_item(
    table_name:,
    item:
  )
    begin
      params = {}
      params[:table_name] = table_name
      params[:item] = item

      response = _dynamodb_client.put_item(params)

      return response
    rescue => e
      raise "Failed to put an item in dynamodb - #{e}"
    end
  end

  # Function to update the existing dynamodb table
  # @param table_name [String] table name
  # @param key [String]
  def delete_item(
    table_name:,
    key:
  )
    begin
      params = {}
      params[:table_name] = table_name
      params[:key] = key

      response = _dynamodb_client.delete_item(params)

      return response
    rescue => e
      raise "Failed to delete an item in dynamodb - #{e}"
    end
  end

  # Function to update the existing dynamodb table
  # @param table_name [String] table name
  # @param key [String]
  # @param expression_attribute_values [String]
  # @param update_expression [String]
  def update_item(
    table_name: nil,
    key: nil,
    expression_attribute_values: nil,
    update_expression: nil
  )

    begin
      params = {}
      params[:table_name] = table_name
      params[:key] = key
      params[:expression_attribute_values] = expression_attribute_values unless expression_attribute_values.nil?
      params[:update_expression] = update_expression unless update_expression.nil?

      response = _dynamodb_client.update_item(params)

      return response
    rescue => e
      raise "Failed to update an item in dynamodb - #{e}"
    end
  end

  def dynamodb_query(
    table_name: nil, # Table name, required
    index_name: nil,
    select: "ALL_ATTRIBUTES",
    limit: 500,
    consistent_read: false,
    exclusive_start_key: nil,
    condition: nil,
    filter: nil,
    projection: nil,
    expression_attribute_names: nil,
    expression_attribute_values: nil
  )

    params = {}
    params[:table_name] = table_name
    params[:index_name] = index_name unless index_name.nil?
    params[:select] = select
    params[:limit] = limit unless limit.nil?
    params[:consistent_read] = consistent_read
    params[:scan_index_forward] = true
    params[:exclusive_start_key] = exclusive_start_key unless exclusive_start_key.nil?
    params[:projection_expression] = projection unless projection.nil?
    params[:filter_expression] = filter unless filter.nil?
    params[:key_condition_expression] = condition unless condition.nil?
    params[:expression_attribute_names] = expression_attribute_names unless expression_attribute_names.nil?
    params[:expression_attribute_values] = expression_attribute_values unless expression_attribute_values.nil?

    response = _dynamodb_client.query(params)

    return response
  end

  def _dynamodb_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @dynamodb_client.nil?

        # Creat the CloudFormation client
        Log.debug "Creating a new AWS DynamoDB client"

        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?
        credentials = _control_credentials || nil
        params[:credentials] = credentials unless credentials.nil?

        @dynamodb_client = Aws::DynamoDB::Client.new(params)
      end
    end

    return @dynamodb_client
  end
end
