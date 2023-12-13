
Set-StrictMode -Version 'Latest'
$ErrorActionPreference = 'Stop'

Write-Host "[1/2] Sourcing context variables via ENV:SystemRoot"
# Source context variables
. $ENV:SystemRoot\context.ps1

Write-Host "[2/2] Sourcing context variables via c:\Windows\context.ps1"
# Source context variables
. c:\Windows\context.ps1

Write-Host "Sourcing context variables testing completed"

exit 0