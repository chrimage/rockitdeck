#!/usr/bin/env bash
# Run as root on a minimal Debian 13 installation, for example:
#   curl -fsSL URL | sudo bash -s -- [options]
# Prompts read from /dev/tty, never from this script's own stdin.
set -euo pipefail
default_repository=https://github.com/chrimage/rockitdeck.git
usage() {
    printf '%s\n' 'Usage: install.sh [--owner NAME] [--repository URL] [--channel stable|testing]' \
      '                  [--enable-updates|--disable-updates] [--noninteractive]' \
      'Existing device settings are preserved unless explicitly overridden.' \
      'New devices default to stable and automatic updates OFF.' \
      'Without a terminal, supply required values by option and add --noninteractive.'
}
main() {
    local owner='' repository='' channel='' updates='' noninteractive=false
    local key value answer tty_open=false
    while (($#)); do
        case "$1" in
            --owner|--repository|--channel)
                (($# >= 2)) && [[ -n $2 && $2 != --* ]] || { usage >&2; exit 2; }
                case "$1" in
                    --owner) owner=$2 ;;
                    --repository) repository=$2 ;;
                    --channel) channel=$2 ;;
                esac
                shift 2 ;;
            --enable-updates|--disable-updates)
                [[ -z $updates ]] || { printf 'Specify only one update flag.\n' >&2; exit 2; }
                [[ $1 == --enable-updates ]] && updates=enabled || updates=disabled
                shift ;;
            --noninteractive) noninteractive=true; shift ;;
            --help|-h) usage; exit 0 ;;
            *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
        esac
    done
    [[ -z $channel || $channel == stable || $channel == testing ]] || { printf 'Invalid channel\n' >&2; exit 2; }
    [[ $EUID == 0 ]] || { printf 'Run the installer as root.\n' >&2; exit 1; }
    . /etc/os-release
    [[ $ID == debian && $VERSION_ID == 13 ]] || { printf 'Debian 13 is required.\n' >&2; exit 1; }
    exec 9>/run/lock/rockitdeck.lock
    flock --nonblock 9 || { printf 'Another deployment is running.\n' >&2; exit 1; }
    export DEBIAN_FRONTEND=noninteractive GIT_TERMINAL_PROMPT=0
    # stdin may be the script itself (curl | bash); child tools must not consume it.
    apt-get update </dev/null
    apt-get install -y --no-install-recommends ansible-core git ca-certificates python3-yaml </dev/null
    install -d -m 0755 /etc/rockitdeck /var/lib/rockitdeck /var/cache/rockitdeck
    if [[ -z $owner && -f /etc/rockitdeck/device.yml ]]; then
        owner=$(python3 - <<'PY'
import yaml
with open('/etc/rockitdeck/device.yml') as f:
    data=yaml.safe_load(f)
assert isinstance(data, dict) and data.get('schema_version') == 1, 'Unsupported device schema'
print(data['owner_name'])
PY
        )
    fi
    # EnvironmentFile values written by this installer are deliberately simple and
    # parsed as data, never sourced as shell code.
    if [[ -f /etc/default/rockitdeck ]]; then
        while IFS='=' read -r key value; do
            case "$key" in
                ROCKITDECK_REPOSITORY) [[ -n $repository ]] || repository=$value ;;
                ROCKITDECK_BRANCH) [[ -n $channel ]] || channel=$value ;;
            esac
        done < /etc/default/rockitdeck
    fi
    repository=${repository:-$default_repository}
    if [[ -z $updates ]] && systemctl cat rockitdeck-update.service >/dev/null 2>&1; then
        if systemctl is-enabled --quiet rockitdeck-update.service; then updates=enabled; else updates=disabled; fi
    fi
    if ! $noninteractive && [[ -z $owner || -z $channel || -z $updates ]]; then
        # Open the controlling terminal on a dedicated fd; fd 0 may be the script stream.
        if ( : </dev/tty ) 2>/dev/null; then
            exec 8</dev/tty
            tty_open=true
        fi
        $tty_open || {
            printf 'No terminal available for prompts. Rerun with --noninteractive and --owner NAME'
            printf ' (optionally --channel stable|testing and --enable-updates|--disable-updates).\n'
        } >&2
        $tty_open || exit 2
        if [[ -z $owner ]]; then printf 'Owner name: ' >&2; read -r -u 8 owner; fi
        if [[ -z $channel ]]; then printf 'Update channel [stable]: ' >&2; read -r -u 8 channel; fi
        if [[ -z $updates ]]; then
            printf 'Enable automatic updates on reboot? [y/N]: ' >&2; read -r -u 8 answer
            case "$answer" in y|Y|yes|YES) updates=enabled ;; ''|n|N|no|NO) updates=disabled ;; *) printf 'Expected yes or no.\n' >&2; exit 2 ;; esac
        fi
        exec 8<&-
    fi
    channel=${channel:-stable}; updates=${updates:-disabled}
    [[ -n $owner && -n $repository ]] || { printf 'Owner is required; use --owner.\n' >&2; exit 2; }
    [[ $channel == stable || $channel == testing ]] || { printf 'Invalid channel\n' >&2; exit 2; }
    # Keep EnvironmentFile interpolation unambiguous; no embedded shell syntax.
    [[ $repository =~ ^[a-zA-Z0-9:/@._~%+,-]+$ && $repository != -* ]] || { printf 'Unsupported repository URL characters.\n' >&2; exit 2; }
    python3 - "$owner" "$repository" "$channel" <<'PY'
import os,pathlib,sys,unicodedata,re,yaml
owner,repo,branch=sys.argv[1:]
parts=owner.split()
if not parts: raise SystemExit('Owner name must not be blank')
first=unicodedata.normalize('NFKD',parts[0]).encode('ascii','ignore').decode().lower()
first=re.sub('[^a-z0-9]','',first)
if not first or len(first)>59: raise SystemExit('First name must normalize to 1-59 ASCII letters/digits')
p=pathlib.Path('/etc/rockitdeck/device.yml')
state=yaml.safe_load(p.read_text()) if p.exists() else {'schema_version':1}
if not isinstance(state,dict) or state.get('schema_version')!=1: raise SystemExit('Unsupported device schema')
# Do not reset a locally customized hostname when the same owner is retained.
if state.get('owner_name') != owner or 'device_hostname' not in state:
    state['device_hostname']=first+'deck'
state['owner_name']=owner
for path,text in [(p,yaml.safe_dump(state,sort_keys=False)),(pathlib.Path('/etc/default/rockitdeck'),f'ROCKITDECK_REPOSITORY={repo}\nROCKITDECK_BRANCH={branch}\n')]:
    tmp=path.with_suffix('.new')
    tmp.write_text(text); tmp.chmod(0o644); os.replace(tmp,path)
PY
    ansible-pull --full --url "$repository" --checkout "$channel" \
        --directory /var/lib/rockitdeck/checkout --inventory localhost, --connection local local.yml </dev/null
    systemctl daemon-reload
    if [[ $updates == enabled ]]; then
        systemctl enable rockitdeck-update.service
    else
        systemctl disable rockitdeck-update.service
    fi
    printf 'RockitDeck configured. Automatic boot updates: %s. Reboot when ready.\n' "$updates"
}
main "$@"
