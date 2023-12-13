
$currentDir = (Get-Item -Path ".\" -Verbose).FullName

$scriptPath = "$currentDir/lib/consumables/aws/common/windows/helperscripts.psm1"
$sharedFuntionsPath = "$currentDir/spec_ps/shared/PesterHelper.ps1"

. $sharedFuntionsPath

Describe 'helperscripts.ps1' {

    Context 'Syntax validity'  {
        It 'Should be valid PS script' {
            $path = Get-ValidScriptFile $scriptPath
    
            Test-Syntax -Path $path | Should -Be $true
        }
    }
}