
# helper for Deploy/Bake stages
[int]$SSM_Param_Max_result = 10
function Get-DeployCleanupFiles() {

    $result = @(
        'C:\Windows\Temp\bamboo-vars.conf',
        'C:\Windows\Temp\bamboo-vars.conf.bak',
        'C:\windowsagents',
        'C:\windowsagents.zip',
        'C:\Windows\Temp\platform_vars',
        'C:\Program Files\Amazon\Ec2ConfigService\sysprep2008.xml',
        'C:\Windows\Panther\unattend.xml'
    )

    return $result
}

# common helpers
function Log-Message($message, $level) {
    $stamp = $(get-date -f "MM-dd-yyyy HH:mm:ss.fff")
    $logMessage = "$stamp : $level : $($env:USERDOMAIN)/$($env:USERNAME) : $message"

    Write-Host $logMessage
}

function Log-InfoMessage($message) {
    Log-Message "$message" "INFO"
}

function Get-DeployStage() {
    [int]$stage = $ENV:DeployStage

    return $stage
}

function Set-DeployStage($value) {
    setx /m "DeployStage" $value
}

function Get-PartOfDomain() {
    (gwmi win32_computersystem).partofdomain
}

function Get-BambooVariable($name) {
    (Get-Content c:\Windows\Temp\bamboo-vars.conf | Where-Object { $_ -like $name }).split("=")[1]
}


function Read-SSMParameter() {
    Param (
        [Parameter(Mandatory = $True)]
        [string]$ssmPlatformSecretPath,

        [Parameter(Mandatory = $True)]
        [string]$instanceId,

        [Parameter(Mandatory = $True)]
        [string]$variable,

        [Parameter(Mandatory = $False)]
        [Boolean]$destroy = $True
    )
    $ssmParameterFullPath = $ssmPlatformSecretPath + "/" + $instanceId + "/"
    $results = (Get-SSMParametersByPath -MaxResult $SSM_Param_Max_result -Path $ssmParameterFullPath -WithDecryption 1)
    Foreach ($ssmParameter in $results) {
        if ($ssmParameter.Name -eq "$ssmParameterFullPath" + "$variable") {
            $decryptedValue = (KMS-Decrypt -Base64Input $ssmParameter.Value)
            if ($destroy) {
                ( Remove-SSMParameter -Name $ssmParameter.Name -Force )
            }
            else {
                Log-InfoMessage "The destroy parameter is set to $destroy. So, not cleaning up the SSM Parameter."
            }

            return $decryptedValue
        }
    }
}

function Execute-AddToLocalGroup($group, $value) {

    Log-InfoMessage "`tAdding user: $value to group: $group"

    net localgroup $group /add $value

    $lastCode = $LastExitCode
    if ($lastCode) { throw "LastExitCode: $lastCode - failed to add user '$value' to '$group' group" }
}

function Execute-DisableUser($value) {
    Log-InfoMessage "`tDisabling user: $value"

    net user $value /active:no

    $lastCode = $LastExitCode
    if ($lastCode) { throw "LastExitCode: $lastCode - Failed to disable user: $value" }
}

function Execute-GrantFolderPermissions($folderPath, $permissions) {
    Log-InfoMessage "`tGranting permissions: $permissions on folder: $folderPath"

    icacls "$folderPath" /grant "$permissions"

    $lastCode = $LastExitCode
    if ($lastCode) { throw "LastExitCode: $lastCode - Unable to set permissions: $permissions on folder: $folderPath" }
}

function Execute-TrendMicroInstall {
    $taskName = "TrendAgentRegCheck"
    $taskUser = "SYSTEM"

    Log-InfoMessage "`tRegistering Schdeule Task for Trend Deep Security Agent"
    register-scheduledtask -Xml (get-content "C:\Windows\Temp\trend_sched_task.xml" | out-string) -TaskName $taskName -User $taskUser

    $schedTask = Get-ScheduledTask -TaskName $taskName  | where state -EQ 'Ready'

    $lastCode = $LastExitCode
    if ($lastCode) { throw "LastExitCode: $lastCode - Failed to Register ScheduleTask: $taskName" }

    Log-InfoMessage "`tStarting Schdeule Task for Trend Deep Security Agent"
    Start-ScheduledTask -TaskName $taskName
    $lastCode = $LastExitCode
    if ($lastCode) { throw "LastExitCode: $lastCode - Failed to Run ScheduleTask: $taskName" }

    Log-InfoMessage "`tCompleted Trend Micro install"
}

