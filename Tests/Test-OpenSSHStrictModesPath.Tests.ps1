#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $RepoRoot 'SSHTools.psd1') -Force
}

Describe 'Test-OpenSSHStrictModesPath' {

    Context 'Plumbing' {
        BeforeEach {
            Mock -ModuleName SSHTools Invoke-SSHToolsScriptBlock { }
        }

        It 'requires -Path' {
            (Get-Command Test-OpenSSHStrictModesPath).Parameters['Path'].Attributes.Mandatory |
                Should -Contain $true
        }

        It 'passes -Path through the ArgumentList' {
            Test-OpenSSHStrictModesPath -Path 'D:\AU\Data'
            Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
                $ArgumentList[0] -eq 'D:\AU\Data'
            }
        }

        It 'forwards -ComputerName' {
            Test-OpenSSHStrictModesPath -Path 'D:\AU\Data' -ComputerName 'srv1'
            Should -Invoke Invoke-SSHToolsScriptBlock -ModuleName SSHTools -Exactly -Times 1 -ParameterFilter {
                $ComputerName -contains 'srv1'
            }
        }
    }

    Context 'ACL analysis (real dispatcher, local temp path)' {
        BeforeAll {
            $script:CleanDir = Join-Path ([System.IO.Path]::GetTempPath()) ("sshtools_clean_" + [guid]::NewGuid().ToString('N'))
            $script:BadDir   = Join-Path ([System.IO.Path]::GetTempPath()) ("sshtools_bad_"   + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:CleanDir -Force | Out-Null
            New-Item -ItemType Directory -Path $script:BadDir   -Force | Out-Null
            # Grant Authenticated Users (S-1-5-11) Modify on the "bad" dir -> StrictModes violation.
            & icacls.exe $script:BadDir /grant '*S-1-5-11:(OI)(CI)M' | Out-Null
        }

        AfterAll {
            foreach ($d in $script:CleanDir, $script:BadDir) {
                if ($d -and (Test-Path $d)) { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }

        It 'flags an over-broad Authenticated Users grant on the target path' {
            $findings = Test-OpenSSHStrictModesPath -Path $script:BadDir |
                Where-Object Path -eq $script:BadDir
            $findings | Should -Not -BeNullOrEmpty
            $findings.Identity | Should -Contain 'NT AUTHORITY\Authenticated Users'
            ($findings | Where-Object Identity -eq 'NT AUTHORITY\Authenticated Users').Rights |
                Should -Match 'Modify'
        }

        It 'does not flag the target path itself when its ACL is clean' {
            # The freshly-created clean dir inherits from TEMP; assert no finding is anchored
            # at the clean dir itself (parent inheritance from TEMP is out of our control).
            Test-OpenSSHStrictModesPath -Path $script:CleanDir |
                Where-Object Path -eq $script:CleanDir |
                Where-Object Identity -eq 'NT AUTHORITY\Authenticated Users' |
                Should -BeNullOrEmpty
        }

        It 'throws on a non-existent path' {
            { Test-OpenSSHStrictModesPath -Path 'Z:\does\not\exist' -ErrorAction Stop } | Should -Throw
        }
    }
}
