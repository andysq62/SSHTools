function Restart-SSHDService {
    <#
    .SYNOPSIS
        Restarts the sshd service and returns its resulting state.

    .DESCRIPTION
        Restarts the OpenSSH server service (sshd) -- the step you take after editing
        sshd_config or fixing permissions -- and reports the service status afterward.

    .PARAMETER ComputerName
        Remote computer to act on. Omit for the local machine.

    .PARAMETER Session
        An existing PSSession to run in. Mutually exclusive with -ComputerName.

    .PARAMETER Credential
        Credential used when connecting with -ComputerName.

    .EXAMPLE
        Restart-SSHDService -ComputerName server01
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Computer')]
    param(
        [Parameter(ParameterSetName = 'Computer')]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName = 'Session', Mandatory)]
        [System.Management.Automation.Runspaces.PSSession[]]$Session,

        [Parameter(ParameterSetName = 'Computer')]
        [pscredential]$Credential
    )

    $sb = {
        $ErrorActionPreference = 'Stop'
        Restart-Service -Name sshd
        $svc = Get-Service -Name sshd
        [pscustomobject]@{
            ComputerName = $env:COMPUTERNAME
            ServiceName  = $svc.Name
            Status       = $svc.Status
        }
    }

    $tgt = if ($ComputerName) { $ComputerName -join ', ' } elseif ($Session) { ($Session.ComputerName) -join ', ' } else { $env:COMPUTERNAME }
    if (-not $PSCmdlet.ShouldProcess($tgt, 'Restart sshd service')) { return }

    $conn = @{}
    foreach ($k in 'ComputerName', 'Session', 'Credential') {
        if ($PSBoundParameters.ContainsKey($k)) { $conn[$k] = $PSBoundParameters[$k] }
    }
    Invoke-SSHToolsScriptBlock -ScriptBlock $sb @conn
}
