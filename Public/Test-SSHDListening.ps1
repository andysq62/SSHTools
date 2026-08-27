function Test-SSHDListening {
    <#
    .SYNOPSIS
        Tests whether sshd is listening on a TCP port.

    .DESCRIPTION
        Checks for a listening TCP endpoint on the given port (22 by default) and reports
        whether one exists, along with the owning process where it can be resolved. This
        confirms the sshd service is actually bound and accepting connections, independent
        of firewall scope.

    .PARAMETER Port
        TCP port to check. Defaults to 22.

    .PARAMETER ComputerName
        Remote computer to query. Omit for the local machine.

    .PARAMETER Session
        An existing PSSession to run in. Mutually exclusive with -ComputerName.

    .PARAMETER Credential
        Credential used when connecting with -ComputerName.

    .EXAMPLE
        Test-SSHDListening

    .EXAMPLE
        Test-SSHDListening -ComputerName server01 -Port 22
    #>
    [CmdletBinding(DefaultParameterSetName = 'Computer')]
    param(
        [ValidateRange(1, 65535)]
        [int]$Port = 22,

        [Parameter(ParameterSetName = 'Computer', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName = 'Session', Mandatory)]
        [System.Management.Automation.Runspaces.PSSession[]]$Session,

        [Parameter(ParameterSetName = 'Computer')]
        [pscredential]$Credential
    )

    process {
        $sb = {
            param([int]$Port)

            $listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
            $procName = $null
            if ($listeners) {
                $procName = ($listeners | ForEach-Object {
                        (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
                    } | Where-Object { $_ } | Select-Object -Unique) -join ', '
            }

            [pscustomobject]@{
                ComputerName  = $env:COMPUTERNAME
                Port          = $Port
                Listening     = [bool]$listeners
                OwningProcess = $procName
            }
        }

        $conn = @{}
        foreach ($k in 'ComputerName', 'Session', 'Credential') {
            if ($PSBoundParameters.ContainsKey($k)) { $conn[$k] = $PSBoundParameters[$k] }
        }
        Invoke-SSHToolsScriptBlock -ScriptBlock $sb -ArgumentList $Port @conn
    }
}
