#/usr/bin/env ruby

##############################
# Usage:
#   configure-s3-notifications.rb \
#     -b $pipeline_AppBucketName
#     -p "${pipeline_Ase}/${pipeline_Branch}/${pipeline_Build}" \
#     -l $function1_TestFunctionArn
#
#   configure-s3-notifications.rb \
#     -b $pipeline_AppBucketName \
#     -a remove \
#     -e 9c149d214039b717eda961ed2a09a85298c7afdc

require 'aws-sdk'
require 'json'
require 'yaml'
require 'logger'
require 'securerandom'
require 'optparse'

def get_s3_notification_configurations(
  bucket_name: nil
)

  s3 = Aws::S3::Client.new(region: 'ap-southeast-2')
  s3.get_bucket_notification_configuration(bucket: bucket_name)
end

def put_s3_notification_configurations(
  bucket_name: nil,
  configurations: nil
)

  s3 = Aws::S3::Client.new(region: 'ap-southeast-2')
  resp = s3.put_bucket_notification_configuration(
    bucket: bucket_name,
    notification_configuration: configurations
  )
  Log.debug("Put bucket notification configurations: #{configurations}")
  Log.debug("Put bucket notification response: #{resp}")
rescue Aws::S3::Errors::InvalidArgument => e
  if e.to_s =~ /Same ID used for multiple configurations. IDs must be unique./
    Log.debug "Configuration already applied"
  else
    raise "#{e}"
  end
rescue => e
  raise "#{e}"
end

# Generates S3 notification configuration hash
# @param event_id [String] Unique event id to be added to the bucket policy
# @param lambda_function_arn [String] Funciton ARN to serve as target (Note: must exist)
# @param key_prefix [String] Prefix for target S3 objects
# @param key_suffix [String] Suffix for target S3 objects
# @param events [Array] List of S3 events to monitor
def s3_notification_configuration(
  event_id: nil,
  lambda_function_arn: nil,
  key_prefix: nil,
  key_suffix: nil,
  events: ['s3:ObjectCreated:*']
)

  filter = {}
  if key_prefix.is_a? String
    ((filter[:key]||={})[:filter_rules]||=[]) << {
      name: 'Prefix',
      value: key_prefix
    }
  end

  if key_suffix.is_a? String
    ((filter[:key]||={})[:filter_rules]||=[]) << {
      name: 'Suffix',
      value: key_suffix
    }
  end

  event_configuration = {
    id: event_id,
    lambda_function_arn: lambda_function_arn,
    events: events
  }

  event_configuration[:filter] = filter unless filter.empty?
  Log.debug "#{event_configuration}"
  return event_configuration
end

def add_notification_configurations(
  bucket_name: nil,
  notification_type: nil,
  notification_definition: nil
)
  unless [:lambda_function_configurations].include? notification_type
    raise ArgumentError, "Must specify notification type as a Symbol"
  end

  unless notification_definition.is_a? Hash
    raise ArgumentError, "Must specify 'notification_definition' as a Hash"
  end

  notification_configurations = get_s3_notification_configurations(
    bucket_name: bucket_name
  ).to_h

  configurations = notification_configurations[notification_type].to_a || []

  configurations << notification_definition

  notification_hash = notification_configurations.to_h
  # Add notification configurations
  notification_hash[notification_type] = configurations

  begin
    put_s3_notification_configurations(
      bucket_name: bucket_name,
      configurations: notification_hash
    )

    Log.debug "Successfully re-applied configurations"
  rescue => e
    Log.error "Failed to apply notification configurations - #{e}"
  end
end

def remove_notification_configurations(
  bucket_name: nil,
  notification_type: nil,
  event_id: nil
)
  unless [:lambda_function_configurations].include? notification_type
    raise ArgumentError, "Must specify notification type as a Symbol"
  end

  unless event_id.is_a? String
    raise ArgumentError, "Must specify 'event_id' as a String"
  end

  notification_configurations = get_s3_notification_configurations(
    bucket_name: bucket_name
  ).to_h

  configurations = notification_configurations[notification_type].to_a || []
  configurations.delete_if{|v| v[:id] == event_id}

  # Add notification configurations
  notification_configurations[notification_type] = configurations

  begin
    put_s3_notification_configurations(
      bucket_name: bucket_name,
      configurations: notification_configurations
    )

    Log.debug "Successfully re-applied configurations"
  rescue => e
    Log.error "Failed to apply notification configurations - #{e}"
  end
end


options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: test_s3 [options]'
  opts.on('-a', '--action STRING', '[Add/Remove]') { |v| options[:action] = v}
  opts.on('-e', '--event_id STRING', 'Event Id') { |v| options[:event_id] = v}
  opts.on('-b', '--bucket_name STRING', 'Bucket Name') { |v| options[:bucket_name] = v}
  opts.on('-p', '--prefix STRING', 's3 key prefix to filter') { |v| options[:prefix] = v }
  opts.on('-s', '--suffix STRING', 's3 key suffix to filter') { options[:suffix] = v}
  opts.on('-l', '--lambda STRING', 'lambda function arn') { |v| options[:lambda] = v }
  opts.on('-d', '--debug', 'Print debug messages') { options[:debug] = true}
  opts.on_tail('-h', '--help', 'Show this message') { puts opts; exit}
end.parse!

Log = Logger.new(STDOUT)

Log.formatter = proc {|severity, datetime, _, msg| "[ #{datetime} ] : #{severity} - #{msg}\n" }
Log.level = Logger::INFO

# Generate unique hex value
event_id = options[:event_id] || SecureRandom.hex(20)
key_prefix = options[:prefix]
key_suffix = options[:suffix]
bucket_name = options[:bucket_name]
lambda_function_arn = options[:lambda]

# Build notification configuration result
notification_config = s3_notification_configuration(
  event_id: event_id,
  lambda_function_arn: lambda_function_arn,
  key_prefix: key_prefix,
  key_suffix: key_suffix,
  events: ['s3:ObjectCreated:*']
)

action = options[:action] || :add
action = action.downcase.to_sym

case action
  when :add
    # Add configurations to existing bucket
    add_notification_configurations(
      bucket_name: bucket_name,
      notification_type: :lambda_function_configurations,
      notification_definition: notification_config
    )
    Log.debug JSON.pretty_generate(notification_config)
  when :remove
    # Add configurations to existing bucket
    remove_notification_configurations(
      bucket_name: bucket_name,
      notification_type: :lambda_function_configurations,
      event_id: event_id
    )
  else
    raise "Invalid action - #{options[:action]} specified"
end
