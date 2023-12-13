function Get-ValidScript($scriptPath) {
    $content = Get-Content $scriptPath

    $replaceStirngs = @(
        "<powershell>",
        "</powershell>",
        "<persist>true</persist>",
        "<runAsLocalSystem>true</runAsLocalSystem>" 
    )

    foreach($replace in $replaceStirngs) {
        $content = $content.Replace($replace, "")
    }
    
    return $content 
}

function Get-ValidScriptFile($scriptPath) {
    $validContent = Get-ValidScript $scriptPath 
    $tmpFilePath = [System.IO.Path]::GetTempFileName()

    $tmpFilePath = $tmpFilePath + ".ps1"

    $validContent >> $tmpFilePath
    chmod 755 $tmpFilePath

    return $tmpFilePath 
}

function Get-ScriptContent($scriptPath) {
    Get-Content $scriptPath
}

function Test-Syntax
{
    [CmdletBinding(DefaultParameterSetName='File')]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='File')]
        [string]$Path, 

        [Parameter(Mandatory=$true, ParameterSetName='String')]
        [string]$Code
    )

    $Errors = @()
    if($PSCmdlet.ParameterSetName -eq 'String'){
        [void][System.Management.Automation.Language.Parser]::ParseInput($Code,[ref]$null,[ref]$Errors)
    } else {
        [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$null,[ref]$Errors)
    }

    return [bool]($Errors.Count -lt 1)
}

function Log-TraceMessage($msg, $color) {
    Write-Host $msg -Fore $color
}

function Log-Info($msg) {
    Log-TraceMessage $msg "Green"
}

function Log-Warn($msg) {
    Log-TraceMessage $msg "Yellow"
}

function Log-Debug($msg) {
    Log-TraceMessage $msg "Blue"
}