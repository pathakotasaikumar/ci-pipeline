# Global PowerShell profile for QCP
# Profile is used to import QCP specific settings (Proxy) and context variables
# Set Proxy setting variables based on the environment variable

$AWS_PROXY=$ENV:HTTP_PROXY

# Source context variables
. $ENV:SystemRoot\context.ps1

#Read bamboo vars and set AWS proxy is available
$AWS_PROXY -match "http://(?<hostname>[a-zA-Z.]+):(?<port>\d+)" | Out-Null
$HTTP_PROXY=$Matches['hostname']; $HTTP_PROXY_PORT=$Matches['port']

Set-AWSProxy -Hostname $HTTP_PROXY -Port $HTTP_PROXY_PORT

# Ensure HelperScripts module is loaded
Import-Module HelperScripts -DisableNameChecking