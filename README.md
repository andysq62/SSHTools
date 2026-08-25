# SSHTools

A PowerShell module for installing, configuring, and troubleshooting **Win32-OpenSSH** (`sshd`)
on Windows. It packages the ad-hoc administration and SFTP-chroot troubleshooting steps from this
repo into proper functions.

Every function can target:

| Target | How |
|---|---|
| The local machine | call with no target parameters |
| A remote computer | `-ComputerName <name>` (optionally `-Credential`) |
| An established session | `-Session <PSSession>` |

`-ComputerName` and `-Session` are mutually exclusive. Remote execution uses PowerShell Remoting
(WinRM), so the work runs *in the target's context* — installing, backing up, and permission fixes
all happen on the machine you point at.

## Install

Copy this repo's contents into a folder named `SSHTools` on `$env:PSModulePath` (e.g.
`C:\Program Files\WindowsPowerShell\Modules\SSHTools`), or import it directly from a clone:

```powershell
Import-Module .\SSHTools.psd1
```

## Functions

| Function | Purpose | Replaces |
|---|---|---|
| `Get-OpenSSHInstallation` | Detect in-box vs. installed OpenSSH, versions, client on PATH, sshd service state | `Get-OpenSSHType`, `Get-OpenSSHVersion` |
| `Install-OpenSSH` | Download the latest Win32-OpenSSH MSI, report SHA256, optionally install | `Get-OpenSSH` |
| `Get-OpenSSHFirewallRule` | List OpenSSH firewall rules **with their profile scope** | `Get-SSHFirewallRule`, `Get-OpenSSHFirewallProfile` |
| `Set-OpenSSHFirewallRule` | Rescope the sshd rule (default: Domain, Private) | `Set-OpenSSHFirewallRule` |
| `Test-SSHDListening` | Confirm sshd is bound and listening on a port | `Get-IsSSHDBoundToPort` |
| `Backup-OpenSSHConfiguration` | Copy `%ProgramData%\ssh` to a timestamped backup folder | `Copy-SSHConfigBackup` |
| `Test-OpenSSHStrictModesPath` | Walk a chroot/keys path to root, flag ACEs that break StrictModes pubkey auth | (new — diagnostic) |
| `Repair-OpenSSHPathPermission` | Remove an over-broad group (default Authenticated Users) from a path chain | `Set-OpenSSHPermissions` |
| `Restart-SSHDService` | Restart sshd and report status | (new — workflow helper) |

## Examples

```powershell
# What OpenSSH is on the SFTP server, and is sshd listening?
Get-OpenSSHInstallation -ComputerName coltst19xfer
Test-SSHDListening       -ComputerName coltst19xfer

# Firewall rule scoped wrong? Inspect, then fix (a Private-only rule won't match a domain NIC).
Get-OpenSSHFirewallRule -ComputerName coltst19xfer
Set-OpenSSHFirewallRule -ComputerName coltst19xfer -Profile Domain,Private

# Diagnose the "silent pubkey rejection" chroot case, then remediate.
Test-OpenSSHStrictModesPath  -ComputerName coltst19xfer -Path 'D:\AU\Data'
Repair-OpenSSHPathPermission -ComputerName coltst19xfer -Path 'D:\' -Recurse
Restart-SSHDService          -ComputerName coltst19xfer

# Reuse one session for a whole workflow.
$s = New-PSSession coltst19xfer
Backup-OpenSSHConfiguration -Session $s -Destination D:\Backups\ssh
Get-OpenSSHInstallation     -Session $s
Remove-PSSession $s
```

State-changing functions (`Install-OpenSSH`, `Set-OpenSSHFirewallRule`,
`Backup-OpenSSHConfiguration`, `Repair-OpenSSHPathPermission`, `Restart-SSHDService`) support
`-WhatIf` and `-Confirm`.

## Tests

[Pester](https://pester.dev) v5 tests live in `Tests/` — one file per function, plus the
manifest and the dispatcher. They mock the remoting layer, so they run offline and change
nothing on the machine:

```powershell
Invoke-Pester -Path .\Tests
```

One test (the `-Session` routing branch) needs a loopback PSSession and self-skips where
WinRM is not configured.

## Background

The chroot / StrictModes / firewall-profile issues these functions target are documented in
[`docs/openssh10-sftp-chroot-pubkey-troubleshooting.md`](docs/openssh10-sftp-chroot-pubkey-troubleshooting.md).
