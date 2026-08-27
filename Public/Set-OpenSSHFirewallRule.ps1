function Set-OpenSSHFirewallRule {
    <#
    .SYNOPSIS
        Sets the network profile scope (and optionally the enabled state) of an OpenSSH firewall rule.

    .DESCRIPTION
        Rescopes the sshd firewall rule to the requested profiles. The default targets the
        standard Win32-OpenSSH server rule and applies it to the Domain and Private profiles,
        which resolves the common case of a Private-only rule failing to match a domain NIC.

    .PARAMETER DisplayName
        Exact display name of the rule to modify.
        Defaults to "OpenSSH SSH Server Preview (sshd)".

    .PARAMETER Profile
        Profiles to scope the rule to. Defaults to Domain, Private.

    .PARAMETER Enabled
        Optionally set the rule's enabled state (True/False) at the same time.

    .PARAMETER ComputerName
        Remote computer to modify. Omit for the local machine.

    .PARAMETER Session
        An existing PSSession to run in. Mutually exclusive with -ComputerName.

    .PARAMETER Credential
        Credential used when connecting with -ComputerName.

    .EXAMPLE
        Set-OpenSSHFirewallRule -ComputerName server01

    .EXAMPLE
        Set-OpenSSHFirewallRule -Profile Domain,Private,Public -Enabled $true
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', '',
        Justification = 'Mirrors Set-NetFirewallRule -Profile. The bound parameter shadows the automatic $Profile, which this function never reads.')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Computer')]
    param(
        [string]$DisplayName = 'OpenSSH SSH Server Preview (sshd)',

        [ValidateSet('Domain', 'Private', 'Public', 'Any')]
        [string[]]$Profile = @('Domain', 'Private'),

        [bool]$Enabled,

        [Parameter(ParameterSetName = 'Computer')]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName = 'Session', Mandatory)]
        [System.Management.Automation.Runspaces.PSSession[]]$Session,

        [Parameter(ParameterSetName = 'Computer')]
        [pscredential]$Credential
    )

    $enabledSet = $PSBoundParameters.ContainsKey('Enabled')

    $sb = {
        param([string]$DisplayName, [string[]]$Profile, [bool]$EnabledSet, [bool]$Enabled)

        $params = @{ DisplayName = $DisplayName; Profile = $Profile }
        if ($EnabledSet) { $params['Enabled'] = if ($Enabled) { 'True' } else { 'False' } }
        Set-NetFirewallRule @params -ErrorAction Stop

        Get-NetFirewallRule -DisplayName $DisplayName | ForEach-Object {
            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                DisplayName  = $_.DisplayName
                Enabled      = $_.Enabled
                Profiles     = ($_ | Get-NetFirewallProfile).Name -join ', '
            }
        }
    }

    $target = if ($ComputerName) { $ComputerName -join ', ' } elseif ($Session) { ($Session.ComputerName) -join ', ' } else { $env:COMPUTERNAME }
    if (-not $PSCmdlet.ShouldProcess($target, "Set firewall rule '$DisplayName' to profiles $($Profile -join ',')")) { return }

    $conn = @{}
    foreach ($k in 'ComputerName', 'Session', 'Credential') {
        if ($PSBoundParameters.ContainsKey($k)) { $conn[$k] = $PSBoundParameters[$k] }
    }
    Invoke-SSHToolsScriptBlock -ScriptBlock $sb -ArgumentList $DisplayName, $Profile, $enabledSet, ([bool]$Enabled) @conn
}
