function Install-OpenSSH {
    <#
    .SYNOPSIS
        Downloads the latest Win32-OpenSSH MSI and (optionally) installs it.

    .DESCRIPTION
        Queries the PowerShell/Win32-OpenSSH GitHub releases API for the latest
        OpenSSH-Win64 MSI, downloads it, and reports its SHA256 hash. Unless
        -DownloadOnly is specified the MSI is installed silently via msiexec.

        The download and install execute in the target context, so pointing this at a
        remote computer installs OpenSSH on that computer. The target must have outbound
        internet access to reach github.com.

    .PARAMETER DownloadOnly
        Download and hash the MSI but do not install it. The downloaded path and hash
        are returned so you can verify SHA256 against the releases page before installing.

    .PARAMETER ComputerName
        Remote computer to install on. Omit for the local machine.

    .PARAMETER Session
        An existing PSSession to run in. Mutually exclusive with -ComputerName.

    .PARAMETER Credential
        Credential used when connecting with -ComputerName.

    .EXAMPLE
        Install-OpenSSH -DownloadOnly

    .EXAMPLE
        Install-OpenSSH -ComputerName server01 -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Computer')]
    param(
        [switch]$DownloadOnly,

        [Parameter(ParameterSetName = 'Computer')]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName = 'Session', Mandatory)]
        [System.Management.Automation.Runspaces.PSSession[]]$Session,

        [Parameter(ParameterSetName = 'Computer')]
        [pscredential]$Credential
    )

    $sb = {
        param([bool]$DownloadOnly)

        $ErrorActionPreference = 'Stop'
        $release = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest'
        $asset   = $release.assets | Where-Object name -like 'OpenSSH-Win64-v*.msi' | Select-Object -First 1
        if (-not $asset) { throw 'Could not locate an OpenSSH-Win64 MSI asset on the latest release.' }

        $msi = Join-Path $env:TEMP $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msi -UseBasicParsing
        $hash = (Get-FileHash -Path $msi -Algorithm SHA256).Hash

        $installed = $false
        if (-not $DownloadOnly) {
            $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn" -Wait -PassThru
            if ($p.ExitCode -ne 0) { throw "msiexec exited with code $($p.ExitCode)." }
            $installed = $true
        }

        [pscustomobject]@{
            ComputerName = $env:COMPUTERNAME
            Release      = $release.tag_name
            Asset        = $asset.name
            MsiPath      = $msi
            SHA256       = $hash
            Installed    = $installed
        }
    }

    $action = if ($DownloadOnly) { 'Download OpenSSH MSI' } else { 'Download and install latest Win32-OpenSSH' }
    $target = if ($ComputerName) { $ComputerName -join ', ' } elseif ($Session) { ($Session.ComputerName) -join ', ' } else { $env:COMPUTERNAME }
    if (-not $PSCmdlet.ShouldProcess($target, $action)) { return }

    $conn = @{}
    foreach ($k in 'ComputerName', 'Session', 'Credential') {
        if ($PSBoundParameters.ContainsKey($k)) { $conn[$k] = $PSBoundParameters[$k] }
    }
    Invoke-SSHToolsScriptBlock -ScriptBlock $sb -ArgumentList ([bool]$DownloadOnly) @conn
}
