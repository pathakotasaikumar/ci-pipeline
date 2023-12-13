<powershell>

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue

$MetadataResource = "<| MetadataResource |>"
$ResourceToSignal = "<| ResourceToSignal |>"
$StackId = "<| StackId |>"
$Region = "<| Region |>"
$domain = "<| Domain |>"
$DeploymentEnv = "<| DeploymentEnv |>"
$WindowsOU = "<| WindowsOU |>"
$Proxy = "<| AwsProxy |>"
$NoProxy = "<| NoProxy |>"
$TrenddsmUrl = "<| TrenddsmUrl |>"
$TrendPolicyName = "<| TrendPolicyName |>"
$SecretManagementArn="<| SecretManagementLambdaArn |>"
$SsmPlatformSecretPath="<| SSMPlatformVariablePath |>"

# common helpers 
function Log-Message($message, $level) {
  $stamp=$(get-date -f "MM-dd-yyyy HH:mm:ss.fff")
  $logMessage="$stamp : $level : $($env:USERDOMAIN)/$($env:USERNAME) : $message"

  Write-Output $logMessage
}

function Log-InfoMessage($message) {
  Log-Message "$message" "INFO"
}

function Trace-ProxyValues($message, $Proxy, $NoProxy) {
  Log-InfoMessage $message
  Log-InfoMessage "`t- Proxy: $Proxy"
  Log-InfoMessage "`t- NoProxy: $NoProxy"
}

