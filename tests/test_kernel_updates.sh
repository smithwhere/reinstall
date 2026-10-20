#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export state=$scratch/state
mkdir -p "$state"

# Only APT/dpkg and waiting are replaced. Run the real updater in a subprocess;
# never invoke the installer's disk, network, bootloader or reboot operations.
apt-get() {
    printf '%s\n' "$*" >>"$state/calls"
    local action= arg
    for arg in "$@"; do
        case "$arg" in update | install) action=$arg ;; esac
    done
    case "$action" in
    update)
        if [ -f "$state/update-failure" ]; then
            echo 'E: Could not download security index' >&2
            return 100
        fi
        if [ -f "$state/partial-update" ]; then
            echo 'W: Failed to fetch security index; old ones used instead.' >&2
            return 0
        fi
        cp "$state/remote" "$state/candidate"
        ;;
    install)
        [ "${DEBIAN_FRONTEND:-}" = noninteractive ] || return 90
        [ -f "$state/candidate" ] || return 91
        if [ -f "$state/install-failures" ]; then
            local failures
            failures=$(cat "$state/install-failures")
            if [ "$failures" -gt 0 ]; then
                echo "$((failures - 1))" >"$state/install-failures"
                return 100
            fi
        fi
        printf '%s\n' "$arg" >"$state/package"
        cp "$state/candidate" "$state/installed"
        ;;
    *) return 92 ;;
    esac
}
apt-mark() { printf '%s\n' "$*" >>"$state/marks"; }
dpkg-query() {
    [ -f "$state/installed" ] || return 1
    printf '%s %s\n' "${@: -1}" "$(cat "$state/installed")"
}
sleep() { :; }
# This suite exercises APT, not the host's BIOS/GRUB. Console behaviour is
# tested against a disposable filesystem by test_bios_console.sh.
uname() { echo aarch64; }
export -f apt-get apt-mark dpkg-query sleep uname

fail() { echo "FAIL: $*" >&2; exit 1; }
reset_state() {
    rm -rf "${state:?}/"*
    echo 6.12.113-1 >"$state/remote"
}
run_update() {
    if [ ! -f "$root/update-kernel.sh" ]; then
        echo 'FAIL: no kernel updater is available to installation paths' >&2
        return 1
    fi
    bash "$root/update-kernel.sh" "$@" >"$state/output" 2>&1
}

reset_state
echo 6.12.107-1 >"$state/installed"
echo 6.12.107-1 >"$state/candidate"
run_update linux-image-cloud-amd64 || fail 'Updating an installed Debian cloud kernel failed.'
[ "$(cat "$state/installed")" = 6.12.113-1 ] || fail 'An installed kernel was skipped or stale indexes were reused.'
grep -qx 'manual linux-image-cloud-amd64' "$state/marks" || fail 'The updated meta-package can be autoremoved.'
echo 'PASS: installed Debian kernel updates from 6.12.107 to 6.12.113.'

# Keep release, architecture and cloud/HWE flavour from the caller. Do not pin
# Debian 13 or replace vendor kernels with generic ones.
for package in linux-image-amd64 linux-image-arm64 linux-image-cloud-arm64 \
    linux-image-virtual-hwe-22.04 linux-image-generic-hwe-24.04 \
    linux-image-aws linux-image-azure linux-image-gcp linux-image-oracle \
    linux-generic-hwe-24.04; do
    reset_state
    run_update "$package" || fail "Could not install $package."
    [ "$(cat "$state/package")" = "$package" ] || fail "Kernel flavour changed: $package."
done
echo 'PASS: absent kernels, architectures, HWE and cloud flavours are preserved.'

reset_state
echo 2 >"$state/install-failures"
run_update linux-image-cloud-amd64 || fail 'Transient install failures were not retried.'
[ "$(grep -c ' update$' "$state/calls")" = 3 ] || fail 'Each install retry must refresh the indexes.'
echo 'PASS: transient install failures refresh indexes and retry.'

for mode in update-failure partial-update; do
    reset_state
    touch "$state/$mode"
    if run_update linux-image-cloud-amd64; then
        fail "Failed or partial index refresh was reported as success: $mode."
    fi
    [ ! -f "$state/installed" ] || fail 'Installed from stale or incomplete indexes.'
done
echo 'PASS: hard and partial index failures stop installation.'

reset_state
echo 3 >"$state/install-failures"
if run_update linux-image-cloud-amd64; then
    fail 'Persistent package installation failure was reported as success.'
fi
[ ! -f "$state/marks" ] || fail 'Failed update was marked complete.'

reset_state
if run_update ''; then fail 'An empty kernel package was accepted.'; fi
[ ! -f "$state/calls" ] || fail 'APT ran without a kernel package.'
echo 'PASS: persistent failures and invalid input fail closed.'