function Wait-ServicesUntilRunning {

    Param(
        [Parameter(Mandatory = $True)]
        [String[]]$serviceNames
    )

    $servicesLogString = [String]::Join("/", $serviceNames)
    Log-InfoMessage "Waiting services to enter 'Running' state: $servicesLogString"

    # polling services for 5 minutes
    # 6 attempts per minute x 5 times x 10 sec
    $attempts = 6 * 5
    $currentAttempt = 0
    $timeoutInSeconds = 10
    $servicesState = @{}
    $inWaitingState = $true

    while ($currentAttempt -lt $attempts) {

        foreach ($serviceName in $serviceNames) {
            $servicesState[$serviceName] = $false

            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

            if ($service -ne $null) {
                Log-InfoMessage "`t[$currentAttempt/$attempts] service: $serviceName status: $($service.Status)"
                $servicesState[$serviceName] = ($service.Status -eq "Running")
            }
            else {
                Log-InfoMessage "`t[$currentAttempt/$attempts] service: $serviceName does not exist yet"
            }
        }

        $inWaitingState = $servicesState.ContainsValue($false) -eq $true

        if ($inWaitingState -eq $true) {
            Log-InfoMessage "`t[$currentAttempt/$attempts] waiting $timeoutInSeconds seconds..."
            Start-Sleep -Seconds $timeoutInSeconds
        }
        else {
            Log-InfoMessage "`tall services are running, continue install..."
            break
        }

        $currentAttempt++
    }

    if ($inWaitingState -eq $true) {
        $fullTimeout = $attempts * $timeoutInSeconds
        throw "Entered timout of $fullTimeout seconds while waiting for services being running: $servicesLogString"
    }
}

function Get-PipelineFeaturesHash($featuresFilePath) {
    $features = (Get-Content -Raw -path $featuresFilePath) | ConvertFrom-Json

    return $features
}

function Get-PipelineFeatureStatus($featureName) {
    $result = $false

    $featuresFilePath = Get-PipelineFeaturesFilePath

    if (Test-Path $featuresFilePath ) {
        Log-InfoMessage "`tReading features.json: $featuresFilePath"

        $featuresHash = Get-PipelineFeaturesHash $featuresFilePath

        Log-InfoMessage "`tChecking 'status' for feature: $featureName"
        if ($featuresHash.features."$featureName".status -eq "enabled") {
            Log-InfoMessage "`t - feature [$featureName] enabled"
            $result = $true
        }
        else {
            Log-InfoMessage "`t - feature [$featureName] is not enabled"
        }

    }
    else {
        Log-InfoMessage "`tPipeline features.json file is missing: $featuresFilePath"
    }

    return $result
}

function Get-WindowsAgentFolder {
    return "C:\windowsagents"
}

function Get-PipelineFeaturesFilePath {
    return "C:\Windows\Temp\features.json"
}

function Install-CodeDeployAgent {
    Param(
        [Parameter(Mandatory = $False)]
        [String]$msiPath
    )

    if ([String]::IsNullOrEmpty($msiPath)) {
        $msiPath = ((Get-WindowsAgentFolder) + "\codedeploy-*.msi")
        Log-InfoMessage "`t - using default agent path: $msiPath"
        $msiPath = Resolve-Path $msiPath
    }
    else {
        Log-InfoMessage "`t - using custom agent path: $msiPath"
    }

    Log-InfoMessage "`t - resolved path: $msiPath"
    if ([String]::IsNullOrEmpty($msiPath) -or !(Test-Path $msiPath)) {
        $errorMessage = "Cannot find path: $msiPath"

        Log-InfoMessage $errorMessage
        throw $msiPath
    }

    Log-InfoMessage  "`t - installing MSI: $msiPath log path: $msiInstallLogPath"
    $process = Start-Process msiexec.exe -ArgumentList "/I $msiPath /quiet /l $msiInstallLogPath" -PassThru -Wait
    $processExitCode = $process.ExitCode

    Log-InfoMessage "`t - processed exit code was: $processExitCode"

    if ($processExitCode -ne 0) {
        $errorMessage = "- exit code was not 0, failing: $processExitCode"

        Log-InfoMessage $errorMessage
        throw $errorMessage
    }
}

