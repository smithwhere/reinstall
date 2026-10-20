#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

# Exercise the real selection functions without sourcing the destructive installer.
source <(sed -n '/^    setos_debian() {/,/^    }/p' "$root/reinstall.sh")
source <(sed -n '/^get_ubuntu_kernel_flavor() {/,/^}/p' "$root/trans.sh")
is_in_china() { return 1; }
is_use_cloud_image() { [ "$image_mode" = cloud ]; }
is_virt() { [ "$machine" = virtual ]; }
set_osvar() { if [ "$1" = kernel ]; then selected=$2; fi; }
error_and_exit() { fail "$*"; }
warn() { fail 'Unexpected interactive installer prompt.'; }
confhome=https://example.invalid/reinstall

# Catch the old VM-only -cloud choice, including stale flavour from another OS.
for releasever in 13 9 10 11 12 14; do
    for basearch_alt in amd64 arm64; do
        [ "$releasever:$basearch_alt" != 9:arm64 ] || continue
        if [ "$basearch_alt" = arm64 ]; then basearch=aarch64; else basearch=x86_64; fi
        for image_mode in netboot cloud; do
            for machine in virtual physical; do
                flavour=-cloud
                selected=
                setos_debian
                [ "$selected" = "linux-image-$basearch_alt" ] ||
                    fail "Debian $releasever $basearch_alt $image_mode $machine selected $selected."
            done
        done
    done
done
echo 'PASS: Debian releases, architectures and install paths select standard kernels.'

# Cached debconf values must also be normalized in the real preseed early step.
debconf-get() { echo "$requested"; }
debconf-set() { selected=$2; }
for requested in linux-image-cloud-amd64 linux-image-cloud-arm64 linux-image-amd64; do
    selected=
    source <(awk '/^    eths=/{active=1; next} active && /^    if \[ -d \/sys\/firmware\/efi/{exit} active {sub(/\\$/, ""); print}' "$root/debian.cfg")
    [ "$selected" = "${requested/-cloud/}" ] || fail "Preseed retained $requested."
done
echo 'PASS: Debian preseed cannot reintroduce a cached cloud kernel selection.'

# Low memory must fail before installation rather than select a cloud kernel.
is_in_windows() { return 1; }
is_distro_like_debian() { [[ "$distro" = debian || "$distro" = kali ]]; }
exit_if_cant_use_cloud_kernel() { echo cloud-fallback; }
memory_guard=$(awk '/^    # Standard Debian kernels need more RAM/{active=1} active {print} active && /^    fi$/{exit}' "$root/reinstall.sh")
[ -n "$memory_guard" ] || fail 'Missing standard-kernel memory guard.'
distro=debian
ram_size=256
if (eval "$memory_guard") >/dev/null 2>&1; then fail '256 MiB Debian silently selected a kernel.'; fi
ram_size=512
eval "$memory_guard"
distro=kali
ram_size=256
[ "$(eval "$memory_guard")" = cloud-fallback ] || fail 'Unrelated Kali memory policy changed.'
echo 'PASS: low-memory Debian fails early without changing Kali policy.'

cache_dmi_and_virt() { :; }
get_cloud_vendor() { echo "$test_vendor"; }
is_ubuntu_lts() { [[ "$releasever" = *.04 ]]; }
for releasever in 18.04 20.04 22.04 24.04 25.10; do
    for test_vendor in vultr aws gcp azure oracle ibm; do
        for machine in virtual physical; do
            selected=$(get_ubuntu_kernel_flavor)
            case "$releasever" in
            25.10) expected=generic ;;
            *) expected=generic-hwe-$releasever ;;
            esac
            [ "$selected" = "$expected" ] ||
                fail "Ubuntu $releasever $test_vendor $machine selected $selected."
        done
    done
done
echo 'PASS: Ubuntu selects generic/HWE independently of VM or cloud vendor.'
