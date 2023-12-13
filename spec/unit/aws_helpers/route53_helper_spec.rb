$LOAD_PATH.unshift("#{BASE_DIR}/lib/aws_helpers")
require 'route53_helper'

describe 'Route53 Helper' do
  before(:context) do
    @dummy_class = DummyClass.new
    @dummy_class.extend(Route53Helper)
  end

  context '_route53_check_health_status' do
    it 'successful health check' do
      route53_mock_client = double(Aws::Route53::Client)
      route53_mock_response = double(Object)
      allow(AwsHelper).to receive(:_route53_client).and_return(route53_mock_client)
      allow(route53_mock_client).to receive(:get_health_check_status).and_return(route53_mock_response)
      allow(route53_mock_response).to receive_message_chain("health_check_observations.first.status_report.status").and_return("Success: 3 datapoints were not greater than or equal to the threshold (90.0).")
      expect(
        AwsHelper._route53_check_health_status(
          healthcheckid: "297c5566-354b-4b6f-8d92-062d835e5383",
          status: "Healthy"
        )
      ).to be true
    end
    it 'failure health check' do
      route53_mock_client = double(Aws::Route53::Client)
      route53_mock_response = double(Object)
      allow(AwsHelper).to receive(:_route53_client).and_return(route53_mock_client)
      allow(route53_mock_client).to receive(:get_health_check_status).and_return(route53_mock_response)
      allow(route53_mock_response).to receive_message_chain("health_check_observations.first.status_report.status").and_return("Failure: CloudWatch didn't have enough data to determine the state of the alarm. The Route 53 health checker considers the health check to be unhealthy based on the InsufficientDataHealthState setting.")
      expect(
        AwsHelper._route53_check_health_status(
          healthcheckid: "297c5566-354b-4b6f-8d92-062d835e5383",
          status: "UnHealthy"
        )
      ).to be true
    end
    it 'test timeout issue' do
      route53_mock_client = double(Aws::Route53::Client)
      route53_mock_response = double(Object)
      allow(AwsHelper).to receive(:_route53_client).and_return(route53_mock_client)
      allow(route53_mock_client).to receive(:get_health_check_status).and_return(route53_mock_response)
      allow(route53_mock_response).to receive_message_chain("health_check_observations.first.status_report.status").and_return("unknown: CloudWatch didn't have enough data to determine the state of the alarm. The Route 53 health checker considers the health check to be unhealthy based on the InsufficientDataHealthState setting.")
      expect {
        AwsHelper._route53_check_health_status(
          healthcheckid: "297c5566-354b-4b6f-8d92-062d835e5383",
          status: "UnHealthy",
          delay: 0.05,
          max_attempts: 2
        )
      }.to raise_error /Timed out waiting for Health check to/
    end
  end

  context '_route53_client' do
    it 'successful execution - initialize no provisioning or control credentials' do
      allow(Aws::Route53::Client).to receive(:new)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper.send(:_route53_client) }.not_to raise_exception
    end

    it 'successful execution - initialize with provisioning credentials' do
      allow(Aws::Route53::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials).and_return(mock_credentials)
      allow(AwsHelper).to receive(:_control_credentials)
      expect { AwsHelper.send(:_route53_client) }.not_to raise_exception
    end

    it 'successful execution - initialize with control credentials' do
      allow(Aws::Route53::Client).to receive(:new)
      mock_credentials = double(Object)
      allow(AwsHelper).to receive(:_provisioning_credentials)
      allow(AwsHelper).to receive(:_control_credentials).and_return(mock_credentials)
      expect { AwsHelper.send(:_route53_client) }.not_to raise_exception
    end
  end
end
