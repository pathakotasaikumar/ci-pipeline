# Baketime userdata script for Windows 2012, 2016 and 2019
# - Executes CloudFormation init metadata
#
# Logs are written to:
#   C:\Windows\Temp\bake.log
#
# Also see:
#   C:\cfn\log
#
# Supported for Windows 2012, 2016 and 2019 instances

<powershell>

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue

$MetadataResource = "<| MetadataResource |>"
$ResourceToSignal = "<| ResourceToSignal |>"
$StackId = "<| StackId |>"
$Region = "<| Region |>"
$Domain = "<| Domain |>"
$WindowsOU = "<| WindowsOU |>"
$Proxy = "<| AwsProxy |>"
$NoProxy = "<| NoProxy |>"


Write-Output "INFO: Setting proxy system environment variables"
setx /m HTTP_PROXY $Proxy
setx /m HTTPS_PROXY $Proxy
setx /m NO_PROXY $NoProxy

Write-Output "INFO: Setting proxy variables for the current session"
$env:HTTP_PROXY = $Proxy
$env:HTTPS_PROXY = $Proxy
$env:NO_PROXY = $NoProxy

$InstanceId = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/instance-id"
$RemoteLogsPath = "<| RemoteLogsPath |>/$InstanceId"
$OSVersion = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name ProductName).ProductName

$LogFiles = (
  "$ENV:SystemDrive\cfn\log\cfn-init-cmd.log",
  "$ENV:SystemDrive\cfn\log\cfn-init.log",
  "$ENV:SystemDrive\cfn\log\cfn-wire.log",
  "$ENV:SystemRoot\Temp\bake.log",
  "$ENV:SystemRoot\Temp\bootstrap.log",
  "$ENV:SystemRoot\context.ps1"
)

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
    } catch {
      Write-Warning "Upload of '$logFile' to S3 '$RemoteLogsPath' has failed - $_"
    }
  }
}

function Add-XmlFragment {
  Param(
    [Parameter(Mandatory=$true)][System.Xml.XmlNode] $xmlElement,
    [Parameter(Mandatory=$true)][string] $text
  )
  $xml = $xmlElement.OwnerDocument.ImportNode(([xml]$text).DocumentElement, $true)
  [void]$xmlElement.AppendChild($xml)
}

function Get-UnattendBlock {
  param([parameter(Mandatory)][string]$Domain)

$xmlMicrosoftWindowsUnattendedJoin = @"
<component name="Microsoft-Windows-UnattendedJoin" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <Identification>
    <UnsecureJoin>False</UnsecureJoin>
    <JoinDomain>$Domain</JoinDomain>
    <Credentials>
      <Domain>$Domain</Domain>
      <Password>qcp-domain-password</Password>
      <Username>qcp-domain-user</Username>
    </Credentials>
  </Identification>
</component>
"@
  return $xmlMicrosoftWindowsUnattendedJoin
}


