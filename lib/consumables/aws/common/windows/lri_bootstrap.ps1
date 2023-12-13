<#
.SYNOPSIS

    Long Running Instance Puppet bootstrap script for Microsoft Windows (2016 & 2012R2)

.DESCRIPTION

    This script is exeuted via the QCP Pipeline to bootstrap a Windows Long Running Instance from the QCP Puppet Master.

.PARAMETER PuppetMaster

    Specifies the Puppet Master server to bootstrap and register the node with


.PARAMETER PuppetEnvironment

    Specifies the Puppet environment to associate the node with. Please note that this value only functions when the PuppetDevelopment is set to true. 
    If set to false, the Puppet master associates the node with the correct long running environment.

.PARAMETER PuppetDevelopment

    Mark the build as a development build. This flag allows us to associate the instance with any Puppet environment for development purposes.

.EXAMPLE

    lri_bootstrap.ps1 -PuppetMaster productionpuppet1-e2kbdkqgcff6bgii.ap-southeast-2.opsworks-cm.io -PuppetEnvironment qcp_lri_nonproduction -PuppetDevelopment false

.LINK 
    The long Running Instance solution documentation can be found at the below location in confluence.
    https://confluence.qantas.com.au/display/QCP/Long+Running+Instances


.NOTES
    Please note that it has been observed that Puppet on Windows outputs special characters that trigger cfn-init.exe to fail with a utf8 related error.
    As such, when we trigger this script from cfn-init, we send all of it's output to a log file then ship the log file back up to S3 with the other
    log file artefacts.

    You can find out more about this issue in the below blog post.

    http://www.codeandcompost.com/post/cfn,-utf8-and-two-days-i%E2%80%99ll-never-get-back

#>

Param(
    [Parameter(Mandatory=$true)][string]$PuppetMaster,
    [Parameter(Mandatory=$true)][string]$PuppetEnvironment,
    [Parameter(Mandatory=$true)][string]$PuppetDevelopment
)
try
{

    #
    # Remove the SOE Puppet Agent package if it is found already.
    #
    Write-Host "Uninstalling the existing Puppet Agent"
    Uninstall-Package 'Puppet Agent (64-bit)' -Force

    # Delete any remnants of the original configuration files
    Write-Host "Deleting leftover Puppet-related files"
    Remove-Item "${env:ALLUSERSPROFILE}\PuppetLabs" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "${env:ProgramFiles}\Puppet Labs" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "${env:ProgramFiles(x86)}\Puppet Labs" -Recurse -Force -ErrorAction SilentlyContinue


    Write-Host "Bootstrapping LRI from $PuppetMaster"
    Write-Host "Configuring agent with environment $PuppetEnvironment and Development set to $PuppetDevelopment"

    # Download the puppet installation script from the master
    [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true};
    $webClient = New-Object System.Net.WebClient; 
    $webClient.DownloadFile("https://${PuppetMaster}:8140/packages/current/install.ps1", 'c:\puppet_install.ps1');

    Write-Host "Executing bootstrap script"
    c:\puppet_install.ps1 -PuppetServiceEnsure 'stopped'

    . C:\Windows\Context.ps1

    Write-Host "Configuring client cert in the Puppet configuration file"
    &  'C:\Program Files\Puppet Labs\Puppet\bin\puppet.bat' config set --section agent certname ${pipeline_Ams}-${pipeline_Qda}-${pipeline_As}-${pipeline_Ase}-$(hostname)

    Write-Host "Configuring environment in the Puppet configuration file"
    &  'C:\Program Files\Puppet Labs\Puppet\bin\puppet.bat' config set --section agent environment $PuppetEnvironment

    Write-Host "Configuring the Puppet extended attributes file"
    $csr_attrib = "extension_requests:`n"
    $csr_attrib += "  pp_environment: ${PuppetEnvironment}`n"

    if ( $PuppetDevelopment -eq "True" ) {
        $csr_attrib += "  pp_apptier: development`n"
    }

    Out-File -Encoding ascii -FilePath 'C:\ProgramData\PuppetLabs\puppet\etc\csr_attributes.yaml' -InputObject $csr_attrib

    # Apply the SOE in 3 Runs (We need to exit with 0 or 2 to mark it as a green build)

    $RUNCOUNT=0
    $DESIREDRUNS=3

    while ( $RUNCOUNT -ne $DESIREDRUNS ) {
        write-host "Running Puppet Agent : $RUNCOUNT of $DESIREDRUNS"
        & 'C:\Program Files\Puppet Labs\Puppet\bin\puppet.bat' agent -tov --detailed-exitcodes

        if ( $LASTEXITCODE -eq 0 ) {
            write-host "Puppet Run $RUNCOUNT returned zero - No longer need to run additional runs"
            break
        }
        $RUNCOUNT++
    }

    # Ensure that the last Puppet Run was (Zero or two) and fail if not.
    if ( $LASTEXITCODE -eq 2) {
            write-host "Last Puppet Run was not zero (Got $LASTEXITCODE)"
            $LASTEXITCODE=0
    }
    if ( $LASTEXITCODE -ne 0 ) {
            write-host "Last Puppet Run was not zero (Got $LASTEXITCODE) after $DESIREDRUNS tries. SOE Application failed. Exiting Build"
            exit $LASTEXITCODE
    }

}
catch [System.Exception]
{
    Write-Host "FAIL - Could not install Puppet Agent $_.Exception"
}