function Execute-CodeDeployInstall {

    Param(
        [Parameter(Mandatory = $False)]
        [String]$msiPath
    )

    $featureEnabled = Get-PipelineFeatureStatus "codedeploy"

    if ($featureEnabled -eq $true) {

        $serviceName = "codedeployagent"
        $msiInstallLogPath = "$env:TEMP\codedeploy-agent-install.log"

        Log-InfoMessage "Configuring CodeDeploy agent..."

        Log-InfoMessage "`t - checking if service exists: $serviceName"
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

        if ($service -eq $null) {
            Log-InfoMessage "Cannot find service: $serviceName, trying to install from MSI"
            Install-CodeDeployAgent $msiPath
        }
        else {
            Log-InfoMessage "Service: $serviceName already installed"
        }

        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

        if ($service -eq $null) {
            $errorMessage = "Cannot find service: $serviceName after MSI install"
            Log-InfoMessage $errorMessage
            throw $errorMessage
        }

        Log-InfoMessage "`t - updating service startup type to Automatic"
        Set-Service $serviceName -StartupType Automatic

        Log-InfoMessage "`t - checking state of the service: $serviceName"
        $serviceStatus = $service.Status

        if ($serviceStatus -eq "Running" ) {
            Log-InfoMessage "`t - service [$serviceName] is runnning"
        }
        else {
            Log-InfoMessage "`t - service [$serviceName] is NOT runnning: [$serviceStatus]. Trying to start..."
            Start-Service $serviceName

            Log-InfoMessage "CHecking final state of the service"
            $service = Get-Service -Name $serviceName

            Log-InfoMessage "`t - service [$serviceName] state is: $($service.Status)"

            if ($service.Status -ne "Running") {
                $errorMessage = "Cannot start service: $serviceName"
                Log-InfoMessage $errorMessage
                throw $errorMessage
            }
        }

        Log-InfoMessage "Configuring CodeDeploy completed!"
    }
}

function Execute-DataDogInstall($proxyHostName, $proxyPort) {

    if (Test-Path C:\Windows\Temp\features.json) {
        $features = (Get-Content  -Raw -path C:\Windows\Temp\features.json) | ConvertFrom-Json

        if ($features.features.datadog.status -eq "enabled") {

            if ($features.features.datadog.apikey) {
                Log-InfoMessage "Installing and configuring Datadog agent"
                Log-InfoMessage "`t - proxyHostName: $proxyHostName"
                Log-InfoMessage "`t - proxyPort: $proxyPort"

                $ddagentfile = (get-item  C:\windowsagents\ddagent-cli*.msi).FullName

                Log-InfoMessage "Waiting for SSM Agent to complete the install"
                if (Get-Process "msiexec" -ErrorAction SilentlyContinue) {
                    Wait-Process -Name msiexec -Timeout 900
                }

                $exitCode = (Start-Process "msiexec" -ArgumentList "/qn /i $ddagentfile" -Wait -Passthru).ExitCode

                # Retry the install
                if ($exitCode) {
                    $installCount = 1
                    Log-InfoMessage "`tInstallation of Datadog failed. $exitCode"
                    while ($installCount -lt 4) {
                        if (!($exitCode)) {
                            break
                        }
                        Log-InfoMessage "`tRetrying the installation: $installCount out of 3"
                        Get-Process "msiexec" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                        $exitCode = (Start-Process "msiexec" -ArgumentList "/qn /i $ddagentfile" -Wait -Passthru).ExitCode
                        $installCount++
                    }
                }

                if ($exitCode) { Log-InfoMessage "`tFailed to install Datadog Agent, error code: $exitCode" }

                Log-InfoMessage "`tStopping Datadog Agent prior to configuration"
                Get-Service DatadogAgent | Stop-Service -force -ErrorAction SilentlyContinue

                $ddconfig = "dd_url: https://app.datadoghq.com" + "`n" + "api_key: " + $features.features.datadog.apikey + "`n" + "log_to_event_viewer: no" + "`n" + "proxy:" + "`n" + " proxy_host: $proxyHostName" + "`n" + " proxy_port: $proxyPort" + "`n" + "process_config:" + "`n" + " enabled: 'true'"

                Log-InfoMessage "`tCreating new datadog configuration file"
                New-Item C:\ProgramData\Datadog\datadog.yaml -type file -force -value $ddconfig

                Log-InfoMessage "`tStarting Service after configuration"
                if ((Get-Service DatadogAgent).Status -eq 'Running') {
                    $lastCode = 0
                }
                else {
                    try {
                        Get-Service DatadogAgent | Start-Service -ErrorAction SilentlyContinue
                        $lastCode = 0
                    }
                    catch {
                        Log-InfoMessage "`tError starting Datadog Agent service"
                    }
                }

                $lastCode = $LastExitCode
                if ($LastExitCode) { throw "LastExitCode: $lastCode - Unable to start DatadogAgent agent" }

            }
            else {
                Log-InfoMessage "`tDatadog status enabled, however the API key is missing - The agent will not be installed."
            }
        }
        else {
            Log-InfoMessage "`tDatadog status not enabled - The agent will not be installed."
        }

    }
    else {
        Log-InfoMessage "`tPipeline features.json file is missing - The Datadog agent will not be installed."
    }

}

