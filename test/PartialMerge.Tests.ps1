$moduleManifestName = 'PartialMerge.psd1'
$moduleManifestPath = "$PSScriptRoot\..\$moduleManifestName"


Describe "$moduleManifestName Tests" {
    Describe 'Module Manifest Tests' {
        It 'Passes Test-ModuleManifest' {
            Test-ModuleManifest -Path $moduleManifestPath | Should Not BeNullOrEmpty
            $? | Should Be $true
        }
    }

    Describe 'Module Function Tests' {
        BeforeAll {
            $sampleMofsPath = Join-Path -Path $PSScriptRoot -ChildPath 'SampleMofs'
            Import-Module -Name $moduleManifestPath -Force
        }

        AfterAll {
            Remove-Module -$ModuleManifestPath
        }

        Describe 'Get-ClientMofs' {
            BeforeAll {
                $outputMof = 'TestDrive:\CombindedMofs.mof'
                $referenceMofs = (Get-ChildItem -Path $sampleMofsPath -Include 'Mof*.mof' -Recurse).FullName
                $referenceSampleData = $referenceMofs | ForEach-Object -Process {[Microsoft.PowerShell.DesiredStateConfiguration.Internal.DscClassCache]::ImportInstances($PSItem, 4)}
                $mofData = Get-ClientMofs -MofFolder $sampleMofsPath -ClientName 'Mof*'
                $mergedMofs = Merge-ClientMofs -MofData $mofData
                Write-MergeMof -OutputFile TestDrive:\merge.mof -CombinedMofs $mergedMofs
                $referenceTypeNames = $referenceSampleData.CimClass | Select-Object -ExpandProperty CimClassName -Unique
                $testCases = @()
                foreach ($typeName in $referenceTypeNames)
                {
                    # Check all but OMI_ConfigurationDocument types, that is handled when written to a file
                    if ($typeName -ne 'OMI_ConfigurationDocument')
                    {
                        $testCases += @{TypeName = $typeName }
                    }
                }
            }

            Describe 'Get-ClientMofs' {
                It 'Should return a hashtable with the correct number of entries' {
                    $mofData.Count | Should -Be $referenceMofs.Count
                }
            }

            Describe 'Merge-ClientMofs' {
                It 'Should return same number of instances for type <TypeName>' -TestCases $testCases {
                    param (
                        [Parameter()]
                        $TypeName
                    )

                    # get typename count in $mergedMofs and $referenceSampleData
                    $mergedMofCount = $mergedMofs.Resources.InstanceType | Where-Object -FilterScript {$_ -eq $TypeName}
                    $referenceSampleDataCount = $referenceSampleData.CimClass.CimClassName | Where-Object -FilterScript {$_ -eq $TypeName}

                    #compare counts
                    $mergedMofCount.Count | Should -Be $referenceSampleDataCount.Count
                }
            }

            Describe 'Write-MergeMof' {
                BeforeAll {
                    Write-MergeMof -CombinedMofs $mergedMofs -OutputFile $outputMof
                    $newMof = (Get-ChildItem -Path $outputMof).FullName
                }

                It 'Should create valid mof' {
                    {$mergeImport = [Microsoft.PowerShell.DesiredStateConfiguration.Internal.DscClassCache]::ImportInstances($newMof, 4)} | Should -Not -Throw
                }

                It 'Should have only one OMI_ConfigurationDocument Instace in merged mof' {
                    $mergeImport = [Microsoft.PowerShell.DesiredStateConfiguration.Internal.DscClassCache]::ImportInstances($newMof, 4)
                    @(($mergeImport | Where-Object -FilterScript {$_.CimClass.CimClassName -eq 'OMI_ConfigurationDocument'})).Count | Should -BeExactly 1
                }

                It 'Should return same number of instances for type <TypeName>' -TestCases $testCases {
                    param (
                        [Parameter()]
                        $TypeName
                    )

                    # get typename count in $mergedMofs and $referenceSampleData
                    $mergedMofCount = $mergeImport.CimClass.CimClassName | Where-Object -FilterScript {$_ -eq $TypeName}
                    $referenceSampleDataCount = $referenceSampleData.CimClassName | Where-Object -FilterScript {$_ -eq $TypeName}

                    #compare counts
                    $mergedMofCount.Count | Should -Be $referenceSampleDataCount.Count
                }
            }
        }

    }
}
