
$currentDir = (Get-Item -Path ".\" -Verbose).FullName

$scriptPath = "$currentDir/lib/consumables/aws/common/windows/Pipeline.Prospero.ps1"
$sharedFuntionsPath = "$currentDir/spec_ps/shared/PesterHelper.ps1"

. $sharedFuntionsPath

Describe 'profile.ps1' {

    Context 'Syntax validity'  {
        It 'Should be valid PS script' {
            $path = Get-ValidScriptFile $scriptPath
    
            Test-Syntax -Path $path | Should -Be $true
        }
    }

    Context 'Syntax validity'  {
        It 'Should be valid PS script' {
            $path = Get-ValidScriptFile $scriptPath
    
            Test-Syntax -Path $path | Should -Be $true
        }
    }

    Context '.Get-DeployCleanupFiles' {
        It 'returns array of files' {
            $path = Get-ValidScriptFile $scriptPath
            . $path

            $result = Get-DeployCleanupFiles
    
            $result.Count | Should -Be 7
           
            $expectedPaths = @(
                'C:\Windows\Temp\bamboo-vars.conf',
                'C:\Windows\Temp\bamboo-vars.conf.bak',
                'C:\windowsagents',
                'C:\windowsagents.zip',
                'C:\Windows\Temp\platform_vars',
                'C:\Program Files\Amazon\Ec2ConfigService\sysprep2008.xml',
                'C:\Windows\Panther\unattend.xml'
            )

            foreach($expectedPath in $expectedPaths) {
                $result.Contains($expectedPath) | Should -Be $true
            }
        }
    }

    Context '.Get-DeployStage' {
        It 'returns 0' {
            $path = Get-ValidScriptFile $scriptPath
            . $path

            $result = Get-DeployStage
    
            $result | Should -Be 0
        }
    }

    Context '.Get-PipelineFeaturesFilePath' {
        It 'returns "C:\Windows\Temp\features.json"' {
            $path = Get-ValidScriptFile $scriptPath
            . $path

            $result = Get-PipelineFeaturesFilePath
    
            $result | Should -Be "C:\Windows\Temp\features.json"
        }

        It 'returns "C:\windowsagents"' {
            $path = Get-ValidScriptFile $scriptPath
            . $path

            $result = Get-WindowsAgentFolder
    
            $result | Should -Be "C:\windowsagents"
        }
    }

    Context '.Get-PipelineFeatureStatus' {
        It 'returns "false" on random feature' {
            $path = Get-ValidScriptFile $scriptPath
            . $path

            $result = Get-PipelineFeatureStatus "random-feature"
    
            $result | Should -Be $false
        }

        It 'returns "false" on random feature' {
            $path = Get-ValidScriptFile $scriptPath
            . $path

            $featuresString = " 
            {
                ""features"": {
                    ""codedeploy"": {
                        ""status"" : ""enabled""
                    }
                }
            }
            " 
          
            $featuresHash  = ConvertFrom-Json  $featuresString 
           
            Mock -CommandName Test-Path -MockWith { return $true }
            Mock -CommandName Get-PipelineFeaturesHash  -MockWith { return $featuresHash }

            Write-Host "Test data: $featuresString"
            $result = Get-PipelineFeatureStatus "non-existing-feature"
    
            $result | Should -Be $false
        }

        It 'returns "true" on enabled feature' {
            $path = Get-ValidScriptFile $scriptPath
            . $path

            $featuresString = " 
            {
                ""features"": {
                    ""codedeploy"": {
                        ""status"" : ""enabled""
                    }
                }
            }
            " 
          
            $featuresHash  = ConvertFrom-Json  $featuresString 
           
            Mock -CommandName Test-Path -MockWith { return $true }
            Mock -CommandName Get-PipelineFeaturesHash  -MockWith { return $featuresHash }

            Write-Host "Test data: $featuresString"
            $result = Get-PipelineFeatureStatus "codedeploy"
    
            $result | Should -Be $true
        }

        It 'returns "false" on disabled feature' {
            $path = Get-ValidScriptFile $scriptPath
            . $path

            $featuresString = " 
            {
                ""features"": {
                    ""codedeploy"": {
                        ""status"" : """"
                    }
                }
            }
            " 
          
            $featuresHash  = ConvertFrom-Json  $featuresString 
           
            Mock -CommandName Test-Path -MockWith { return $true }
            Mock -CommandName Get-PipelineFeaturesHash  -MockWith { return $featuresHash }

            Write-Host "Test data: $featuresString"
            $result = Get-PipelineFeatureStatus "codedeploy"
    
            $result | Should -Be $false
        }
    }
}