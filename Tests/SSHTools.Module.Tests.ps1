#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# -ForEach data must exist at discovery time, so it is built here (and again in
# BeforeAll for the run phase). The manifest's FunctionsToExport is the source of truth.
BeforeDiscovery {
    $ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'SSHTools.psd1'
    $ExpectedFunctions = @((Import-PowerShellDataFile -Path $ManifestPath).FunctionsToExport)
}

BeforeAll {
    $script:RepoRoot     = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:RepoRoot 'SSHTools.psd1'
    Import-Module $script:ManifestPath -Force
    $script:ExpectedFunctions = @((Import-PowerShellDataFile -Path $script:ManifestPath).FunctionsToExport)
}

Describe 'SSHTools module' {

    Context 'Manifest' {
        It 'is a valid module manifest' {
            { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } | Should -Not -Throw
        }

        It 'declares an explicit list of functions to export (no wildcard)' {
            $script:ExpectedFunctions | Should -Not -BeNullOrEmpty
            $script:ExpectedFunctions | Should -Not -Contain '*'
        }
    }

    Context 'Loaded module' {
        It 'runtime exports match the manifest declaration' {
            (Get-Command -Module SSHTools -CommandType Function).Name | Sort-Object |
                Should -Be ($script:ExpectedFunctions | Sort-Object)
        }

        It 'does not export the private dispatcher' {
            Get-Command -Module SSHTools -Name 'Invoke-SSHToolsScriptBlock' -ErrorAction SilentlyContinue |
                Should -BeNullOrEmpty
        }
    }

    Context 'Source files' {
        It 'every .ps1 parses without syntax errors' {
            $files = Get-ChildItem -Path (Join-Path $script:RepoRoot 'Public'), (Join-Path $script:RepoRoot 'Private') -Filter *.ps1
            foreach ($file in $files) {
                $errors = $null
                [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors) | Out-Null
                $errors | Should -BeNullOrEmpty -Because "$($file.Name) should have no parse errors"
            }
        }

        It 'defines one public function per file matching the file name' {
            Get-ChildItem -Path (Join-Path $script:RepoRoot 'Public') -Filter *.ps1 | ForEach-Object {
                Get-Command -Module SSHTools -Name $_.BaseName -ErrorAction SilentlyContinue |
                    Should -Not -BeNullOrEmpty -Because "$($_.Name) should define function $($_.BaseName)"
            }
        }
    }

    Context 'Help and parameters' {
        It '<_> has a synopsis' -ForEach $ExpectedFunctions {
            (Get-Help $_ -ErrorAction SilentlyContinue).Synopsis.Trim() | Should -Not -BeNullOrEmpty
        }

        It '<_> supports -ComputerName, -Session, and -Credential' -ForEach $ExpectedFunctions {
            $params = (Get-Command $_).Parameters
            $params.Keys | Should -Contain 'ComputerName'
            $params.Keys | Should -Contain 'Session'
            $params.Keys | Should -Contain 'Credential'
        }

        It '<_> keeps ComputerName and Session in different parameter sets' -ForEach $ExpectedFunctions {
            $cmd          = Get-Command $_
            $computerSets = $cmd.Parameters['ComputerName'].ParameterSets.Keys
            $sessionSets  = $cmd.Parameters['Session'].ParameterSets.Keys
            ($computerSets | Where-Object { $sessionSets -contains $_ }) | Should -BeNullOrEmpty
        }
    }
}
