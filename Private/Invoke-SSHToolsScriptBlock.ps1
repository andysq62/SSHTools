function Invoke-SSHToolsScriptBlock {
    <#
    .SYNOPSIS
        Runs a script block locally, against a remote computer, or in an existing PSSession.

    .DESCRIPTION
        Central execution helper for the SSHTools module. Every public function funnels its
        work through here so that the same code path can target:

            * the local machine        (neither -ComputerName nor -Session supplied)
            * a remote computer name    (-ComputerName [, -Credential])
            * an established PSSession   (-Session)

        The supplied script block must be self-contained (use only built-in cmdlets and its own
        parameters), because when it runs over PowerShell Remoting the module's private functions
        are not present in the remote runspace.

    .NOTES
        Internal helper. Not exported.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Computer')]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [object[]]$ArgumentList,

        [Parameter(ParameterSetName = 'Computer')]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName = 'Computer')]
        [pscredential]$Credential,

        [Parameter(ParameterSetName = 'Session', Mandatory)]
        [System.Management.Automation.Runspaces.PSSession[]]$Session
    )

    $invokeParams = @{ ScriptBlock = $ScriptBlock }
    if ($ArgumentList) { $invokeParams['ArgumentList'] = $ArgumentList }

    if ($PSCmdlet.ParameterSetName -eq 'Session') {
        $invokeParams['Session'] = $Session
    }
    elseif ($ComputerName) {
        $invokeParams['ComputerName'] = $ComputerName
        if ($Credential) { $invokeParams['Credential'] = $Credential }
    }
    # else: no target -> Invoke-Command runs the block in-process (localhost)

    # When Invoke-Command runs over remoting (-ComputerName / -Session) it decorates
    # every returned object with RunspaceId, PSComputerName, and PSShowComputerName.
    # Our objects already carry their own ComputerName, so strip the remoting noise.
    Invoke-Command @invokeParams | ForEach-Object {
        if ($null -ne $_) {
            foreach ($p in 'RunspaceId', 'PSComputerName', 'PSShowComputerName') {
                $_.PSObject.Properties.Remove($p)
            }
        }
        $_
    }
}
