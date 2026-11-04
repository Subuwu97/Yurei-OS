# Hyper-V enhanced sessions and audio

The basic Hyper-V Virtual Machine Connection console has no virtual sound card.
Yurei provides xrdp, an Xorg remote display, Plasma X11 and the PipeWire xrdp
module for enhanced-session sound redirection. The local desktop stays on
Plasma Wayland. Installing these packages does not enable remote access.

## Set up inside the guest

Open **Hyper-V Enhanced Session Setup** from the application menu, or run:

```sh
sudo yurei-hyperv enable
```

Set a non-empty password when asked. The dedicated `yurei-remote` account keeps
the remote desktop separate from the local live user. A live USB's account and
password disappear on reboot. The helper refuses a non-Hyper-V machine, root
logins, blank/locked passwords and any TCP listener. It uses Hyper-V sockets,
not an open network port. Certificates are generated locally on enable; the
ISO contains no shared private key. The remote account is not an administrator.

## Set up on Windows

Enable Enhanced Session Mode in Hyper-V Settings. With the VM shut down, open
PowerShell as administrator, substitute the actual VM name, and run:

```powershell
Set-VM -VMName '<your VM name>' -EnhancedSessionTransportType HvSocket
```

Start the VM and reconnect using Enhanced Session. Sign in as `yurei-remote`
with the password set in the guest. In the connection's local resources,
leave audio playback set to play on this computer.

Disable access with `sudo yurei-hyperv disable`. It stops the service without
removing the remote account's files.

## Validation

Recipe checks and account/listener guard tests run automatically. The ISO build
checks component installation, listener configuration, private-key absence and
disabled-by-default service state. Real Hyper-V enhanced-session playback must
still be verified on the Windows host before claiming the audio problem fixed.

Upstream references:
- https://github.com/neutrinolabs/xrdp
- https://github.com/neutrinolabs/xorgxrdp
- https://github.com/neutrinolabs/pipewire-module-xrdp
- https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/learn-more/enhanced-session-mode