function Execute-SplunkInstall($environment) {
    $splunk_index = if ($environment -eq "NonProduction") { "qcp_win_nonprod" } else { "qcp_win_prod" }
    $splunk_add_on_inputs = if ($environment -eq "NonProduction") { "qcp_win_nonprod_inputs" } else { "qcp_win_prod_inputs" }

    $oldInputFilePath = "C:\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.conf"
    $outputFilePath = "C:\Program Files\SplunkUniversalForwarder\etc\system\local\outputs.conf"
    $oldserverconfFilePath = "C:\Program Files\SplunkUniversalForwarder\etc\system\local\server.conf"
    $oldInputFilePathapps = "C:\Program Files\SplunkUniversalForwarder\etc\apps\Splunk_TA_Windows\local\inputs.conf"
    $inputFilePath = "C:\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.txt"
    $serverFilePath = "C:\Program Files\SplunkUniversalForwarder\etc\system\local\server.txt"
    $inputFilePathapps = "C:\Program Files\SplunkUniversalForwarder\etc\apps\Splunk_TA_Windows\local\inputs.txt"
    $splunkoutputaddon = "C:\Program Files\SplunkUniversalForwarder\etc\apps\qcp_uf_win_outputs\default\outputs.conf"
    $splunkinputaddon = "C:\Program Files\SplunkUniversalForwarder\etc\apps\$splunk_add_on_inputs\default\inputs.conf"
    $deploymentclientFilePath = "C:\Program Files\SplunkUniversalForwarder\etc\system\default\deploymentclient.txt"
    $splunkInputsPath = "C:\Windows\Temp\splunkInputs.txt"
    $splunkInputsPathapps = "C:\Windows\Temp\splunkappInputs.txt"
    $splunkdeploymentclientPath = "C:\Windows\Temp\deploymentclient.txt"
    $splunkserverFilePath = "C:\Windows\Temp\server.txt"

    New-Item -Path "C:\Program Files\SplunkUniversalForwarder\etc\apps\qcp_uf_win_outputs\default" -ItemType Directory
    New-Item -Path "C:\Program Files\SplunkUniversalForwarder\etc\apps\$splunk_add_on_inputs\default" -ItemType Directory

    $file = Get-Content -Path $splunkInputsPath
    $file -replace 'qcp_win_prod', $splunk_index | Out-File $splunkInputsPath

    $file = Get-Content -Path $splunkInputsPathapps
    $file -replace 'qcp_win_prod', $splunk_index | Out-File $splunkInputsPathapps

    Log-InfoMessage "`tCreating new inputs.conf"
    if (Test-Path $oldInputFilePath)
        {
            Remove-Item -path $oldInputFilePath -force
        }
    #Remove-Item -path $oldInputFilePath -force
    Remove-Item -path $oldInputFilePathapps -force
    Remove-Item -path $oldserverconfFilePath -force
    $splunkRegId = $pipeline_Ams + "-" + $pipeline_Qda + "-" + $pipeline_As + "-" + $pipeline_Ase + "-" + $ComputerName
    New-Item $inputFilePath -type file -force -value "[default]`r`nhost = $splunkRegId`r`n`r`n"
    New-Item $deploymentclientFilePath -type file -force -value "[deployment-client]`r`nclientName = $splunkRegId`r`n`r`n"

    Log-InfoMessage "`tConfiguring inputs.conf"
    Add-Content -Path $inputFilePath -Value (Get-Content $splunkInputsPath)
    Add-Content -Path $inputFilePathapps -Value (Get-Content $splunkInputsPathapps)
    Add-Content -Path $serverFilePath -Value (Get-Content $splunkserverFilePath)
    Add-Content -Path $deploymentclientFilePath -Value (Get-Content $splunkdeploymentclientPath)
    $lastCode = $LastExitCode
    if ($LastExitCode) { throw "LastExitCode: $lastCode - Unable to copy required static contents for Splunk Logging" }

    Rename-Item -path $inputFilePath -newname inputs.conf
    Rename-Item -path $inputFilePathapps -newname inputs.conf
    Rename-Item -path $deploymentclientFilePath -newname deploymentclient.conf
    Rename-Item -path $serverFilePath -newname server.conf

    Copy-Item -Path $outputFilePath -Destination $splunkoutputaddon -Force
    Copy-Item -Path $oldInputFilePathapps -Destination $splunkinputaddon -Force

    Log-InfoMessage "`tUpdating SplunkForwarder service start type..."
    Set-Service SplunkForwarder -StartupType 'automatic'
    $lastCode = $LastExitCode
    if ($LastExitCode) { throw "LastExitCode: $lastCode - Unable to set SplunkForwarder to StartupType 'automatic'" }

    Log-InfoMessage "`tStarting SplunkForwarder service..."
    Start-Service SplunkForwarder
    $lastCode = $LastExitCode
    if ($LastExitCode) { throw "LastExitCode: $lastCode - Unable to start SplunkForwarder service" }
}

