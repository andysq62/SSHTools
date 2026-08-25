function Test-OpenSSHStrictModesPath {
    <#
    .SYNOPSIS
        Checks a chroot/authorized-keys path chain for permissions that fail Win32-OpenSSH StrictModes.

    .DESCRIPTION
        Win32-OpenSSH (StrictModes yes, the default) validates ownership and write permissions
        on a ChrootDirectory / AuthorizedKeysFile path AND every parent directory up to the drive
        root before it will accept public-key authentication. Any write/modify grant to an
        account other than SYSTEM, the Administrators group, or the path owner silently breaks
        pubkey auth (the client falls back to password with no useful error).

        This function walks the supplied path up to its drive root and reports, for each level,
        any access-control entries that would trip StrictModes -- most commonly
        "NT AUTHORITY\Authenticated Users" with Modify.

    .PARAMETER Path
        The path to validate (for example a ChrootDirectory such as "D:\AU\Data").

    .PARAMETER ComputerName
        Remote computer to query. Omit for the local machine.

    .PARAMETER Session
        An existing PSSession to run in. Mutually exclusive with -ComputerName.

    .PARAMETER Credential
        Credential used when connecting with -ComputerName.

    .EXAMPLE
        Test-OpenSSHStrictModesPath -Path 'D:\AU\Data' -ComputerName coltst19xfer

    .OUTPUTS
        One object per offending ACE. No output means the path chain is clean.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Computer')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(ParameterSetName = 'Computer')]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName = 'Session', Mandatory)]
        [System.Management.Automation.Runspaces.PSSession[]]$Session,

        [Parameter(ParameterSetName = 'Computer')]
        [pscredential]$Credential
    )

    $sb = {
        param([string]$Path)

        if (-not (Test-Path -LiteralPath $Path)) { throw "Path not found: $Path" }

        # Identities that are allowed to have write access under StrictModes.
        $allowed = @('NT AUTHORITY\SYSTEM', 'BUILTIN\Administrators')

        # Rights that constitute "write" for StrictModes purposes.
        $writeMask = [System.Security.AccessControl.FileSystemRights]::Write         -bor
                     [System.Security.AccessControl.FileSystemRights]::WriteData     -bor
                     [System.Security.AccessControl.FileSystemRights]::AppendData    -bor
                     [System.Security.AccessControl.FileSystemRights]::Modify        -bor
                     [System.Security.AccessControl.FileSystemRights]::FullControl   -bor
                     [System.Security.AccessControl.FileSystemRights]::WriteAttributes -bor
                     [System.Security.AccessControl.FileSystemRights]::WriteExtendedAttributes

        # Build the chain from the path up to the drive root.
        $chain = @()
        $current = (Resolve-Path -LiteralPath $Path).Path
        while ($current) {
            $chain += $current
            $parent = Split-Path -Path $current -Parent
            if ($parent -eq $current -or [string]::IsNullOrEmpty($parent)) { break }
            $current = $parent
        }

        foreach ($item in $chain) {
            $acl   = Get-Acl -LiteralPath $item
            $owner = $acl.Owner
            foreach ($ace in $acl.Access) {
                if ($ace.AccessControlType -ne 'Allow') { continue }
                if (($ace.FileSystemRights -band $writeMask) -eq 0) { continue }

                $id = $ace.IdentityReference.Value
                if ($allowed -contains $id) { continue }
                if ($id -eq $owner) { continue }

                [pscustomobject]@{
                    ComputerName = $env:COMPUTERNAME
                    Path         = $item
                    Owner        = $owner
                    Identity     = $id
                    Rights       = $ace.FileSystemRights.ToString()
                    Inherited    = $ace.IsInherited
                }
            }
        }
    }

    $conn = @{}
    foreach ($k in 'ComputerName', 'Session', 'Credential') {
        if ($PSBoundParameters.ContainsKey($k)) { $conn[$k] = $PSBoundParameters[$k] }
    }
    Invoke-SSHToolsScriptBlock -ScriptBlock $sb -ArgumentList $Path @conn
}
