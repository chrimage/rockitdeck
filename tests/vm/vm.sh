#!/usr/bin/env bash
# Disposable Debian 13 netinst test VM. Usage: VM_STATE_DIR=DIR vm.sh ACTION
# Actions: fetch install boot bootstrap ssh view stop destroy. See README.md.
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo=$(cd -- "$here/../.." && pwd -P)
die() { printf 'vm.sh: %s\n' "$*" >&2; exit 1; }

action=${1:-}; shift || true
[[ -n $action ]] || die "usage: VM_STATE_DIR=DIR $0 {fetch|install|boot|bootstrap|ssh|view|stop|destroy}"
[[ -n ${VM_STATE_DIR:-} ]] || die 'VM_STATE_DIR is required'
s=$(realpath -m -- "$VM_STATE_DIR")
[[ $s != / && $s != "$HOME" ]] || die "unsafe state directory: $s"
[[ $s/ != "$repo"/* ]] || die "state directory must be outside the repository ($repo)"

port=${VM_SSH_PORT:-2222}; display=${VM_VNC_DISPLAY:-7}; http_port=${VM_HTTP_PORT:-18080}
for n in "$port" "$display" "$http_port"; do [[ $n =~ ^[0-9]+$ ]] || die "not a number: $n"; done
((port > 0 && port < 65536 && http_port > 0 && http_port < 65536 && display < 59636)) || die 'port or display out of range'

version=13.7.0
iso_name=debian-$version-amd64-netinst.iso
iso_bases=("https://cdimage.debian.org/cdimage/release/$version/amd64/iso-cd"
           "https://cdimage.debian.org/cdimage/archive/$version/amd64/iso-cd")
marker=$s/.rockitdeck-vm-state
disk=$s/disk.qcow2; pidfile=$s/qemu.pid; key=$s/ssh/lab_key; known=$s/known_hosts

running() {
    [[ -f $pidfile ]] || return 1
    local pid; pid=$(< "$pidfile")
    [[ $pid =~ ^[0-9]+$ ]] && grep -aqF -- "$disk" "/proc/$pid/cmdline" 2>/dev/null
}
vm_ssh() {
    ssh -i "$key" -p "$port" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
        -o "UserKnownHostsFile=$known" -o ConnectTimeout=5 debian@127.0.0.1 "$@"
}
wait_ssh() {
    local i; for ((i = 0; i < 60; i++)); do vm_ssh true 2>/dev/null && return 0; sleep 3; done
    die 'VM did not accept SSH within 180s'
}
qemu() {  # extra args are appended; the disk path must stay on the command line
    qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp 2 -m 2048 \
        -drive "file=$disk,if=virtio,format=qcow2" \
        -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$port-:22" -device virtio-net-pci,netdev=net0 \
        -device virtio-vga -device qemu-xhci -device usb-tablet \
        -display none -vnc "127.0.0.1:$display" -pidfile "$pidfile" \
        -qmp "unix:$s/qmp.sock,server=on,wait=off" "$@"
}
need_state() { [[ -f $marker ]] || die "$s is not a state directory made by this script; run fetch first"; }

case $action in
fetch)
    if [[ ! -f $marker && -d $s ]]; then
        shopt -s nullglob dotglob
        entries=("$s"/*)
        ((${#entries[@]} == 0)) || die 'refusing to claim an existing nonempty directory'
        shopt -u nullglob dotglob
    fi
    mkdir -p "$s/iso" "$s/logs"; : > "$marker"
    cd "$s/iso"
    ok=
    for base in "${iso_bases[@]}"; do
        curl -fsSL --proto '=https' -o SHA512SUMS.part "$base/SHA512SUMS" || continue
        grep -F " $iso_name" SHA512SUMS.part > SHA512SUMS.one || continue
        mv SHA512SUMS.one SHA512SUMS
        if [[ -f $iso_name ]] && sha512sum -c --quiet SHA512SUMS 2>/dev/null; then ok=1; break; fi
        curl -fL --proto '=https' -o "$iso_name.part" "$base/$iso_name" || continue
        mv "$iso_name.part" "$iso_name"
        sha512sum -c SHA512SUMS && { ok=1; break; }
        rm -f "$iso_name"
    done
    rm -f SHA512SUMS.part SHA512SUMS.one "$iso_name.part"
    [[ -n $ok ]] || die "could not download and verify $iso_name"
    isoinfo -R -i "$iso_name" -x /install.amd/vmlinuz > vmlinuz
    isoinfo -R -i "$iso_name" -x /install.amd/initrd.gz > initrd.gz
    [[ -s vmlinuz && -s initrd.gz ]] || die 'kernel/initrd extraction failed'
    printf 'Verified %s; kernel and initrd extracted to %s\n' "$iso_name" "$s/iso" ;;
install)
    need_state
    [[ ! -e $disk ]] || die "refusing to install over existing disk $disk (run destroy first)"
    running && die 'VM is already running'
    for f in "$iso_name" vmlinuz initrd.gz; do [[ -s $s/iso/$f ]] || die "missing $s/iso/$f; run fetch first"; done
    mkdir -p "$s/ssh" "$s/http" "$s/logs"; chmod 700 "$s/ssh"
    rm -f "$key" "$key.pub" "$known"
    ssh-keygen -q -t ed25519 -N '' -C vm-lab -f "$key"
    tpl=$(< "$here/preseed.cfg.in"); pub=$(< "$key.pub")
    printf '%s\n' "${tpl//@SSH_PUBLIC_KEY@/$pub}" > "$s/http/preseed.cfg"   # only file ever served
    qemu-img create -q -f qcow2 "$disk" 24G
    python3 -I -m http.server "$http_port" --bind 127.0.0.1 --directory "$s/http" >"$s/logs/http.log" 2>&1 &
    trap 'kill $! 2>/dev/null || true' EXIT
    printf 'Installing (network required); this blocks until the installer powers off.\n'
    qemu -drive "file=$s/iso/$iso_name,media=cdrom,readonly=on" \
        -kernel "$s/iso/vmlinuz" -initrd "$s/iso/initrd.gz" \
        -append "auto=true priority=critical locale=en_US.UTF-8 keymap=us hostname=debian-vm domain= console=ttyS0,115200n8 preseed/url=http://10.0.2.2:$http_port/preseed.cfg" \
        -serial "file:$s/logs/install-serial.log" -no-reboot
    printf 'Installer exited. Next: VM_STATE_DIR=%s %s boot\n' "$s" "$0" ;;
boot)
    need_state; [[ -f $disk ]] || die 'no disk; run install first'
    running && die 'VM is already running'
    qemu -boot order=c -serial "file:$s/logs/boot-serial.log" -daemonize
    printf 'Booted. SSH 127.0.0.1:%s, VNC display :%s\n' "$port" "$display" ;;
bootstrap)
    need_state; running || die 'VM is not running; run boot first'
    : "${VM_REPOSITORY:?VM_REPOSITORY (git URL reachable from the VM) is required}"
    : "${VM_OWNER:?VM_OWNER (owner name) is required}"
    args=(--noninteractive --owner "$VM_OWNER" --repository "$VM_REPOSITORY")
    [[ -z ${VM_CHANNEL:-} ]] || args+=(--channel "$VM_CHANNEL")
    case ${VM_UPDATES:-} in
        '') ;; enable) args+=(--enable-updates) ;; disable) args+=(--disable-updates) ;;
        *) die 'VM_UPDATES must be enable or disable' ;;
    esac
    wait_ssh
    vm_ssh 'cat > /home/debian/install.sh' < "$repo/install.sh"
    printf -v cmd '%q ' sudo bash /home/debian/install.sh "${args[@]}"
    vm_ssh "$cmd" ;;
ssh) need_state; vm_ssh "$@" ;;
view) need_state; exec vncviewer -Shared "127.0.0.1::$((5900 + display))" ;;
stop)
    need_state; running || { printf 'Not running.\n'; exit 0; }
    vm_ssh sudo systemctl poweroff || true
    for ((i = 0; i < 30; i++)); do running || { printf 'Stopped.\n'; exit 0; }; sleep 2; done
    die 'VM still running after 60s' ;;
destroy)
    [[ ${VM_DESTROY:-} == yes ]] || die 'set VM_DESTROY=yes to confirm'
    need_state; running && die 'VM is running; stop it first'
    # Only known generated files; downloaded ISO/kernel/initrd in iso/ are kept.
    rm -f "$disk" "$pidfile" "$s/qmp.sock" "$known" "$key" "$key.pub" "$s/http/preseed.cfg" \
          "$s/logs/install-serial.log" "$s/logs/boot-serial.log" "$s/logs/http.log"
    rmdir "$s/ssh" "$s/http" "$s/logs" 2>/dev/null || true
    printf 'VM disk and generated files removed from %s (iso/ kept)\n' "$s" ;;
*) die "unknown action: $action" ;;
esac
