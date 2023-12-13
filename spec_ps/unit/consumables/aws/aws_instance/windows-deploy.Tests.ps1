
$currentDir = (Get-Item -Path ".\" -Verbose).FullName

$scriptPath = "$currentDir/lib/consumables/aws/aws_instance/windows-deploy.ps1"
$sharedFuntionsPath = "$currentDir/spec_ps/shared/PesterHelper.ps1"
$prosperoPath = "$currentDir/lib/consumables/aws/common/windows/Pipeline.Prospero.ps1"

. $sharedFuntionsPath

Describe 'windows-deploy.ps1' {

    Context 'Syntax validity'  {
        It 'Should be valid PS script' {
            $path = Get-ValidScriptFile $scriptPath 
    
            Test-Syntax -Path $path | Should -Be $true
        }
    }

    Context 'Parameters' {
       
        It 'Set-ExecutionPolicy' {
            $content = Get-ScriptContent $scriptPath 
         
            $content.Contains("Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue") | Should -Be $true
        }

        It '$ErrorActionPreference = "Stop"' {
            $content = Get-ScriptContent $scriptPath 
            
            $content.Contains('$ErrorActionPreference = "Stop"') | Should -Be $true
        }

        It 'Should have persist = true' {
            $content = Get-ScriptContent $scriptPath 
            
            $content.Contains('<persist>true</persist>') | Should -Be $true
        }
    
        It 'Should have runAsLocalSystem = true' {
            $content = Get-ScriptContent $scriptPath 
            
            $content.Contains('<runAsLocalSystem>true</runAsLocalSystem>') | Should -Be $true
        }
    
        It 'Should have default parameters' {
            $content = Get-ScriptContent $scriptPath 
            
            $defaultParams = @(
                '$MetadataResource = "<| MetadataResource |>"',
                '$ResourceToSignal = "<| ResourceToSignal |>"',
                '$StackId = "<| StackId |>"',
                '$Region = "<| Region |>"',
                '$domain = "<| Domain |>"',
                '$DeploymentEnv = "<| DeploymentEnv |>"',
                '$WindowsOU = "<| WindowsOU |>"',
                '$Proxy = "<| AwsProxy |>"',
                '$NoProxy = "<| NoProxy |>"',
                '$TrenddsmUrl = "<| TrenddsmUrl |>"'
                '$TrendPolicyName = "<| TrendPolicyName |>"'
            )
    
            foreach($defaultParam in $defaultParams) {
                Log-Debug "`tTesting parameter: $defaultParam"
                $content.Contains($defaultParam) | Should -Be $true
            }
        }
    }

    Context 'Execution' {
       
        function Mock-Execution() {

            function Get-SSMParametersByPath() {}
            function Execute-CleaningUpSsmParameter() {}
            function Invoke-LMFunction() {}
            function Get-LocalUser() {}
            function Rename-LocalUser() {}
            function Read-SSMParameter() {}

            function Get-ProsperoPath() {}
            function Log-Message() {}
            
            function Set-DeployStage() {  }
            
            function Write-S3Object() {}
            function Stage1-Sleep {}

            Mock -CommandName Set-ExecutionPolicy  -MockWith {}
            Mock -CommandName Invoke-RestMethod  -MockWith { return 'aws-my-instance-id'}
            
            Mock -CommandName New-Item -MockWith {}
            Mock -CommandName Copy-Item -MockWith {}
            Mock -CommandName Remove-Item -MockWith {}
            
            Mock -CommandName Write-S3Object -MockWith {}
                 
            Mock -CommandName Start-Process -MockWith { return 0 }

            Mock -CommandName Get-ProsperoPath -MockWith { return $prosperoPath }

            Mock -CommandName Set-DeployStage -MockWith {  }
            Mock -CommandName Stage1-Sleep -MockWith {  }

            Mock -CommandName Log-Message -MockWith { param ($msg)  Log-Debug("`t`t$msg") }

            Mock -CommandName Get-SSMParametersByPath -MockWith {}
            Mock -CommandName Execute-CleaningUpSsmParameter -MockWith {}
            Mock -CommandName Execute-CleaningUpSsmParameter -MockWith {}
            Mock -CommandName Invoke-LMFunction -MockWith {}
            Mock -CommandName Get-LocalUser -MockWith {}
            Mock -CommandName Rename-LocalUser -MockWith {}
            Mock -CommandName Read-SSMParameter -MockWith { return "1" }
        }

        function Test-ScriptInclude($contentPath) {
            Log-Warn "`tIncluding file: $contentPath"

            $trace = (. $contentPath)
            $exitCode = $LASTEXITCODE

            Log-Warn "`tLASTEXITCODE: $exitCode"
            Log-Warn "`tTRACE: $trace"

            $exitCode | Should -Be 0
        }

        It 'Default - Stage 0' {
            $contentPath = Get-ValidScriptFile $scriptPath 
            
            Mock-Execution

            function Rename-Computer() {}   
            function Get-DeployStage() { return 0 }
             
            Mock -CommandName Get-DeployStage -MockWith { return 0 }
            
            Test-ScriptInclude $contentPath
        }

        It 'Default - Stage 1' {
            $contentPath = Get-ValidScriptFile $scriptPath 
            
            function Rename-Computer() {}
            function Get-DeployStage() { return 0 }
            
            Mock-Execution
            Mock -CommandName Get-DeployStage -MockWith { return 1 }
           
            Test-ScriptInclude $contentPath
        }

        It 'Default - Stage 2: part of domain' {
            $contentPath = Get-ValidScriptFile $scriptPath 
            
            function Rename-Computer() {}
            function Get-DeployStage() { return 0 }
            function Log-LogMessage() {}
            function Write-S3Object() {}
            function Get-PartOfDomain { return false }
            
            function Get-BambooVariable { return "" }
            function Execute-GrantFolderPermissions {}

            #function Execute-TrendMicroInstall {}
            function Execute-DataDogInstall {}
            function Execute-SplunkInstall {}

            function Execute-CfnInit {}

            Mock-Execution
            Mock -CommandName Get-DeployStage -MockWith { return 2 }
            Mock -CommandName Log-LogMessage -MockWith { param ($msg)  Log-Debug("`t`t$msg") }
            Mock -CommandName Get-PartOfDomain -MockWith { return $true  }
            
            Mock -CommandName Get-BambooVariable -MockWith { return "" }
            Mock -CommandName Execute-GrantFolderPermissions -MockWith {  }

            Mock -CommandName Execute-DataDogInstall -MockWith {  }
            Mock -CommandName Execute-SplunkInstall -MockWith {  }
          
            Mock -CommandName Execute-CfnInit -MockWith {  }
          
            Test-ScriptInclude $contentPath
        }

        It 'Default - Stage 2: not part of domain' {
            $contentPath = Get-ValidScriptFile $scriptPath 
            
            function Rename-Computer() {}
            function Get-DeployStage() { return 0 }
            function Log-LogMessage() {}
            function Write-S3Object() {}
            function Get-PartOfDomain { return false }
            function Add-Computer {}
            function Get-BambooVariable {}

            function Execute-CfnInit {}

            Mock-Execution
            Mock -CommandName Get-DeployStage -MockWith { return 2 }
            Mock -CommandName Log-LogMessage -MockWith { param ($msg)  Log-Debug("`t`t$msg") }
            Mock -CommandName Get-PartOfDomain -MockWith { return $false  }
            Mock -CommandName Get-BambooVariable -MockWith { param ($name) return "$name-value"  }
            
            Mock -CommandName Execute-CfnInit -MockWith {  }
          

            Test-ScriptInclude $contentPath
        }
       
    }

}