function Execute-CleaningUp($files) {
    foreach ($file in $files ) {
        Log-InfoMessage "`t Deleting file: $file"
        try {
            Remove-Item $file -Force -ErrorAction SilentlyContinue -Recurse -Confirm:$false
        }
        catch {
            Log-InfoMessage "ERROR while deleting file: $file - $_"
        }
    }
}

function Execute-CleaningUpSsmParameter($ssmPlatformSecretPath, $instanceId) {
    $ssmParameterFullPath = $ssmPlatformSecretPath + "/" + $instanceId + "/"
    $results = (Get-SSMParametersByPath -MaxResult $SSM_Param_Max_result -Path $ssmParameterFullPath -WithDecryption 1)
    Foreach ($ssmParameter in $results) {
        try {
            Remove-SSMParameter -Name $ssmParameter.Name -Force
        }
        catch {
            Log-InfoMessage "ERROR while cleanup SSM parameter: $_"
        }
    }
}

function Get-SafeComputerName($instanceId) {
    $result = $instanceId

    if ($instanceId.Length -eq 19) {
        $result = "q" + $instanceId.subString(5)
    }

    Log-InfoMessage "`tReturned safe computer name: $result for instanceId: $instanceId"

    return $result
}

function Execute-CfnInit($Region, $StackId, $MetadataResource, $configSet) {

    $exitCode = (Start-Process "cfn-init.exe" -ArgumentList "-v --region $Region --stack $StackId --resource $MetadataResource --configsets $configSet" -Wait -Passthru).ExitCode
    if ($exitCode) { throw "LastExitCode: $exitCode - Failed to execute cfn-init Deploy step" }

    # Forcing delay in case user specified waitAfterCompletion: forever, breaking signalling
    Start-Sleep 10
}

