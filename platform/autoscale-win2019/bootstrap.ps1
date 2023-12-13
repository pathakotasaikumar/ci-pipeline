if ((Get-WindowsFeature Web-Server).Installed) {
  Write-Output "INFO: IIS is already installed"

} else {

  try {
    Add-WindowsFeature web-server,web-mgmt-tools
    Write-Output "INFO: IIS Successfully installed"
  } catch { throw "WARNING: Unable to install IIS" }
}


if(Get-Website "Default Web Site") {
  try {
  Get-website -Name "Default Web Site" | Remove-Website
  Write-Output "INFO: Removed default website"
  } catch {
  Write-Output "WARNING: Unable to remove default website"
  }
}


$site_path = "$ENV:SystemDrive" + "\inetpub\testsite"

try {

  if(!(Test-Path $site_path)) {
    New-Item $site_path -Type directory
    Write-Output "INFO: Creating directory $site_path for new website"
  }

  if(!(Get-website "TestSite")) {
    New-WebSite -Name TestSite -Port 80 -PhysicalPath $site_path
    Write-Output "INFO: Created new test website"
  }

} catch { throw "WARNING: Unabled to add new website on drive $drive $_" }

if (! (Test-Path "$site_path\$pipeline_Component"))
{
    New-Item "$site_path\$pipeline_Component" -ItemType Directory
}

convertto-html -PostContent "This site was updated on component $pipeline_Component at <b>$(get-date)</b>" >> ($site_path +"\" + "$pipeline_Component\index.html")

$source_folder = "C:\Windows\temp\payload\context-include.ps1"
$destination_folder = "C:\Windows\temp\TmpDeployDir"

if (!(Test-Path -path $destination_folder)) {New-Item $destination_folder -Type Directory}


Copy-Item $source_folder -Destination $destination_folder