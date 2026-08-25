function Get-OpenSSHFirewallRule {
    <#
    .SYNOPSIS
        Lists the Windows Firewall rules for OpenSSH, including their profile scope.

    .DESCRIPTION
        Returns every firewall rule whose display name matches the OpenSSH pattern, with
        the enabled state, direction, action, and the network profiles the rule applies to.

        A rule can show Enabled = True yet never take effect if its profile scope does not
        match the machine's active connection profile (for example a Private-only rule on a
        DomainAuthenticated NIC) -- the Profiles column is what makes that visible.

        Replaces the Get-SSHFirewallRule and Get-OpenSSHFirewallProfile snippets.

    .PARAMETER DisplayName
        Wildcard pattern matched against the rule display name. Defaults to "*OpenSSH*".

    .PARAMETER ComputerName
        Remote computer to query. Omit for the local machine.

    .PARAMETER Session
        An existing PSSession to run in. Mutually exclusive with -ComputerName.

    .PARAMETER Credential
        Credential used when connecting with -ComputerName.

    .EXAMPLE
        Get-OpenSSHFirewallRule -ComputerName coltst19xfer

    .EXAMPLE
        Get-OpenSSHFirewallRule -DisplayName 'OpenSSH SSH Server*'
    #>
    [CmdletBinding(DefaultParameterSetName = 'Computer')]
    param(
        [string]$DisplayName = '*OpenSSH*',

        [Parameter(ParameterSetName = 'Computer', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName = 'Session', Mandatory)]
        [System.Management.Automation.Runspaces.PSSession[]]$Session,

        [Parameter(ParameterSetName = 'Computer')]
        [pscredential]$Credential
    )

    process {
        $sb = {
            param([string]$DisplayName)

            Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue | ForEach-Object {
                $profiles = ($_ | Get-NetFirewallProfile).Name -join ', '
                [pscustomobject]@{
                    ComputerName = $env:COMPUTERNAME
                    DisplayName  = $_.DisplayName
                    Enabled      = $_.Enabled
                    Direction    = $_.Direction
                    Action       = $_.Action
                    Profiles     = $profiles
                }
            }
        }

        $conn = @{}
        foreach ($k in 'ComputerName', 'Session', 'Credential') {
            if ($PSBoundParameters.ContainsKey($k)) { $conn[$k] = $PSBoundParameters[$k] }
        }
        Invoke-SSHToolsScriptBlock -ScriptBlock $sb -ArgumentList $DisplayName @conn
    }
}
