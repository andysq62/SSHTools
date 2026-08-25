function Get-OpenSSHInstallation {
    <#
    .SYNOPSIS
        Reports the OpenSSH installation(s) present on a machine.

    .DESCRIPTION
        Detects both the "in-box" OpenSSH that ships with Windows (under
        %SystemRoot%\System32\OpenSSH) and a standalone Win32-OpenSSH install
        (under %ProgramFiles%\OpenSSH), returning the file version of each sshd.exe
        found, the ssh.exe currently resolved on PATH, and the state of the sshd service.

        Replaces the Get-OpenSSHType and Get-OpenSSHVersion snippets.

    .PARAMETER ComputerName
        One or more remote computers to query. Omit to query the local machine.

    .PARAMETER Session
        An existing PSSession to run in. Mutually exclusive with -ComputerName.

    .PARAMETER Credential
        Credential used when connecting with -ComputerName.

    .EXAMPLE
        Get-OpenSSHInstallation

    .EXAMPLE
        Get-OpenSSHInstallation -ComputerName coltst19xfer

    .EXAMPLE
        $s = New-PSSession coltst19xfer; Get-OpenSSHInstallation -Session $s
    #>
    [CmdletBinding(DefaultParameterSetName = 'Computer')]
    param(
        [Parameter(ParameterSetName = 'Computer', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName = 'Session', Mandatory)]
        [System.Management.Automation.Runspaces.PSSession[]]$Session,

        [Parameter(ParameterSetName = 'Computer')]
        [pscredential]$Credential
    )

    process {
        $sb = {
            $candidates = @(
                @{ Type = 'Installed'; Path = Join-Path $env:ProgramFiles 'OpenSSH\sshd.exe' }
                @{ Type = 'InBox';     Path = Join-Path $env:SystemRoot  'System32\OpenSSH\sshd.exe' }
            )

            $installs = foreach ($c in $candidates) {
                if (Test-Path -LiteralPath $c.Path) {
                    $vi = (Get-Item -LiteralPath $c.Path).VersionInfo
                    [pscustomobject]@{
                        Type           = $c.Type
                        Path           = $c.Path
                        ProductVersion = $vi.ProductVersion
                        FileVersion    = $vi.FileVersion
                    }
                }
            }

            $svc    = Get-Service -Name sshd -ErrorAction SilentlyContinue
            $sshCmd = Get-Command ssh.exe -ErrorAction SilentlyContinue

            [pscustomobject]@{
                ComputerName     = $env:COMPUTERNAME
                Installs         = $installs
                ClientOnPath     = $sshCmd.Source
                ServiceName      = $svc.Name
                ServiceStatus    = if ($svc) { $svc.Status }    else { 'NotInstalled' }
                ServiceStartType = if ($svc) { $svc.StartType } else { $null }
            }
        }

        $conn = @{}
        foreach ($k in 'ComputerName', 'Session', 'Credential') {
            if ($PSBoundParameters.ContainsKey($k)) { $conn[$k] = $PSBoundParameters[$k] }
        }
        Invoke-SSHToolsScriptBlock -ScriptBlock $sb @conn
    }
}
