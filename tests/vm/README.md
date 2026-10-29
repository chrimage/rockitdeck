# Disposable Debian 13 VM test workflow

`vm.sh` creates a minimal Debian 13.7 (netinst, no desktop) QEMU/KVM VM, then
runs the repository's `install.sh` in it. It is a test tool, not product
runtime. All generated files live in a state directory you choose, which must
be **outside** this repository (the script refuses otherwise).

## Dependencies (host)

`qemu-system-x86_64` with KVM, `qemu-img`, `isoinfo` (genisoimage/xorriso
package providing it), `curl`, `sha512sum`, `python3`, OpenSSH client
(`ssh`, `ssh-keygen`), and TigerVNC `vncviewer` (only for `view`).

## Interface

`VM_STATE_DIR=<dir> tests/vm/vm.sh <action>` — configuration is by environment.

| Variable | Default | Used by |
| --- | --- | --- |
| `VM_STATE_DIR` | required | all |
| `VM_SSH_PORT` | `2222` (host loopback → guest 22) | all VM actions |
| `VM_VNC_DISPLAY` | `7` (loopback port 5907) | install, boot, view |
| `VM_HTTP_PORT` | `18080` (loopback preseed server) | install |
| `VM_REPOSITORY` | required | bootstrap (URL the **VM** can reach; the host is `10.0.2.2` from the guest) |
| `VM_OWNER` | required | bootstrap → `--owner` |
| `VM_CHANNEL` | unset (bootstrap default) | bootstrap → `--channel stable\|testing` |
| `VM_UPDATES` | unset (bootstrap default, off) | bootstrap → `enable` or `disable` |
| `VM_DESTROY` | must be `yes` | destroy |

Actions:

- `fetch` downloads the Debian 13.7.0 netinst ISO, verifies its SHA512 against
  `SHA512SUMS` from the same HTTPS site (the GPG signature is not checked), and
  extracts `vmlinuz`/`initrd.gz` with `isoinfo`.
- `install` refuses if a disk exists. It makes a fresh lab SSH key, renders
  `preseed.cfg.in`, serves only that preseed on `127.0.0.1`, and runs the
  installer (2 GB RAM, 24 GB disk) until it powers off (`-no-reboot`).
- `boot` starts the installed disk (no installer media), daemonized.
- `bootstrap` copies this checkout's `install.sh` to the VM and runs it with
  `sudo bash /home/debian/install.sh --noninteractive` and the configured options.
- `ssh [command...]` logs in as `debian`; host keys go to the state directory.
- `view` opens VNC via `vncviewer`; `stop` powers off via SSH, only the VM
  whose disk is in this state directory.
- `destroy` deletes the disk, key, known_hosts, preseed and logs. It refuses
  while running and without `VM_DESTROY=yes`. Downloaded `iso/` is kept.

## Example

```sh
export VM_STATE_DIR="$HOME/rockitdeck-vm"      # your choice, outside the repo
tests/vm/vm.sh fetch
tests/vm/vm.sh install                          # blocks until the installer exits
tests/vm/vm.sh boot
VM_REPOSITORY=https://github.com/chrimage/rockitdeck.git VM_OWNER='Jordan Lee' \
  VM_CHANNEL=testing VM_UPDATES=disable tests/vm/vm.sh bootstrap
tests/vm/vm.sh ssh
tests/vm/vm.sh ssh sudo reboot                # enter configured writing session
tests/vm/vm.sh view                           # human testing via TigerVNC
tests/vm/vm.sh stop
VM_DESTROY=yes tests/vm/vm.sh destroy           # then install again to recreate
```

For a fork, replace the repository URL with a reachable repository containing
the branch under test. For a private repository, provision noninteractive root Git
access in the guest first. Ports can be changed with the variables above to
avoid conflicts with other local VMs or HTTP servers. After `boot`, SSH may take
a few seconds to become available; `bootstrap` waits for it automatically.

## Security and scope

- `install` and the preseed use the network (Debian mirror and, for bootstrap,
  your repository) and **wipe `/dev/vda` of the VM only**. Never reuse the
  preseed on real hardware.
- The lab key is generated per install in `$VM_STATE_DIR/ssh`; it is never
  served. The `debian` account has no password and passwordless sudo: the host
  user who holds the key is fully trusted as root in the VM. SSH and VNC
  listen on host loopback only.
- Out of scope: custom ISOs, interactive/physical installs, hardening.
