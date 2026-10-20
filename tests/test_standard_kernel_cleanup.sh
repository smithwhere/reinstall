#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export state=$scratch/state
sed "s|/boot/|$state/boot/|g" "$root/update-kernel.sh" >"$scratch/updater.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
uname() { echo aarch64; }
sleep() { :; }
apt-mark() { :; }
dpkg-query() {
    if [ "$*" = '-W -f=${db:Status-Status} ${binary:Package}\n' ]; then
        [ ! -e "$state/query-failure" ] || return 1
        sed 's/^/installed /' "$state/packages"
    else
        echo 'linux-image-amd64 6.12.113-1'
    fi
}
apt-get() {
    local action= arg
    for arg in "$@"; do
        case "$arg" in update | install | purge) action=$arg ;; esac
    done
    case "$action" in
    update) : ;;
    install)
        [ ! -e "$state/install-failure" ] || return 100
        printf 'kernel\n' >"$state/boot/vmlinuz-$image_release"
        if [ ! -e "$state/missing-initrd" ]; then
            printf 'initrd\n' >"$state/boot/initrd.img-$image_release"
        fi
        ;;
    purge)
        printf '%s\n' "$*" >"$state/purge"
        [ ! -e "$state/purge-failure" ] || return 100
        local removed=false
        for arg in "$@"; do
            case "$arg" in
            -y) removed=true ;;
            *) if $removed; then
                grep -Fxv "$arg" "$state/packages" >"$state/remaining" || :
                mv "$state/remaining" "$state/packages"
            fi ;;
            esac
        done
        ;;
    *) return 90 ;;
    esac
}
update-grub() { touch "$state/grub-regenerated"; }
export -f uname sleep apt-mark dpkg-query apt-get update-grub
reset_state() {
    rm -rf "${state:?}"
    mkdir -p "$state/boot"
    export image_release=6.12.113+deb13-amd64
    printf '%s\n' linux-base linux-image-amd64 linux-image-6.12.113+deb13-amd64 \
        linux-image-cloud-amd64 linux-image-6.12.107+deb13-cloud-amd64 \
        linux-image-6.12.113+deb13-cloud-amd64 >"$state/packages"
}
run_update() { bash "$scratch/updater.sh" "${1:-linux-image-amd64}" >"$state/output" 2>&1; }

reset_state
run_update || fail 'Standard kernel migration failed.'
! grep -q cloud "$state/packages" || fail 'Cloud kernels remain installed and can stay the GRUB default.'
grep -qx linux-base "$state/packages" || fail 'Non-kernel infrastructure was removed.'
grep -qx linux-image-6.12.113+deb13-amd64 "$state/packages" || fail 'The standard kernel was removed.'
[ -e "$state/grub-regenerated" ] || fail 'GRUB was not regenerated after cloud removal.'
echo 'PASS: the standard kernel is installed before old cloud kernels are removed and GRUB is refreshed.'

reset_state
touch "$state/missing-initrd"
if run_update; then fail 'Migration succeeded without a standard initrd.'; fi
[ ! -e "$state/purge" ] || fail 'Cloud kernels were removed without a bootable standard replacement.'
echo 'PASS: missing standard initrd preserves old kernels and fails installation.'

reset_state
touch "$state/install-failure"
if run_update; then fail 'A failed standard install succeeded.'; fi
[ ! -e "$state/purge" ] || fail 'Old kernels were removed after a failed install.'

reset_state
touch "$state/purge-failure"
if run_update; then fail 'A failed cloud removal was ignored.'; fi
echo 'PASS: install and cloud-removal errors cannot silently finish migration.'

reset_state
touch "$state/query-failure"
if run_update; then fail 'An unreadable installed-package inventory was ignored.'; fi
[ ! -e "$state/purge" ] || fail 'Purged kernels using an unreadable inventory.'
echo 'PASS: package inventory failures stop migration.'

reset_state
image_release=6.8.0-1-generic
printf '%s\n' linux-base linux-image-generic linux-image-6.8.0-1-generic \
    linux-virtual linux-image-virtual linux-aws linux-image-aws \
    linux-image-6.8.0-1-aws linux-image-6.8.0-1-azure \
    linux-image-6.8.0-1-gcp linux-image-6.8.0-1-oracle \
    linux-image-6.8.0-1-ibm linux-image-6.8.0-1-kvm >"$state/packages"
run_update linux-image-generic || fail 'Ubuntu optimized-kernel cleanup failed.'
[ "$(cat "$state/packages")" = "$(printf '%s\n' linux-base linux-image-generic linux-image-6.8.0-1-generic)" ] ||
    fail 'Ubuntu cleanup kept optimized kernels or removed standard packages.'
echo 'PASS: Ubuntu optimized kernels are removed while generic images and linux-base remain.'
