# RockitDeck

A distraction-free Debian 13 writing appliance built with GNOME, Zettlr, Ansible and systemd. It stores writing in ordinary local files and remains useful offline.

- [Product vision](docs/VISION.md)
- [Development](docs/development.md) and [reproducible netinst VM workflow](tests/vm/README.md)

## Install

Start from **Debian 13 amd64**, with an existing administrator account, a suitable standard kernel, `curl`, CA certificates, sudo access and Internet connectivity. The installer adds the writing environment; it does not partition disks or install Debian.

```sh
curl -fsSL https://raw.githubusercontent.com/chrimage/rockitdeck/stable/install.sh | sudo bash
```

It asks for the owner's name, update channel (`stable` by default), and whether to enable automatic updates on reboot (**off** by default). Choose **yes** for the remote-maintenance workflow described below. Prompts read from the terminal, not from the downloaded script stream. The public repository is selected automatically; no GitHub account or token is needed on the device.

For a fully unattended installation:

```sh
curl -fsSL https://raw.githubusercontent.com/chrimage/rockitdeck/stable/install.sh |
  sudo bash -s -- --owner 'Jordan Lee' --channel stable --enable-updates --noninteractive
```

Reboot when installation reports success. The installer never reboots automatically.

This executes downloaded code as root: trust the source before running it. If you prefer to inspect it first, download `install.sh` to a file, review it, then run `sudo bash install.sh`. The same single-file script can be hosted at another HTTPS URL. `example.com` is only a placeholder, not an installation endpoint.

### Installer options

| Option | Meaning |
| --- | --- |
| `--owner NAME` | First or full owner name. The hostname is the normalized first name plus `deck`: `Jordan Lee` becomes `jordandeck`. The account always remains `writer`. |
| `--channel stable\|testing` | Git branch to follow; new devices default to `stable`. |
| `--enable-updates` / `--disable-updates` | Explicitly enable or disable boot updates. |
| `--repository URL` | Override the public repository, for forks or development. |
| `--noninteractive` | No prompts. Supply the owner on new devices; omitted channel/update options use their defaults. |

Existing device choices are preserved when rerunning the installer unless explicitly overridden.

## Remote maintenance

```text
Develop on testing → validate in a VM → publish approved changes to stable
→ owner chooses to reboot → device pulls and applies the changed configuration
```

The device initiates an outbound HTTPS connection to the public Git repository. You do not need SSH access to it, a shared LAN, a VPN, or its network address. Once automatic updates are enabled, the owner only needs to reboot; writing itself never depends on the network.

Before graphical login, `rockitdeck-update.service` invokes `ansible-pull --only-if-changed`. It follows the device's selected branch, skips unchanged repositories, uses a shared deployment lock and logs to journald. It never initiates a reboot.

- A NetworkManager readiness check waits at most 15 seconds, inside a total default update deadline of 300 seconds.
- An offline, failed or timed-out update does not require success before the writing session can start.
- Initial installation always applies the playbook, even if the checkout already exists.
- There is only one update toggle: the systemd unit's enabled state.

Administrator commands:

```sh
sudo systemctl enable rockitdeck-update.service
sudo systemctl disable rockitdeck-update.service
journalctl -u rockitdeck-update.service
```

To change a device's followed channel, rerun the installer with `--channel testing` or `--channel stable`. When publishing, change `testing` first and validate before advancing `stable`; publication to `stable` is an explicit release decision.

## Persistent state

| Location | Purpose |
| --- | --- |
| `/home/writer/Writing/` | Manuscripts, notes and research; initial workspace. |
| `/home/writer/.config/Zettlr/` | Personal preferences and session state. Seeded only if no configuration exists. |
| `/etc/rockitdeck/device.yml` | Schema-versioned owner identity and local playbook overrides. |
| `/etc/default/rockitdeck` | Repository URL and selected branch. |

Reconfiguration preserves this state. Writer autostart and shell-extension files are managed configuration and may be replaced by a deployment.

The stock netinst single-interface DHCP configuration is migrated to NetworkManager with a backup so GNOME can control it. Custom/static interface configurations and additional interface files are not rewritten. An administrator should migrate those manually if desktop network controls are wanted. `writer` receives Debian's `netdev` network-control permissions, not sudo privileges.

## Recovery and administrator access

This is a **soft kiosk**, not a security boundary. Ctrl+Alt+F3 reaches a conventional console; log in with the existing Debian administrator account for maintenance. That account retains its ordinary desktop settings, separate from the writing profile.

Updates are not transactional. A failure can leave partial changes. After a new commit is fetched, `--only-if-changed` skips it on subsequent boots even if its playbook failed. To retry unconditionally with saved settings, download the installer and run:

```sh
sudo bash install.sh --noninteractive
```

If a timeout interrupted package configuration, repair dpkg first with `sudo dpkg --configure -a` and resolve any reported dependency problems. Then rerun the installer. There is no automatic rollback or custom commit-tracking engine.

VM testing does not establish physical-device battery, Wi-Fi, suspend or sound behaviour. See [development.md](docs/development.md) for the validation procedure.