function Upload-Logs {
  $bucket, $s3Path = $RemoteLogsPath.split("/", 2)
  New-Item C:\Windows\Temp\Logs -Type Directory -Force

  foreach ($logFile in $LogFiles) {
    try {
      if (Test-Path $logFile) {
        $logFilename = $logFile.split("\")[-1]
        $copyFilename = "C:\Windows\Temp\Logs\$logFilename"
        Copy-Item $logFile $copyFilename -Force
        Write-S3Object -BucketName $bucket -key "$s3Path/$logFilename" -File $copyFilename -ServerSideEncryption "AES256" -CannedACLName "bucket-owner-full-control" -Force
        Remove-Item $copyFilename, $logFilename -Force -ErrorAction SilentlyContinue
      }
    }
    catch {
      Write-Warning "Upload of '$logFile' to S3 '$RemoteLogsPath' has failed - $_"
    }
  }
}

function Get-DeployStage {
  return $ENV:DeployStage
}

function Set-DeployStage($value) {
  setx /m "DeployStage" $value
}

function Get-SafeComputerName($instanceId) {
  $result = $instanceId 

  if ($instanceId.Length -eq 19) { 
    $result = "q" + $instanceId.subString(5)
  } 

  return $result
}

function Get-ProsperoPath {
  return "C:\\Windows\\Temp\\Pipeline.Prospero.ps1"
}

function Stage1-Sleep {
  Start-Sleep 10
}

function Flush-LogsToS3 {
  Param(
    [Parameter(Mandatory=$true)][string] $logFilePath
  )

  try {
    stop-transcript | out-null
  } catch [System.InvalidOperationException] {

  }

  Upload-Logs 
  # -IncludeInvocationHeader might fail on win2012
  Start-Transcript -Path $logFilePath -Append
}

function Invoke-LambdaToCreateSSMSecret($instanceId) {

  $params =@{
   "EC2InstanceId" = "$InstanceId"
   "ExecutionType" = "Instance"
  } | ConvertTo-Json

  $result=Invoke-LMFunction -FunctionName $SecretManagementArn -InvocationType "RequestResponse" -Payload $params
  IF(![string]::IsNullOrEmpty($result.FunctionError)) {
     $exitCode = "1"
     throw "Exit code: $exitCode - Failed to create platform Secrets for instance id $InstanceId"
  } else {
     Log-InfoMessage "Successfully created the SSM parameters for Instance id $InstanceId"
  }
}

# initial setup
Trace-ProxyValues "Setting proxy system environment variables" $Proxy $NoProxy
setx /m HTTP_PROXY $Proxy
setx /m HTTPS_PROXY $Proxy
setx /m NO_PROXY $NoProxy

Trace-ProxyValues "Setting proxy values for the current session" $Proxy $NoProxy
$env:HTTP_PROXY = $Proxy
$env:HTTPS_PROXY = $Proxy
$env:NO_PROXY = $NoProxy

$InstanceId = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/instance-id"
$RemoteLogsPath = "<| RemoteLogsPath |>/$InstanceId"

$LogFiles = (
    "$ENV:SystemDrive\cfn\log\cfn-init-cmd.log",
    "$ENV:SystemDrive\cfn\log\cfn-init.log",
    "$ENV:SystemDrive\cfn\log\cfn-wire.log",
    "$ENV:SystemRoot\Temp\deploy.log",
    "$ENV:SystemRoot\Temp\bootstrap.log",
    "$ENV:SystemRoot\context.ps1",
    "$ENV:SystemRoot\Temp\lri_bootstrap.log"
)

$ErrorActionPreference = "Stop"
$logFile = "$ENV:SystemRoot\Temp\deploy.log"

try {
  
  Start-Transcript -Path $logFile -Append

  $ComputerName = Get-SafeComputerName $InstanceId

  [int]$Stage = Get-DeployStage

  # stage 1 deploys scripts to an instance
  if ($Stage -lt 1) {
    Log-InfoMessage "Running QCP Secret management lambda to populate the secrets to SSM"
    Invoke-LambdaToCreateSSMSecret $InstanceId

    Log-InfoMessage "Running Stage $([int]++$Stage): cfn-init Prepare"
    Set-DeployStage $Stage

    Log-InfoMessage "Executing cfn-init Prepare step (region=$Region; stack=$StackId; resource=$MetadataResource)"
    $exitCode = (Start-Process "cfn-init.exe" -ArgumentList "-v --region $Region --stack $StackId --resource $MetadataResource --configsets Prepare" -Wait -Passthru).ExitCode
    if ($exitCode) { throw "Exit code: $exitCode - Failed to execute cfn-init Prepare step" }
    
    # Forcing delay in case user specified waitAfterCompletion: forever, breaking signalling
    Stage1-Sleep

    Flush-LogsToS3 $logFile
  } else { Log-InfoMessage "Skipping Stage 1" }

  # further stages can have access to deployed scripts
  $prosperoPath =  Get-ProsperoPath
  Log-InfoMessage "Including Prospero: $prosperoPath"
  . $prosperoPath
  
  Process-DeployStages -Stage $Stage `
                       -ResourceToSignal $ResourceToSignal `
                       -ComputerName $ComputerName `
                       -domain $domain `
                       -Region $Region `
                       -StackId $StackId `
                       -MetadataResource $MetadataResource `
                       -WindowsOU $WindowsOU `
                       -DeploymentEnv $DeploymentEnv `
                       -TrenddsmUrl $TrenddsmUrl `
                       -TrendPolicyName $TrendPolicyName `
                       -Proxy $Proxy `
                       -SsmPlatformSecretPath $SsmPlatformSecretPath `
                       -logFile $logFile

  exit 0
}
catch [System.Exception] {
  Log-InfoMessage "ERROR: $_"
  Log-InfoMessage "Signalling CloudFormation with cfn-signal (error=1; region=$Region; stack=$StackId; resource=$ResourceToSignal)"
 
  cfn-signal.exe -e 1 --region $Region --stack $StackId --resource $ResourceToSignal

  Log-InfoMessage "Clean up the SSM Parameters"
  Execute-CleaningUpSsmParameter $SsmPlatformSecretPath $InstanceId

  Flush-LogsToS3 $logFile
  
  exit 1
}

</powershell>
<persist>true</persist>
<runAsLocalSystem>true</runAsLocalSystem>