# Exercise the actual cloud-image call sites and target boundary, not just the
# updater. Substitutes prevent real downloads and chroot operations on the host.
for function in chroot_update_kernel chroot_apt_install chroot_apt_update; do
    source <(sed -n "/^$function() {/,/^}/p" "$root/trans.sh")
done
export root
export confhome=https://raw.githubusercontent.com/smithwhere/reinstall/main
download() {
    [ "$1" = "$confhome/update-kernel.sh" ] || return 80
    cp "$root/update-kernel.sh" "$2"
}
chroot() {
    local target=$1
    shift
    case "$1" in
    sh) shift; local script=$1; shift; bash "$target$script" "$@" ;;
    dpkg) [ -f "$state/installed" ] ;;
    apt-mark) shift; apt-mark "$@" ;;
    *) return 81 ;;
    esac
}
error_and_exit() { echo "$*" >&2; exit 1; }
get_ubuntu_kernel_flavor() { echo virtual-hwe-24.04; }
export -f download chroot error_and_exit get_ubuntu_kernel_flavor
export -f chroot_update_kernel chroot_apt_install chroot_apt_update

for distro in debian ubuntu; do
    reset_state
    mkdir -p "$state/target/tmp"
    export os_dir=$state/target
    export kernel=linux-image-cloud-amd64
    echo 6.12.107-1 >"$state/installed"
    if [ "$distro" = debian ]; then
        sed -n '/^        kernel_package=\$kernel/,/^        chroot_.*"\$kernel_package"/p' "$root/trans.sh" >"$state/caller.sh"
        expected_package=linux-image-cloud-amd64
    else
        sed -n '/^        flavor=\$(get_ubuntu_kernel_flavor)/,/^        chroot_.*"linux-image-\$flavor"/p' "$root/trans.sh" >"$state/caller.sh"
        expected_package=linux-image-virtual-hwe-24.04
    fi
    [ -s "$state/caller.sh" ] || fail "No $distro cloud caller found."
    bash "$state/caller.sh" >"$state/output" 2>&1 || fail "$distro cloud kernel update failed."
    [ "$(cat "$state/installed")" = 6.12.113-1 ] || fail "$distro cloud caller skipped an installed kernel."
    [ "$(cat "$state/package")" = "$expected_package" ] || fail "$distro cloud flavour changed."
done
echo 'PASS: Debian and Ubuntu cloud call sites upgrade existing kernels.'

# Run the real preseed/late-command fragments with /target redirected to a
# disposable fixture. The target runner executes the shared updater unchanged.
debconf-get() { echo linux-image-cloud-amd64; }
wget() { [ "$1" = "$confhome/update-kernel.sh" ] && cp "$root/update-kernel.sh" "$3"; }
in-target() { chroot "$state/target" "$@"; }
curtin() { shift 3; chroot "$state/target" "$@"; }
curl() { [ "$2" = "$confhome/update-kernel.sh" ] && cp "$root/update-kernel.sh" "$4"; }
export -f debconf-get wget in-target curtin curl

for installer in debian ubuntu; do
    reset_state
    mkdir -p "$state/target/tmp" "$state/target/etc"
    echo ID=debian >"$state/target/etc/os-release"
    echo 6.12.107-1 >"$state/installed"
    if [ "$installer" = debian ]; then
        awk '/^    if grep.*ID=.*debian/ { active=1 } active { sub(/\\$/, ""); print } active && /^    fi;/ { exit }' "$root/debian.cfg" >"$state/fragment"
        expected_package=linux-image-cloud-amd64
    else
        awk '/^      # Update the selected kernel/ { active=1; next } active && /^$/ { exit } active { print }' "$root/deprecated/ubuntu.yaml" >"$state/fragment"
        export kernel=virtual-hwe-24.04
        expected_package=linux-virtual-hwe-24.04
    fi
    [ -s "$state/fragment" ] || fail "No $installer installer kernel update found."
    sed "s|/target|$state/target|g" "$state/fragment" >"$state/caller.sh"
    bash "$state/caller.sh" >"$state/output" 2>&1 || fail "$installer installer failed to update."
    [ "$(cat "$state/installed")" = 6.12.113-1 ] || fail "$installer installer kept the old kernel."
    [ "$(cat "$state/package")" = "$expected_package" ] || fail "$installer installer changed flavour."
    touch "$state/update-failure"
    if bash "$state/caller.sh" >"$state/output" 2>&1; then
        fail "$installer installer ignored a failed kernel update."
    fi
done
echo 'PASS: Debian preseed and Ubuntu ISO late commands update and propagate failures.'
