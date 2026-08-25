# OpenSSH 10 Upgrade — SFTP Pubkey Authentication Failure (server01)

## Summary

After upgrading Win32-OpenSSH to version 10 on `server01`, the ERP colleague's SFTP client could not connect. Troubleshooting uncovered **three independent, layered issues** — not one root cause:

1. A firewall rule scoped to the wrong network profile (blocked all traffic, including the initial connectivity test)
2. Overly broad NTFS permissions (`Authenticated Users: Modify`) on the chroot path, which silently fails Win32-OpenSSH's `StrictModes` pubkey check
3. `AuthorizedKeysFile` resolving *inside* the chroot jail once `ChrootDirectory` was active, pointing at a file that didn't exist

Each layer produced a different symptom, which is why this took multiple passes to isolate.

---

## Timeline of Symptoms → Root Cause → Fix

### 1. Client reported server version as "9.5"

**Symptom:** `sftp -vv` showed `OpenSSH_for_Windows_9.5p1` immediately, suggesting the server hadn't upgraded.

**Root cause:** That line is the **local client's own version**, printed before any connection is made — not a banner read from the server. Confirmed via:

```powershell
Invoke-Command -ComputerName server01 { ssh -V }
# OpenSSH_for_Windows_10.0p2 Win32-OpenSSH-GitHub, LibreSSL 4.2.0
```

The server had upgraded correctly; the client machine (client01) simply had an older OpenSSH client installed locally.

**Resolution:** No action needed — this was a red herring. Good to know for next time: always confirm server version via `Invoke-Command` or a live connection banner, not the first line of local client output.

---

### 2. Connection timed out (`TcpTestSucceeded : False`)

**Symptom:**

```powershell
Test-NetConnection server01 -Port 22
# PingSucceeded : True
# TcpTestSucceeded : False
```

**Root cause:** The Windows Firewall rule for sshd (`OpenSSH SSH Server Preview (sshd)`) was scoped only to the `Private` profile. The server's active NIC was classified `DomainAuthenticated`, so the rule never applied — despite `Get-NetFirewallRule` showing `Enabled: True`.

**How to check:**

```powershell
# On the SFTP server
Get-NetTCPConnection -LocalPort 22 -State Listen
Get-NetFirewallRule -DisplayName "*OpenSSH*" | Select DisplayName, Enabled, Direction, Action
Get-NetFirewallRule -DisplayName "OpenSSH SSH Server Preview (sshd)" | Get-NetFirewallProfile
Get-NetConnectionProfile
```

Key insight: **domain-joined does not guarantee the firewall profile is `Domain`.** Multiple NICs, delayed DC contact at boot, or a manually-scoped rule can all cause a mismatch between AD membership and what Windows Firewall is actually evaluating against.

**Fix:**

```powershell
Set-NetFirewallRule -DisplayName "OpenSSH SSH Server Preview (sshd)" -Profile Domain,Private
```

**Verify:**

```powershell
# From the client
Test-NetConnection server01 -Port 22
# TcpTestSucceeded should now be True
```

---

### 3. Connected, but pubkey auth silently rejected → fell back to password

**Symptom:** Once the firewall was fixed, `sftp -vv -i <key>` completed the full SSH handshake but the offered key was rejected with no explanit reason, falling through to keyboard-interactive/password:

```
debug1: Offering public key: ...id_ed25519 ...
debug2: we sent a publickey packet, wait for reply
debug1: Authentications that can continue: publickey,password,keyboard-interactive
```

**Investigation path:**

- Confirmed the service account (`svcfiletransfers`) is a member of local **Administrators**.
- Checked for `administrators_authorized_keys` (the default key file Win32-OpenSSH uses for admin accounts) — it didn't exist on either test or prod, and **prod worked fine without it**, ruling out the standard admin-account default-path theory.
- Compared `sshd_config` between prod and test and found **test had `Match User` blocks that prod did not**, including one for `svcfiletransfers` with:

```
Match User domain\svcfiletransfers
    ChrootDirectory "D:\Data"
    Banner "C:\Test\testbanner.txt"
    AllowTCPForwarding no
    X11Forwarding no
    ForceCommand internal-sftp

PubkeyAcceptedAlgorithms +ssh-rsa
```

**Root cause:** Win32-OpenSSH's `StrictModes` (default `yes`) validates ownership and write permissions on the `ChrootDirectory` path **and every parent directory up to the drive root** before allowing pubkey auth. `icacls` revealed:

```
NT AUTHORITY\Authenticated Users:(M)   [inherited from D:\ down through D:\Data]
```

`Authenticated Users` is a built-in Windows group automatically populated with **any account that successfully authenticates** — effectively all domain users/computers/services. Having Modify access at the root of the chroot path fails the StrictModes check, and sshd rejects the key silently (no useful error on either side).

**Confirmed via safe test** (temporarily disabling the check):

```
StrictModes no   # added under the Match User block, sshd restarted
```

`psftp -v -i <ppk key>` immediately succeeded — proving the theory before touching permissions.

**Permanent fix** — remove the overly broad grant instead of leaving StrictModes disabled:

```powershell
# Check what else lives on D:\ before making changes
Get-ChildItem D:\ | Select Name

# Remove Authenticated Users write access, recursively
icacls D:\ /remove:g "NT AUTHORITY\Authenticated Users" /T /C

# Verify
icacls D:\
icacls "D:\Data"
```

Then **revert `StrictModes` back to enabled**:

```powershell
# Remove/comment "StrictModes no" under the Match User block
Restart-Service sshd
```

---

### 4. Pubkey still rejected after permissions fix — key file not found

**Symptom:** With `StrictModes` back to `yes` and the `Authenticated Users` permission fixed, the key was *still* refused.

**Root cause:** With `ChrootDirectory` active, the relative `AuthorizedKeysFile .ssh/authorized_keys` (inherited from the global directive) resolves **inside the chroot jail**, not against the account's Windows profile. Effectively sshd was looking for:

```
D:\Data\.ssh\authorized_keys
```

— a file that never existed, since the key had only ever lived under `C:\Users\svcfiletransfers\.ssh\`.

**Check:**

```powershell
Test-Path "D:\Data\.ssh\authorized_keys"
```

---

## Best-Practice Fix: Move `AuthorizedKeysFile` Outside the Chroot

Rather than placing `authorized_keys` inside the data payload folder (mixes SSH infra config into a folder meant for ERP/vendor file drops, and re-inherits the same StrictModes exposure), override the path per-account to a dedicated location outside the chroot. Key lookup happens **before** chroot is applied to the session, so this works cleanly:

```
Match User domain\svcfiletransfers
    ChrootDirectory "D:\Data"
    AuthorizedKeysFile "C:/ProgramData/ssh/authorized_keys_svcfiletransfers"
    Banner "C:\Test\testbanner.txt"
    AllowTCPForwarding no
    X11Forwarding no
    ForceCommand internal-sftp
```

**Create and lock down the file:**

```powershell
New-Item -ItemType Directory -Path C:\ProgramData\ssh -Force
New-Item -ItemType File -Path "C:\ProgramData\ssh\authorized_keys_svcfiletransfers" -Force
Add-Content -Path "C:\ProgramData\ssh\authorized_keys_svcfiletransfers" -Value "ssh-ed25519 AAAA... svcfiletransfers@..."

icacls "C:\ProgramData\ssh\authorized_keys_svcfiletransfers" /inheritance:r
icacls "C:\ProgramData\ssh\authorized_keys_svcfiletransfers" /grant "SYSTEM:F" /grant "Administrators:F"
```

**Restart and retest:**

```powershell
Restart-Service sshd
```

### Why `C:\ProgramData\ssh` over `C:\Users\<account>\.ssh`

Not a hard requirement, but the conventional choice:

- Keeps all SSH infrastructure (host keys, `sshd_config`, key files) in one consistent location
- Doesn't depend on the service account's user profile existing/being loaded
- Avoids inheriting broader default profile-folder permissions that can re-trigger StrictModes issues
- Cleaner separation for shared service accounts vs. personal interactive logins

### Multiple service accounts, one config line

If managing more than one chrooted service account, use the `%u` token so each gets its own isolated key file without duplicating config:

```
Match Group domain\SFTPServiceAccounts
    AuthorizedKeysFile "C:/ProgramData/ssh/authorized_keys_%u"
    ChrootDirectory "D:\Data\%u"
    ForceCommand internal-sftp
```

Avoid pointing two accounts at the *same* `authorized_keys` file — any key in a shared file authenticates any account referencing it, which defeats per-account auditing/separation.

---

## Useful Diagnostic Commands Reference

| Purpose | Command |
| --- | --- |
| Test raw TCP connectivity | `Test-NetConnection <host> -Port 22` |
| Verbose SFTP debug (OpenSSH client) | `sftp -vvv -i <key> user@host` |
| Verbose SFTP debug (PuTTY, `.ppk` keys) | `psftp -v -i <key.ppk> user@host` |
| Verbose SSH debug (PuTTY) | `plink -v -i <key.ppk> user@host` |
| Confirm actual server version | `Invoke-Command -ComputerName <host> { ssh -V }` |
| Check firewall rule + profile scope | `Get-NetFirewallRule -DisplayName "*OpenSSH*" \| Get-NetFirewallProfile` |
| Check active network profile | `Get-NetConnectionProfile` |
| Confirm sshd is listening | `Get-NetTCPConnection -LocalPort 22 -State Listen` |
| Check NTFS permissions | `icacls <path>` |
| Remove a group's access recursively | `icacls <path> /remove:g "<group>" /T /C` |
| Confirm key fingerprint match | `ssh-keygen -lf <authorized_keys path>` |

---

## Key Takeaways

- **`sftp -i` / `plink -i` / `psftp -i` all accept a private key path** — OpenSSH-format keys work with the native `sftp`/`ssh`/`scp` clients; `.ppk` files need `plink`/`psftp` (or conversion via PuTTYgen/`ssh-keygen`).
- **Silent pubkey rejection with fallback to password is almost always a server-side authorized_keys/permissions issue**, not a bad key or wrong algorithm — the client-side debug output won't tell you why, only that it happened.
- **`ChrootDirectory` on Win32-OpenSSH triggers `StrictModes` validation on the entire path up to the drive root.** Any non-Admin/SYSTEM write access anywhere in that chain will silently break pubkey auth.
- **`AuthorizedKeysFile` resolves relative to the chroot jail once `ChrootDirectory` is active**, unless explicitly overridden in the same `Match` block with an absolute path outside the jail.
- **Chroot + `internal-sftp` is the stronger, more correct way to restrict an SFTP-only account to a folder tree**, compared to the `sftp-server.exe -d` flag approach (which only sets a starting directory, not a real filesystem boundary).
