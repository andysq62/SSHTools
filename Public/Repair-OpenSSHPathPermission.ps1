function Repair-OpenSSHPathPermission {
    <#
    .SYNOPSIS
        Removes an overly broad group's access from a chroot/authorized-keys path chain.

    .DESCRIPTION
        Removes a security principal's access-control entries (default
        "NT AUTHORITY\Authenticated Users") from a path and, with -Recurse, propagates the
        removal to existing children. This is the permanent fix for the StrictModes pubkey
        failure that Test-OpenSSHStrictModesPath detects -- it strips the broad write grant
        instead of leaving StrictModes disabled.

        Uses icacls under the hood. Replaces the Set-OpenSSHPermissions snippet.

    .PARAMETER Path
        The path to clean (for example a ChrootDirectory root such as "D:\").

    .PARAMETER Identity
        The principal whose access to remove. Defaults to "NT AUTHORITY\Authenticated Users".

    .PARAMETER Recurse
        Propagate the removal to existing child files and folders (icacls /T).

    .PARAMETER ComputerName
        Remote computer to modify. Omit for the local machine.

    .PARAMETER Session
        An existing PSSession to run in. Mutually exclusive with -ComputerName.

    .PARAMETER Credential
        Credential used when connecting with -ComputerName.

    .EXAMPLE
        Repair-OpenSSHPathPermission -Path D:\ -Recurse -ComputerName coltst19xfer

    .EXAMPLE
        Repair-OpenSSHPathPermission -Path 'D:\AU\Data' -Identity 'DOMAIN\SomeGroup' -Recurse -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Computer')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Identity = 'NT AUTHORITY\Authenticated Users',

        [switch]$Recurse,

        [Parameter(ParameterSetName = 'Computer')]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName = 'Session', Mandatory)]
        [System.Management.Automation.Runspaces.PSSession[]]$Session,

        [Parameter(ParameterSetName = 'Computer')]
        [pscredential]$Credential
    )

    $sb = {
        param([string]$Path, [string]$Identity, [bool]$Recurse)

        if (-not (Test-Path -LiteralPath $Path)) { throw "Path not found: $Path" }

        $args = @($Path, '/remove:g', $Identity, '/C')
        if ($Recurse) { $args += '/T' }

        $output   = & icacls.exe @args 2>&1
        $exitCode = $LASTEXITCODE

        [pscustomobject]@{
            ComputerName = $env:COMPUTERNAME
            Path         = $Path
            Identity     = $Identity
            Recurse      = $Recurse
            ExitCode     = $exitCode
            Success      = ($exitCode -eq 0)
            Output       = ($output | Out-String).Trim()
        }
    }

    $tgt = if ($ComputerName) { $ComputerName -join ', ' } elseif ($Session) { ($Session.ComputerName) -join ', ' } else { $env:COMPUTERNAME }
    if (-not $PSCmdlet.ShouldProcess("$tgt : $Path", "Remove '$Identity' access$(if($Recurse){' recursively'})")) { return }

    $conn = @{}
    foreach ($k in 'ComputerName', 'Session', 'Credential') {
        if ($PSBoundParameters.ContainsKey($k)) { $conn[$k] = $PSBoundParameters[$k] }
    }
    Invoke-SSHToolsScriptBlock -ScriptBlock $sb -ArgumentList $Path, $Identity, ([bool]$Recurse) @conn
}
