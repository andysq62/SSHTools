function Get-OpenSSHStatusReport {
    <#
    .SYNOPSIS
        Collects a single snapshot of OpenSSH state (installation, service, firewall, listening
        port, and file permissions) for before/after comparison across an install or upgrade.

    .DESCRIPTION
        Gathers, in one round-trip, everything the individual SSHTools check functions report,
        plus the piece they don't: the actual owner, ACL, and hash of the permission-sensitive
        OpenSSH files. An install or upgrade of Win32-OpenSSH frequently resets ACLs on
        %ProgramData%\ssh and its host keys, or regenerates host keys outright; capturing the
        real access-control entries (not just StrictModes violations) is what makes those
        changes visible in a diff.

        Run it once before the change and once after, writing each run to a file with -OutFile,
        then compare the two files. The report is deterministically ordered (paths, rules, and
        ACEs are all sorted) so a plain text diff shows only what genuinely changed. The only
        volatile line is the "# Collected (UTC)" header, which is prefixed with '#'.

        What the snapshot contains:
            * Installation   - Installed and in-box sshd.exe versions, ssh.exe on PATH, and the
                               sshd service name/status/start type.
            * Firewall       - OpenSSH firewall rules with their enabled state and profile scope.
            * Listening      - Whether a listener is bound on the SSH port and the owning process.
            * Paths          - Owner + full ACL of the ssh data directory, sshd_config,
                               administrators_authorized_keys, and every ssh_host_* file, plus a
                               SHA256 hash and last-write time for files. Any -Path values are
                               added to this set.
            * StrictModes    - For each -Path (a chroot/authorized-keys chain), the same
                               offending ACEs that Test-OpenSSHStrictModesPath reports.

    .PARAMETER Path
        One or more additional paths (typically SFTP ChrootDirectory roots) to include. Each is
        captured in the Paths section and walked to its drive root for StrictModes findings.

    .PARAMETER Port
        SSH port to check for a listener. Defaults to 22.

    .PARAMETER FirewallDisplayName
        Wildcard matched against firewall rule display names. Defaults to "*OpenSSH*".

    .PARAMETER OutFile
        Path to write the human-readable, diff-friendly text report to. The snapshot object is
        still returned on the pipeline. Parent directories are created if needed. When several
        computers are targeted, all of their reports are written to the one file in sequence.

    .PARAMETER ComputerName
        One or more remote computers to snapshot. Omit to snapshot the local machine.

    .PARAMETER Session
        An existing PSSession to run in. Mutually exclusive with -ComputerName.

    .PARAMETER Credential
        Credential used when connecting with -ComputerName.

    .EXAMPLE
        Get-OpenSSHStatusReport -OutFile C:\ssh-before.txt

        Snapshot the local machine before an upgrade.

    .EXAMPLE
        Get-OpenSSHStatusReport -Path 'D:\AU\Data' -OutFile C:\ssh-after.txt
        Compare-Object (Get-Content C:\ssh-before.txt) (Get-Content C:\ssh-after.txt)

        Snapshot after the upgrade (including a chroot path) and diff the two reports.

    .EXAMPLE
        Get-OpenSSHStatusReport -ComputerName server01 -Credential (Get-Credential)

        Return the structured snapshot object for a remote host.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Computer')]
    param(
        [string[]]$Path,

        [ValidateRange(1, 65535)]
        [int]$Port = 22,

        [string]$FirewallDisplayName = '*OpenSSH*',

        [string]$OutFile,

        [Parameter(ParameterSetName = 'Computer', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$ComputerName,

        [Parameter(ParameterSetName = 'Session', Mandatory)]
        [System.Management.Automation.Runspaces.PSSession[]]$Session,

        [Parameter(ParameterSetName = 'Computer')]
        [pscredential]$Credential
    )

    begin {
        $collected = New-Object System.Collections.Generic.List[object]

        # Renders one snapshot object as a stable, sorted block of text lines.
        function Format-Snapshot {
            param($r)

            $out = New-Object System.Collections.Generic.List[string]
            $out.Add('# SSHTools OpenSSH status report')
            $out.Add("# Collected (UTC): $($r.CollectedAt)  [informational -- changes every run]")
            $out.Add("Computer: $($r.ComputerName)")
            $out.Add('')

            $out.Add('[Installation]')
            $i = $r.Installation
            $out.Add("ClientOnPath     = $($i.ClientOnPath)")
            $out.Add("ServiceName      = $($i.ServiceName)")
            $out.Add("ServiceStatus    = $($i.ServiceStatus)")
            $out.Add("ServiceStartType = $($i.ServiceStartType)")
            foreach ($ins in @($i.Installs | Sort-Object Type)) {
                $out.Add("Install[$($ins.Type)] Path           = $($ins.Path)")
                $out.Add("Install[$($ins.Type)] ProductVersion = $($ins.ProductVersion)")
                $out.Add("Install[$($ins.Type)] FileVersion    = $($ins.FileVersion)")
            }
            $out.Add('')

            $out.Add('[Firewall]')
            $rules = @($r.Firewall | Sort-Object DisplayName, Direction)
            if ($rules.Count -eq 0) { $out.Add('(no matching rules)') }
            foreach ($f in $rules) {
                $out.Add("Rule '$($f.DisplayName)' [$($f.Direction)] Enabled=$($f.Enabled) Action=$($f.Action) Profiles=$($f.Profiles)")
            }
            $out.Add('')

            $out.Add('[Listening]')
            $l = $r.Listening
            $out.Add("Port $($l.Port): Listening=$($l.Listening) Process=$($l.OwningProcess)")
            $out.Add('')

            $out.Add('[Paths]')
            foreach ($p in @($r.Paths | Sort-Object Path)) {
                $out.Add("Path $($p.Path)")
                $out.Add("  Exists    = $($p.Exists)")
                if ($p.Exists) {
                    $out.Add("  Container = $($p.IsContainer)")
                    $out.Add("  Owner     = $($p.Owner)")
                    if (-not $p.IsContainer) {
                        $out.Add("  Sha256    = $($p.Sha256)")
                        $out.Add("  Length    = $($p.Length)")
                        $out.Add("  Modified  = $($p.LastWriteTimeUtc)")
                    }
                    foreach ($a in @($p.Access | Sort-Object Identity, Type, Rights, InheritanceFlags, PropagationFlags)) {
                        $out.Add("  ACE = $($a.Type) | $($a.Identity) | $($a.Rights) | Inherited=$($a.Inherited) | Inh=$($a.InheritanceFlags) | Prop=$($a.PropagationFlags)")
                    }
                }
            }
            $out.Add('')

            $out.Add('[StrictModes offending ACEs]')
            $bad = @($r.StrictModes | Sort-Object RootPath, Path, Identity)
            if ($bad.Count -eq 0) { $out.Add('(none)') }
            foreach ($s in $bad) {
                $out.Add("$($s.Path) : $($s.Identity) has $($s.Rights) (owner $($s.Owner), inherited=$($s.Inherited), root $($s.RootPath))")
            }

            $out
        }

        # Self-contained collector run in the target context. Uses only built-in cmdlets and
        # emits only primitives / nested pscustomobjects so it serializes cleanly over remoting.
        $sb = {
            param([string[]]$Paths, [string]$FirewallDisplayName, [int]$Port)

            function ConvertTo-AclSnapshot {
                param([string]$ItemPath)
                $acl = Get-Acl -LiteralPath $ItemPath
                $entries = @(foreach ($ace in $acl.Access) {
                        [pscustomobject]@{
                            Identity         = $ace.IdentityReference.Value
                            Type             = $ace.AccessControlType.ToString()
                            Rights           = $ace.FileSystemRights.ToString()
                            Inherited        = [bool]$ace.IsInherited
                            InheritanceFlags = $ace.InheritanceFlags.ToString()
                            PropagationFlags = $ace.PropagationFlags.ToString()
                        }
                    })
                [pscustomobject]@{
                    Owner  = $acl.Owner
                    Access = @($entries | Sort-Object Identity, Type, Rights, InheritanceFlags, PropagationFlags)
                }
            }

            # ---- Installation ----
            $candidates = @(
                @{ Type = 'Installed'; Path = Join-Path $env:ProgramFiles 'OpenSSH\sshd.exe' }
                @{ Type = 'InBox';     Path = Join-Path $env:SystemRoot  'System32\OpenSSH\sshd.exe' }
            )
            $installs = @(foreach ($c in $candidates) {
                    if (Test-Path -LiteralPath $c.Path) {
                        $vi = (Get-Item -LiteralPath $c.Path).VersionInfo
                        [pscustomobject]@{
                            Type           = $c.Type
                            Path           = $c.Path
                            ProductVersion = $vi.ProductVersion
                            FileVersion    = $vi.FileVersion
                        }
                    }
                })
            $svc    = Get-Service -Name sshd -ErrorAction SilentlyContinue
            $sshCmd = Get-Command ssh.exe -ErrorAction SilentlyContinue
            $installation = [pscustomobject]@{
                Installs         = $installs
                ClientOnPath     = $sshCmd.Source
                ServiceName      = $svc.Name
                ServiceStatus    = if ($svc) { $svc.Status.ToString() }    else { 'NotInstalled' }
                ServiceStartType = if ($svc) { $svc.StartType.ToString() } else { $null }
            }

            # ---- Firewall ----
            $firewall = @(Get-NetFirewallRule -DisplayName $FirewallDisplayName -ErrorAction SilentlyContinue | ForEach-Object {
                    $profiles = ($_ | Get-NetFirewallProfile).Name -join ', '
                    [pscustomobject]@{
                        DisplayName = $_.DisplayName
                        Enabled     = $_.Enabled.ToString()
                        Direction   = $_.Direction.ToString()
                        Action      = $_.Action.ToString()
                        Profiles    = $profiles
                    }
                })

            # ---- Listening ----
            $listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
            $procName = $null
            if ($listeners) {
                $procName = ($listeners | ForEach-Object {
                        (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
                    } | Where-Object { $_ } | Select-Object -Unique) -join ', '
            }
            $listening = [pscustomobject]@{
                Port          = $Port
                Listening     = [bool]$listeners
                OwningProcess = $procName
            }

            # ---- Permission-sensitive path targets ----
            $sshDir  = Join-Path $env:ProgramData 'ssh'
            $targets = New-Object System.Collections.Generic.List[string]
            $targets.Add($sshDir)
            if (Test-Path -LiteralPath $sshDir) {
                Get-ChildItem -LiteralPath $sshDir -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq 'sshd_config' -or $_.Name -eq 'administrators_authorized_keys' -or $_.Name -like 'ssh_host_*' } |
                    ForEach-Object { $targets.Add($_.FullName) }
            }
            foreach ($p in $Paths) { if ($p) { $targets.Add($p) } }

            $pathReports = @(foreach ($t in ($targets | Select-Object -Unique)) {
                    if (-not (Test-Path -LiteralPath $t)) {
                        [pscustomobject]@{
                            Path = $t; Exists = $false; IsContainer = $null; Owner = $null
                            Sha256 = $null; Length = $null; LastWriteTimeUtc = $null; Access = @()
                        }
                        continue
                    }
                    $item = Get-Item -LiteralPath $t -Force
                    $isContainer = [bool]$item.PSIsContainer
                    $snap = ConvertTo-AclSnapshot -ItemPath $t
                    $sha = $null; $len = $null
                    if (-not $isContainer) {
                        $len = $item.Length
                        try { $sha = (Get-FileHash -LiteralPath $t -Algorithm SHA256).Hash } catch { $sha = $null }
                    }
                    [pscustomobject]@{
                        Path             = $t
                        Exists           = $true
                        IsContainer      = $isContainer
                        Owner            = $snap.Owner
                        Sha256           = $sha
                        Length           = $len
                        LastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o')
                        Access           = $snap.Access
                    }
                })

            # ---- StrictModes findings for supplied chroot chains ----
            $allowed   = @('NT AUTHORITY\SYSTEM', 'BUILTIN\Administrators')
            $writeMask = [System.Security.AccessControl.FileSystemRights]::Write               -bor
                         [System.Security.AccessControl.FileSystemRights]::WriteData           -bor
                         [System.Security.AccessControl.FileSystemRights]::AppendData          -bor
                         [System.Security.AccessControl.FileSystemRights]::Modify              -bor
                         [System.Security.AccessControl.FileSystemRights]::FullControl         -bor
                         [System.Security.AccessControl.FileSystemRights]::WriteAttributes     -bor
                         [System.Security.AccessControl.FileSystemRights]::WriteExtendedAttributes
            $strict = @(foreach ($p in $Paths) {
                    if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
                    $chain   = @()
                    $current = (Resolve-Path -LiteralPath $p).Path
                    while ($current) {
                        $chain += $current
                        $parent = Split-Path -Path $current -Parent
                        if ($parent -eq $current -or [string]::IsNullOrEmpty($parent)) { break }
                        $current = $parent
                    }
                    foreach ($node in $chain) {
                        $acl   = Get-Acl -LiteralPath $node
                        $owner = $acl.Owner
                        foreach ($ace in $acl.Access) {
                            if ($ace.AccessControlType -ne 'Allow') { continue }
                            if (($ace.FileSystemRights -band $writeMask) -eq 0) { continue }
                            $id = $ace.IdentityReference.Value
                            if ($allowed -contains $id) { continue }
                            if ($id -eq $owner) { continue }
                            [pscustomobject]@{
                                RootPath  = $p
                                Path      = $node
                                Owner     = $owner
                                Identity  = $id
                                Rights    = $ace.FileSystemRights.ToString()
                                Inherited = [bool]$ace.IsInherited
                            }
                        }
                    }
                })

            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                CollectedAt  = (Get-Date).ToUniversalTime().ToString('o')
                Installation = $installation
                Firewall     = $firewall
                Listening    = $listening
                Paths        = $pathReports
                StrictModes  = $strict
            }
        }
    }

    process {
        # Keep the path array intact as a single positional argument.
        $pathsArg = @($Path | Where-Object { $_ })
        $argList  = New-Object System.Collections.Generic.List[object]
        $argList.Add($pathsArg)
        $argList.Add($FirewallDisplayName)
        $argList.Add($Port)

        $conn = @{}
        foreach ($k in 'ComputerName', 'Session', 'Credential') {
            if ($PSBoundParameters.ContainsKey($k)) { $conn[$k] = $PSBoundParameters[$k] }
        }

        $results = Invoke-SSHToolsScriptBlock -ScriptBlock $sb -ArgumentList $argList.ToArray() @conn
        foreach ($r in $results) {
            $collected.Add($r)
            $r
        }
    }

    end {
        if ($OutFile) {
            $lines = New-Object System.Collections.Generic.List[string]
            $first = $true
            foreach ($r in $collected) {
                if (-not $first) { $lines.Add(''); $lines.Add(('=' * 70)); $lines.Add('') }
                foreach ($line in (Format-Snapshot $r)) { $lines.Add($line) }
                $first = $false
            }

            $dir = Split-Path -Parent $OutFile
            if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
            }
            Set-Content -LiteralPath $OutFile -Value $lines -Encoding UTF8
            Write-Verbose "Wrote status report to $OutFile"
        }
    }
}
