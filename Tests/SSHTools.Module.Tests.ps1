#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot     = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $RepoRoot 'SSHTools.psd1'
    Import-Module $ManifestPath -Force

    $script:ExpectedFunctions = @(
        'Get-OpenSSHInstallation'
        'Install-OpenSSH'
        'Get-OpenSSHFirewallRule'
        'Set-OpenSSHFirewallRule'
        'Test-SSHDListening'
        'Backup-OpenSSHConfiguration'
        'Test-OpenSSHStrictModesPath'
        'Repair-OpenSSHPathPermission'
        'Restart-SSHDService'
    )
}

Describe 'SSHTools module' {

    Context 'Manifest' {
        It 'is a valid module manifest' {
            { Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop } | Should -Not -Throw
        }

        It 'exports exactly the expected functions in the manifest' {
            $manifest = Test-ModuleManifest -Path $ManifestPath
            $manifest.ExportedFunctions.Keys | Sort-Object |
                Should -Be ($ExpectedFunctions | Sort-Object)
        }
    }

    Context 'Loaded module' {
        It 'exports exactly the expected functions at runtime' {
            (Get-Command -Module SSHTools -CommandType Function).Name | Sort-Object |
                Should -Be ($ExpectedFunctions | Sort-Object)
        }

        It 'does not export the private dispatcher' {
            Get-Command -Module SSHTools -Name 'Invoke-SSHToolsScriptBlock' -ErrorAction SilentlyContinue |
                Should -BeNullOrEmpty
        }
    }

    Context 'Source files' {
        It 'every .ps1 parses without syntax errors' {
            $files = Get-ChildItem -Path (Join-Path $RepoRoot 'Public'), (Join-Path $RepoRoot 'Private') -Filter *.ps1
            foreach ($file in $files) {
                $errors = $null
                [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors) | Out-Null
                $errors | Should -BeNullOrEmpty -Because "$($file.Name) should have no parse errors"
            }
        }

        It 'defines one public function per file matching the file name' {
            Get-ChildItem -Path (Join-Path $RepoRoot 'Public') -Filter *.ps1 | ForEach-Object {
                Get-Command -Module SSHTools -Name $_.BaseName -ErrorAction SilentlyContinue |
                    Should -Not -BeNullOrEmpty -Because "$($_.Name) should define function $($_.BaseName)"
            }
        }
    }

    Context 'Help and parameters' {
        It '<_> has a synopsis' -ForEach $ExpectedFunctions {
            (Get-Help $_ -ErrorAction SilentlyContinue).Synopsis.Trim() | Should -Not -BeNullOrEmpty
        }

        It '<_> supports -ComputerName and -Session' -ForEach $ExpectedFunctions {
            $params = (Get-Command $_).Parameters
            $params.Keys | Should -Contain 'ComputerName'
            $params.Keys | Should -Contain 'Session'
            $params.Keys | Should -Contain 'Credential'
        }

        It '<_> keeps ComputerName and Session in different parameter sets' -ForEach $ExpectedFunctions {
            $cmd            = Get-Command $_
            $computerSets   = $cmd.Parameters['ComputerName'].ParameterSets.Keys
            $sessionSets    = $cmd.Parameters['Session'].ParameterSets.Keys
            # No parameter set should allow both at once.
            ($computerSets | Where-Object { $sessionSets -contains $_ }) | Should -BeNullOrEmpty
        }
    }
}
