# RockitDeck

**A distraction-free, personal writing appliance built from ordinary computers and open-source software.**

## The idea

RockitDeck turns a laptop or desktop into a device whose primary purpose is writing. Power it on, return to the work in progress, and write. The operating system, application launcher, and administrative machinery stay out of the way until deliberately needed.

It should feel like a finished appliance, not a Linux desktop that someone has been asked to tolerate.

RockitDeck is intended for people working on anything from notes and journals to multiple books, with simple navigation between manuscripts, chapters, and research. The writer should not have to understand Linux, Git, or Ansible to use it.

## The experience

1. **Open it and write.** The device automatically enters its writing environment and restores the previous workspace or document.
2. **Stay focused.** The editor owns the screen. Ordinary application launchers, notifications, and desktop clutter are absent from the normal workflow.
3. **Keep the useful controls.** Battery, networking, volume, and power actions remain accessible without exposing a general-purpose desktop.
4. **Save without thinking about it.** Writing is stored locally using normal files, with the editor responsible for autosave and session restoration.
5. **Keep control of the work.** Internet access, cloud synchronization, and online accounts are optional. The device must remain useful offline.
6. **Leave an escape hatch.** An administrator can access a conventional environment for troubleshooting and maintenance. The writing experience is a *soft kiosk*, not a security boundary.

## Design principles

- **Writer first.** Optimize for concentration, predictable behavior, readable typography, and minimal friction.
- **Local first.** Manuscripts belong to the writer, in ordinary accessible files. Never make the network a dependency for writing.
- **Appliance on the surface, Linux underneath.** Hide unnecessary complexity without removing the ability to maintain the system.
- **Configuration as code.** Build the environment declaratively and reproducibly rather than relying on a series of manual desktop tweaks.
- **Use existing mechanisms.** Prefer Debian, GNOME, systemd, Ansible, and established tools over RockitDeck-specific daemons or frameworks.
- **Personal, not hardcoded.** Every installation can have its own identity and settings without forking the project.
- **Protect user state.** Reconfiguration must not overwrite manuscripts, working sessions, or personal editing preferences.
- **Small, incremental changes.** Validate on a disposable VM before deploying changes to a real writing device.

## Technical direction

The initial implementation uses **Debian 13**, **GNOME on Wayland**, and **Zettlr**. Zettlr supplies the writing experience and organization of multiple projects; GNOME supplies the minimal shell and basic system controls; Ansible supplies reproducible deployment.

A standard unprivileged account named `writer` runs the writing session. An existing administrator account provides maintenance access.

Keep writable user state separate from managed configuration:

| Location | Purpose |
| --- | --- |
| `/home/writer/Writing/` | Manuscripts, projects, notes, and research; initial Zettlr workspace |
| `/home/writer/.config/Zettlr/` | Zettlr preferences, session state, and application data |
| `/etc/rockitdeck/device.yml` | Persistent local device identity and configuration |
| `/etc/default/rockitdeck` | Systemd/`ansible-pull` environment settings, including repository and branch |

The installer asks for an owner's name, an update channel (`stable` or `testing`), and whether automatic updates on reboot are enabled. Each option also has a noninteractive CLI equivalent. The hostname is derived from the owner's **first** name plus `deck`, while the account remains `writer` on every device.

## The update loop

RockitDeck should be maintainable remotely **without SSH or access to the device's network**:

**Develop locally → test in a VM → push an approved Git change → user chooses to reboot → RockitDeck applies the change.**

A systemd unit invokes `ansible-pull --only-if-changed` against the device's selected branch before the graphical session begins. Automatic updates are opt-in. The update attempt is time-bounded; an offline or unsuccessful update must not indefinitely block the writing session. No update process may initiate an unattended reboot.

Keep this mechanism simple, using the existing Git, Ansible and systemd facilities. Updates are not transactional: a failed Ansible run can leave partial changes. That limitation should be understood and tested rather than concealed.

## Development model

The Git repository contains the installer, playbooks, managed configuration, reusable tests, and documentation. Host-specific development helpers, generated VM disks, temporary experiments, credentials, and raw test output stay outside it. Contributors do not need a particular workspace layout.

## Room to grow

RockitDeck should remain hardware-independent at its core, with device-specific configuration added as optional Ansible roles where warranted. Over time, possible enhancements include refined power management, keyboard layouts, better recovery, and optional backup or synchronization. None should complicate the normal act of writing or be required for the initial appliance.

**Success means the owner thinks about what to write, not how the computer works.**
