function Backup-OpenSSHConfiguration {
    <#
    .SYNOPSIS
        Backs up the OpenSSH configuration directory (host keys, sshd_config, key files).

    .DESCRIPTION
        Copies the ssh data directory (%ProgramData%\ssh by default) into a timestamped
        subfolder of the backup destination. The copy runs in the target context, so
        pointing this at a remote computer backs up that computer's configuration onto
        that computer.

        Replaces the Copy-SSHConfigBackup snippet.

    .PARAMETER Path
        Source directory to back up. Defaults to "$env:ProgramData\ssh".

    .PARAMETER Destination
        Root backup folder. A timestamped subfolder is created inside it.
        Defaults to "C:\Backup\ssh_backup".

    .PARAMETER ComputerName
        Remote computer to back up. Omit for the local machine.

    .PARAMETER Session
        An existing PSSession to run in. Mutually exclusive with -ComputerName.

    .PARAMETER Credential
        Credential used when connecting with -ComputerName.

    .EXAMPLE
        Backup-OpenSSHConfiguration

    .EXAMPLE
        Backup-OpenSSHConfiguration -ComputerName coltst19xfer -Destination D:\Backups\ssh
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Computer')]
    param(
        [string]$Path = "$env:ProgramData\ssh",

        [string]$Destination = 'C:\Backup\ssh_backup',

        [Parameter(ParameterSetName = 'Computer')]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName = 'Session', Mandatory)]
        [System.Management.Automation.Runspaces.PSSession[]]$Session,

        [Parameter(ParameterSetName = 'Computer')]
        [pscredential]$Credential
    )

    $sb = {
        param([string]$Path, [string]$Destination)

        $ErrorActionPreference = 'Stop'
        if (-not (Test-Path -LiteralPath $Path)) { throw "Source path not found: $Path" }

        $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
        $target = Join-Path $Destination $stamp
        New-Item -Path $target -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $Path -Destination $target -Recurse -Force

        [pscustomobject]@{
            ComputerName = $env:COMPUTERNAME
            Source       = $Path
            BackupPath   = $target
            FileCount    = (Get-ChildItem -LiteralPath $target -Recurse -File).Count
        }
    }

    $tgt = if ($ComputerName) { $ComputerName -join ', ' } elseif ($Session) { ($Session.ComputerName) -join ', ' } else { $env:COMPUTERNAME }
    if (-not $PSCmdlet.ShouldProcess($tgt, "Back up '$Path' to '$Destination'")) { return }

    $conn = @{}
    foreach ($k in 'ComputerName', 'Session', 'Credential') {
        if ($PSBoundParameters.ContainsKey($k)) { $conn[$k] = $PSBoundParameters[$k] }
    }
    Invoke-SSHToolsScriptBlock -ScriptBlock $sb -ArgumentList $Path, $Destination @conn
}
