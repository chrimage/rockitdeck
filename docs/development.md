# Development

## Repository boundary

Keep product source, reusable tests and durable user/developer documentation here:

- `install.sh`, `local.yml` and `roles/`: installation and device configuration.
- `tests/`: host-safe checks and a reusable disposable-VM workflow.
- `README.md` and `docs/`: installation, maintenance, product vision and testing instructions.

Keep planning files, progress reports, personal notes, failed experiments, credentials, VM disks, installer media and generated test output outside the checkout. `ansible-pull` clones this repository but executes only `local.yml` and its roles; tests and documentation are not installed as runtime tools.

## Host-safe checks

From the repository root, with Python 3, Bash and Ansible available:

```sh
python3 -m unittest discover -s tests -v
ansible-playbook -i localhost, --syntax-check local.yml
```

These commands do not configure the development host. The dconf compilation and YAML-content checks require `dconf-cli` and PyYAML respectively; they report a skip if those dependencies are missing. Passing source checks alone does not verify a working appliance.

## VM validation

Use the [disposable Debian netinst workflow](../tests/vm/README.md) with an explicit state directory outside the repository. It installs minimal Debian without a desktop, then runs this checkout's `install.sh`. The preseed wipes the virtual `/dev/vda` disk and configures a key-only lab administrator; it is not a physical-device installer.

Validate the following before publishing changes:

1. **Installation:** install onto minimal Debian 13 amd64, reboot, and confirm automatic `writer` login to GNOME Wayland with maximized Zettlr and no settled Overview. Check the extension's runtime state, not just its installed files.
2. **Hosted entrypoint:** exercise the actual public HTTPS script through `curl | sudo bash` with terminal prompts, and exercise unattended `bash -s --` options without a terminal. A new installation should use the official repository and default to `stable` without requiring GitHub credentials.
3. **Writing:** enter text without a Save command, verify it reaches disk, and confirm the document/workspace is restored after reboot. Exercise Quick Settings and the administrator console escape.
4. **Reapplication:** rerun the installer and confirm idempotence, preserved manuscripts/preferences/device settings, and preservation of enabled and disabled update choices when no override is supplied.
5. **Updates:** push a visible configuration change to the test repository, reboot with updates enabled and read back the applied change. Reboot unchanged and check that the journal reports a skipped deployment.
6. **Failure behaviour:** in an isolated fixture repository and disposable VM, test a disconnected network, a deliberately failing playbook and a deliberately timed-out deployment. In each case the writing session must still start; restore the working repository and normal timeout afterward. Never publish deliberate failures to a device's production channel.
7. **Recovery:** confirm a manual installer rerun retries deployment after a failure, releases the deployment lock and preserves local state. Updates are not transactional; interrupted package configuration can need manual dpkg repair.
8. **Repeatability:** stop and destroy the disposable VM, recreate a fresh disk/key and install again. The workflow must refuse reinstall over an existing disk and destruction of a running VM.

Keep source revisions, logs, screenshots and observed results outside the repository. Distinguish desktop controls visible in a VM from physical battery, Wi-Fi, sound and suspend behaviour, which require hardware testing.

## Publishing

Develop on `testing`, validate in a VM, then advance `stable` only with release approval. Devices follow their selected branch over outbound HTTPS; deployment must not depend on developer SSH access, a shared LAN or an unattended reboot. Preserve device-local repository/channel choices unless explicitly overridden.