function Execute-CfnSignal($result, $Region, $StackId, $ResourceToSignal) {
    cfn-signal.exe -e $result --region $Region --stack $StackId --resource $ResourceToSignal
}

# actual bake/deploy stages
function Process-DeployStages() {

    Param (
        [Parameter(Mandatory = $True)]
        [int]$Stage,

        [Parameter(Mandatory = $True)]
        [string]$ResourceToSignal,

        [Parameter(Mandatory = $True)]
        [string]$ComputerName,

        [Parameter(Mandatory = $True)]
        [string]$domain,

        [Parameter(Mandatory = $True)]
        [string]$Region,

        [Parameter(Mandatory = $True)]
        [string]$StackId,

        [Parameter(Mandatory = $True)]
        [string]$MetadataResource,

        [Parameter(Mandatory = $True)]
        [string]$WindowsOU,

        [Parameter(Mandatory = $True)]
        [string]$DeploymentEnv,

        [Parameter(Mandatory = $True)]
        [string]$TrenddsmUrl,

        [Parameter(Mandatory = $True)]
        [string]$TrendPolicyName,

        [Parameter(Mandatory = $True)]
        [string]$Proxy,

        [Parameter(Mandatory = $True)]
        [string]$SsmPlatformSecretPath,

        [Parameter(Mandatory = $True)]
        [string]$logFile
    )

    # required for DataDog agent deployment
    $ProxyHostName = [regex]::match($Proxy, '^http://(.*):([0-9]+)$' ).Groups[1].value
    $ProxyPort = [regex]::match($Proxy, '^http://(.*):([0-9]+)$' ).Groups[2].value

    if ($Stage -lt 2) {
        Log-InfoMessage "Running Stage $([int]++$Stage): Checking if the computername $ENV:ComputerName is correct"
        Set-DeployStage $Stage

        if ($env:COMPUTERNAME -ne $ComputerName) {
            Log-InfoMessage "Renaming computer $ENV:ComputerName to $ComputerName"
            Flush-LogsToS3 $logFile

            Rename-Computer -NewName $ComputerName -Restart -Force
            Log-InfoMessage "Successfully renamed computer $ENV:ComputerName to $ComputerName"

            exit 0
        }
        else {
            Log-InfoMessage "Computer $ENV:ComputerName is named correctly"
            Flush-LogsToS3 $logFile
        }
    }
    else { Log-InfoMessage "Skipping Stage 2 - Computer $ENV:ComputerName named correctly" }

    if ($Stage -lt 3) {
        Log-InfoMessage "Running Stage $([int]++$Stage): Checking $domain ActiveDirectory domain membership"
        Set-DeployStage $Stage

        if (!$Domain) {
            throw "No active directory domain was specified."
        }
        elseif (!(Get-PartOfDomain)) {

            $username = $domain + "\" + ( Read-SSMParameter $SsmPlatformSecretPath $instanceId "bamboo_ad_join_user" )
            $password = ( Read-SSMParameter $SsmPlatformSecretPath $instanceId "bamboo_ad_join_password" ) | ConvertTo-SecureString -asPlainText -Force
            if ($username -and $password) {
                $credential = New-Object System.Management.Automation.PSCredential($username, $password)

                $params = @{
                    DomainName = $domain
                    Credential = $credential
                }

                # if Windows OU is specified, add OUPath to Add-Computer parameters
                if ($WindowsOU -and ($WindowsOU -ne "@default")) {
                    Log-InfoMessage "Using OU container $WindowsOU"
                    $params.Add('OUPath', $WindowsOU)
                }
                else {
                    Log-InfoMessage "Using default OU container"
                }

                Log-InfoMessage "Adding computer $ComputerName to $domain"
                Flush-LogsToS3 $logFile

                Add-Computer @params -Restart -Force
                Log-InfoMessage "Successfully added computer $ComputerName to $domain"
                Stop-Transcript

                exit 0
            }
            else {
                throw "Unable to join $domain ActiveDirectory domain. The Username/Password is empty."
            }
        }
        else {
            Log-InfoMessage "Computer is already joined to $domain ActiveDirectory domain"
            Flush-LogsToS3 $logFile
        }
    }
    else { Log-InfoMessage "Skipping Stage 3 - ActiveDirectory domain join " }

    if ($Stage -lt 4) {
        try {
            Log-InfoMessage "Running Stage $([int]++$Stage): Running deploy time SOE configuration"
            Set-DeployStage $Stage

            Log-InfoMessage "Configuring Users"
            $admin = Get-BambooVariable 'bamboo_ad_security_group_admin*'
            $user = Get-BambooVariable 'bamboo_ad_security_group_user*'

            Execute-AddToLocalGroup "Remote Desktop Users" "$Domain\$admin"
            Execute-AddToLocalGroup "Remote Desktop Users" "$Domain\$user"
            Execute-AddToLocalGroup "administrators" "$Domain\$admin"
            Execute-AddToLocalGroup "users" "$Domain\$user"

            $adminUser = Get-LocalUser | Where-Object { $_.Name -eq "qcpadmin" }
            if ( -not $adminUser) {
                Log-InfoMessage "Renaming Administrator account to QCPAdmin"
                Rename-LocalUser -Name "Administrator" -Newname "QCPAdmin"
            }
            else {
                Log-InfoMessage "qcpadmin already exists"
            }

            $guestUser = Get-LocalUser | Where-Object { $_.Name -eq "QCPGuest" }
            if ( -not $guestUser) {
                Log-InfoMessage "Renaming GuestUser account to QCPGuest"
                Rename-LocalUser -Name "Guest" -Newname "QCPGuest"
            }
            else {
                Log-InfoMessage "QCPGuest already exists"
            }

            Execute-DisableUser "qcpadmin"

            Log-InfoMessage "Configuring permissions on the WindowsAgents directory"
            Execute-GrantFolderPermissions 'C:\WindowsAgents' 'Everyone:(OI)(CI)F'

            Log-InfoMessage "Configuring DataDog agent"
            Execute-DataDogInstall $ProxyHostName $ProxyPort

            Log-InfoMessage "Configuring CodeDeploy agent"
            Execute-CodeDeployInstall

            Log-InfoMessage "Configuring Splunk agent"
            Execute-SplunkInstall $DeploymentEnv

        }
        catch {
            Log-InfoMessage "ERROR on SOE configuration stage: $_"
            throw $_
        }
        finally {
            Log-InfoMessage "Clean up the SSM Parameters"
            Execute-CleaningUpSsmParameter $SsmPlatformSecretPath $instanceId

            Flush-LogsToS3 $logFile
        }

    }
    else { Log-InfoMessage "Skipping Stage 4" }

    if ($Stage -lt 5) {
        Log-InfoMessage "Running Stage $([int]++$Stage): Deploy time user scripts"
        Set-DeployStage $Stage

        Log-InfoMessage "Executing cfn-init Deploy step (region=$Region; stack=$StackId; resource=$MetadataResource); configSet=Deploy"
        Execute-CfnInit $Region `
            $StackId `
            $MetadataResource `
            'Deploy'

        Flush-LogsToS3 $logFile

    }
    else { Log-InfoMessage "Skipping Stage 5" }

    if ($Stage -lt 6) {
        Log-InfoMessage "Running Stage $([int]++$Stage): Clean-up"
        Set-DeployStage $Stage

        Log-InfoMessage "Cleaning up, fetching files..."
        $cleanupFiles = Get-DeployCleanupFiles

        Log-InfoMessage "Found $($cleanupFiles.Count) files."
        Execute-CleaningUp $cleanupFiles

        Log-InfoMessage "Clean up the SSM Parameters"
        Execute-CleaningUpSsmParameter $SsmPlatformSecretPath $instanceId

        Log-InfoMessage "Signalling CloudFormation with cfn-signal (error=0; region=$Region; stack=$StackId; resource=$ResourceToSignal)"
        Execute-CfnSignal 0 `
            $Region `
            $StackId `
            $ResourceToSignal

        Flush-LogsToS3 $logFile

    }
    else { Log-InfoMessage "Skipping Stage 6" }
}
