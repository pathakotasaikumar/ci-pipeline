function Execute-TrendMicroInstall {

$current_time=Get-Date -format "yyyy-MM-dd-HH:mm:ss"
$myFQDN=(Get-WmiObject win32_computersystem).DNSHostName+"."+(Get-WmiObject win32_computersystem).Domain
$trend_agent_location="C:\Program Files\Trend Micro\Deep Security Agent\"
$trend_agent_logs="C:\Windows\Temp\trendagent_registeration.log"

$url=$pipeline_TrendAWSUrl
$activationurl=$pipeline_DSAgentActivationUrl
$trend_proxy=$pipeline_TrendSAASProxy
$trend_tenant_id=$pipeline_TrendTenantID
$trend_token_id=$pipeline_TrendTokenId
$policy_components="$pipeline_Ams-$pipeline_Qda-$pipeline_As-$pipeline_Ase-$pipeline_Branch-$pipeline_Build-$pipeline_Component"

echo "$current_time TrendAgentHostname:$myFQDN Registration:ScriptStarted with url:$url" >> $trend_agent_logs

cd $trend_agent_location

$heartbeatStatus=.\dsa_control.cmd -m

if($heartbeatStatus -match "activate agent first")
    
{
    echo "$current_time TrendAgentHostname:$myFQDN Registration:StartedReset with url:$url" >> $trend_agent_logs
    & "C:\Program Files\Trend Micro\Deep Security Agent\dsa_control.cmd" -r
 
    & sleep 30

    echo "$current_time TrendAgentHostname:$myFQDN Registration:SetDSMProxy with url:$url" >> $trend_agent_logs
    & "C:\Program Files\Trend Micro\Deep Security Agent\dsa_control.cmd" -x dsm_proxy://$($trend_proxy)

    echo "$current_time TrendAgentHostname:$myFQDN Registration:SetDSRProxy with url:$url" >> $trend_agent_logs
    & "C:\Program Files\Trend Micro\Deep Security Agent\dsa_control.cmd" -y relay_proxy://$($trend_proxy)

    echo "$current_time TrendAgentHostname:$myFQDN Registration:StartedActivation with url:$url" >> $trend_agent_logs
    & "C:\Program Files\Trend Micro\Deep Security Agent\dsa_control.cmd" -a "dsm://$($activationurl):443" "tenantID:$trend_tenant_id" "token:$trend_token_id" "policy:$policy_components" --max-dsm-retries 5 --dsm-retry-interval 30

    & "C:\Program Files\Trend Micro\Deep Security Agent\dsa_control.cmd" -m 
    $lastCode = $LastExitCode
    if ($LastExitCode) { throw "LastExitCode: $lastCode - Unable to install Trend Micro Deep security agent" } 
    
    $heartbeatStatusRecheck=.\dsa_control.cmd -m
    
      if($heartbeatStatusRecheck -match "HTTP Status: 200 - OK")
      {
      echo "$current_time TrendAgentHostname:$myFQDN Registration:CompletedActivation with url:$url" >> $trend_agent_logs
      Wait-ServicesUntilRunning @(
        "ds_agent"
        "ds_notifier"
        "amsssp")
      }
      else{
      echo "$current_time TrendAgentHostname:$myFQDN Registration:FailedTrendDSMCommunication with url:$url" >> $trend_agent_logs
      }
}
else{
    echo "$current_time TrendAgentHostname:$myFQDN Registration:CompletedAlready with url:$url" >> $trend_agent_logs
}
}


function Wait-ServicesUntilRunning {

    Param(
        [Parameter(Mandatory=$True)]
        [String[]]$serviceNames
    )

    $servicesLogString = [String]::Join("/", $serviceNames)
    echo "Waiting services to enter 'Running' state: $servicesLogString"
    echo "$current_time TrendAgentHostname:$myFQDN Registration:TrendServicesCheckStarted state:$servicesLogString" >> $trend_agent_logs

    # polling services for 5 minutes
    # 6 attempts per minute x 5 times x 10 sec
    $attempts         = 6 * 5
    $currentAttempt   = 0 
    $timeoutInSeconds = 10
    $servicesState = @{}
    $inWaitingState = $true

    while($currentAttempt -lt $attempts) {
        
        foreach($serviceName in $serviceNames) {
            $servicesState[$serviceName] = $false
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if($service -ne $null) {
                echo "$current_time TrendAgentHostname:$myFQDN Registration:TrendServicesExists [$currentAttempt/$attempts] service:$serviceName status:$($service.Status)" >> $trend_agent_logs
                $servicesState[$serviceName] = ($service.Status -eq "Running")
            } else { 
                echo "$current_time TrendAgentHostname:$myFQDN Registration:TrendServicesNotExists [$currentAttempt/$attempts] service:$serviceName status:NotExist" >> $trend_agent_logs
            }
        }

        $inWaitingState = $servicesState.ContainsValue($false) -eq $true

        if($inWaitingState -eq $true) {
            echo "`t[$currentAttempt/$attempts] waiting $timeoutInSeconds seconds..."
            Start-Sleep -Seconds $timeoutInSeconds
        } else { 
            echo "$current_time TrendAgentHostname:$myFQDN Registration:TrendServicesRunning with url:$url" >> $trend_agent_logs
            break
        }
        $currentAttempt++  
    }

    if($inWaitingState -eq $true) {
        $fullTimeout = $attempts * $timeoutInSeconds
        echo "$current_time TrendAgentHostname:$myFQDN Registration:TrendServicesTimeout with url:$url" >> $trend_agent_logs
    }
}