try {

  # Stop script on any errors
  $ErrorActionPreference = "Stop"

  Start-Transcript -IncludeInvocationHeader -Path "C:\Windows\Temp\bake.log" -Append

  [int]$Stage = $ENV:BakeStage

  if ($Stage -lt 1) {
    Write-Output "Running Stage $([int]++$Stage): cfn-init Prepare"
    setx /m "BakeStage" $Stage

    Write-Output "Info: Removing old logs files"
    foreach($logFile in $LogFiles) { Remove-Item -Path $logFile -Force -ErrorAction SilentlyContinue }

    Write-Output "INFO: Executing cfn-init Prepare step (region=$Region; stack=$StackId; resource=$MetadataResource)"
    $exitCode = (Start-Process "cfn-init.exe" -ArgumentList "-v --region $Region --stack $StackId --resource $MetadataResource --configsets Prepare" -Wait -Passthru).ExitCode
    if ($exitCode) {throw "Failed to execute cfn-init Prepare step"}
    # Forcing 10 second delay for restarts with waitAfterCompletion: forever
    Start-Sleep 10
  } else { Write-Output "Skipping Stage 1 - cfn-init Prepare" }

  if ($Stage -lt 2) {
    Write-Output "Running Stage $([int]++$Stage): cfn-init Deploy"
    setx /m "BakeStage" $Stage

    Write-Output "INFO: Executing cfn-init Deploy step (region=$Region; stack=$StackId; resource=$MetadataResource)"
    $exitCode = (Start-Process "cfn-init.exe" -ArgumentList "-v --region $Region --stack $StackId --resource $MetadataResource --configsets Deploy" -Wait -Passthru).ExitCode
    if ($ExitCode) { throw "Failed to execute cfn-init Deploy step" }
    # Forcing 10 second delay in case user specified waitAfterCompletion: forever, breaking signalling
    Start-Sleep 10
  } else { Write-Output "Skipping Stage 2 - cfn-init Deploy" }

  if ($Stage -lt 3) {
    Write-Output "Running Stage $([int]++$Stage): cfn-init Sysprep"
    setx /m "BakeStage" $Stage

    if ($OSVersion -like "*2012*" ) {
      Write-Output "INFO: Replacing EC2Config settings files"
      Copy-Item "C:\Windows\Temp\BundleConfig.xml" "C:\Program Files\Amazon\Ec2ConfigService\Settings\BundleConfig.xml"
      Copy-Item "C:\Windows\Temp\sysprep2008.xml" "C:\Program Files\Amazon\Ec2ConfigService\sysprep2008.xml"

      $sysprepAnswerFile = "C:\Program Files\Amazon\Ec2ConfigService\sysprep2008.xml"

    } elseif ($OSVersion -like "*2016*" ) {

      Copy-Item "C:\Windows\Temp\SysprepInstance2016.ps1" "C:\ProgramData\Amazon\EC2-Windows\Launch\Scripts\SysprepInstance.ps1"
      $SysprepAnswerFile = "C:\ProgramData\Amazon\EC2-Windows\Launch\Sysprep\Unattend.xml"

    } elseif ($OSVersion -like "*2019*" ) {

      Copy-Item "C:\Windows\Temp\SysprepInstance2016.ps1" "C:\ProgramData\Amazon\EC2-Windows\Launch\Scripts\SysprepInstance.ps1"
      $SysprepAnswerFile = "C:\ProgramData\Amazon\EC2-Windows\Launch\Sysprep\Unattend.xml"

    } else {
        throw "Unknown operating system - $OSVersion"
    }

    $XMLfile = [xml](Get-Content $sysprepAnswerFile)
    $xmlSettingsSpecialize = $XMLfile.unattend.settings | where {$_.pass -ieq 'specialize'}
    ($xmlSettingsSpecialize.component | ? { $_.name -ieq "Microsoft-Windows-Shell-Setup" }).copyprofile = "false"

    # If Domain is specified then add UnattendedJoin section to sysprep answer file
    if ($Domain) {
      Add-XmlFragment $xmlSettingsSpecialize $(Get-UnattendBlock -Domain $domain)
      # Add ActiveDirectory OU if specified
      if ($WindowsOU -and ($WindowsOU -ne "@default")) {
        Write-Output "INFO: Using OU container $WindowsOU" 
        $ouXML = "<MachineObjectOU>$WindowsOU</MachineObjectOU>"
        Add-XmlFragment ($xmlSettingsSpecialize.component | ? { $_.name -ieq "Microsoft-Windows-UnattendedJoin" }).Identification $ouXML
      } else {
        Write-Output "INFO: Using default OU container" 
      }
    }

    $XMLfile.save($sysprepAnswerFile)

    Write-Output "INFO: Running sysprep"
    if ($OSVersion -like "*2012*" ) {
        & "C:\Program Files\Amazon\Ec2ConfigService\ec2config.exe" -sysprep
    } elseif ($OSVersion -like "*2016*" ) {
        & "C:\ProgramData\Amazon\EC2-Windows\Launch\Scripts\InitializeInstance.ps1" -Schedule
        & "C:\ProgramData\Amazon\EC2-Windows\Launch\Scripts\SysprepInstance.ps1"
    } elseif ($OSVersion -like "*2019*" ) {
      & "C:\ProgramData\Amazon\EC2-Windows\Launch\Scripts\InitializeInstance.ps1" -Schedule
      & "C:\ProgramData\Amazon\EC2-Windows\Launch\Scripts\SysprepInstance.ps1"
    }

    # Remove persisted route to instance metadata service
    route delete 169.254.169.254


    Write-Output "INFO: Writing out windeploy.bat batch file to disk"
    $WinDeploySub = "PowerShell.exe -ExecutionPolicy Unrestricted -File c:\Windows\Temp\windeploy.ps1 && c:\Windows\System32\oobe\windeploy.exe"
    Set-Content "C:\Windows\Temp\windeploy.bat" $WinDeploySub -Encoding ASCII

    Write-Output "INFO: Set registry key to run custom batch file on startup"
    Set-ItemProperty -Path "HKLM:\System\Setup" -Name "CmdLine" -Value "C:\Windows\Temp\windeploy.bat"

    Write-Output "INFO: Signalling CloudFormation with cfn-signal (error=0; region=$Region; stack=$StackId; resource=$ResourceToSignal)"
    cfn-signal.exe -e 0 --region $Region --stack $StackId --resource $ResourceToSignal

    # Remove BakeStage system var
    Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "BakeStage"
    Stop-Transcript
    Upload-Logs

  } else { Write-Output "Skipping Stage 3 - Sysprep" }
  exit 0

} catch [System.Exception] {
  Write-Output "ERROR: $_"
  Write-Output "INFO: Signalling CloudFormation with cfn-signal (error=1; region=$Region; stack=$StackId; resource=$ResourceToSignal)"
  cfn-signal.exe -e 1 --region $Region --stack $StackId --resource $ResourceToSignal
  Stop-Transcript
  Upload-Logs
  exit 1
}

</powershell>
<persist>true</persist>
<runAsLocalSystem>true</runAsLocalSystem>