require 'aws-sdk'

# Module provides wrappers for AWS SDK methods
module KinesisHelper
  # initialise AWS SDK Kinesis client
  def _kinesis_helper_init
    @kinesis_client = nil
  end

  # Set retention period (in hours) for a kinesis stream
  # @param (see Aws::Kinesis::Client#increase_stream_retention_period)
  def kinesis_set_retention_period_hours(
    stream_name: nil,
    retention_period_hours: 24
  )

    # Get the current retention period
    response = _kinesis_client.describe_stream(stream_name: stream_name)

    # Increase or decrease the retention period
    if retention_period_hours < response.stream_description.retention_period_hours
      _kinesis_client.decrease_stream_retention_period(
        stream_name: stream_name,
        retention_period_hours: retention_period_hours
      )
    elsif retention_period_hours > response.stream_description.retention_period_hours
      _kinesis_client.increase_stream_retention_period(
        stream_name: stream_name,
        retention_period_hours: retention_period_hours
      )
    else
      Log.debug "Retention period for #{stream_name} is left unchanged at #{retention_period_hours}"
    end
  end

  # Initialises AWS::Kinesis::Client
  # @return [Struct] AWS:Kinesis::Client
  def _kinesis_client
    # Create a new client if it doesn't exist yet
    @client_mutex.synchronize do
      if @kinesis_client.nil?

        # Creat the CloudFormation client
        Log.debug "Creating a new AWS Kinesis client"

        # Build the client parameters
        params = {}
        params[:http_proxy] = @proxy unless @proxy.nil?
        params[:region] = @region unless @region.nil?
        params[:retry_limit] = @retry_limit unless @retry_limit.nil?
        credentials = _provisioning_credentials || _control_credentials || nil
        params[:credentials] = credentials unless credentials.nil?

        @kinesis_client = Aws::Kinesis::Client.new(params)
      end
    end

    return @kinesis_client
  end
end
