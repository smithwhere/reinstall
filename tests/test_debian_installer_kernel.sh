#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# Load only functions; never run the installer's main program in a test.
for function in download_debian_daily_installer debian_installer_has_kernel \
    select_debian_installer_udeb_suite build_nextos_cmdline; do
    source <(sed -n "/^$function() {/,/^}/p" "$root/reinstall.sh")
done
source <(sed -n '/^    download_and_extract_deb() {/,/^    }/p' "$root/reinstall.sh")

scratch=$(mktemp -d)
tmp=$scratch/cache
fixtures=$scratch/fixtures
mkdir -p "$tmp" "$fixtures" "$scratch/initrd/etc"
cd "$scratch/initrd"

info() { printf '%s\n' "$*"; }
error_and_exit() { printf '%s\n' "$*" >&2; exit 1; }
install_pkg() { :; }
is_distro_like_debian() { [ "$1" = debian ] || [ "$1" = kali ]; }
is_debian_elts() { return 1; }
ar() { :; }
tar() { :; }

write_index() {
    local kernel=$1 file=$2 module
    for module in linux-binary base-modules scsi-core-modules ata-modules scsi-modules; do
        printf 'Package: %s-%s-di\nFilename: pool/%s-%s.udeb\n\n' \
            "$module" "$kernel" "$module" "$kernel"
    done >"$file"
    printf 'Package: openssh-server-udeb\nFilename: pool/openssh-server-udeb_1.udeb\n\n' >>"$file"
}

# Network calls are replaced with local, deliberately mismatched archives.
curl() {
    local output= url= suite
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -o | -Lo) output=$2; shift 2 ;;
        --max-time) shift 2 ;;
        https://* | http://*) url=$1; shift ;;
        *) shift ;;
        esac
    done
    printf '%s\n' "$url" >>"$scratch/downloads.log"
    if [[ "$url" = *"${blocked_mirror:-never-match.invalid}"* ]]; then
        return 22
    fi
    case "$url" in
    */SHA256SUMS) cp "$fixtures/SHA256SUMS" "$output" ;;
    */linux) cp "$fixtures/linux" "$output" ;;
    */initrd.gz) cp "$fixtures/initrd.gz" "$output" ;;
    */Packages.gz)
        suite=${url#*/dists/}
        suite=${suite%%/*}
        cp "$fixtures/$suite.gz" "$output"
        ;;
    */pool/*) printf 'fixture' >"$output" ;;
    *) return 22 ;;
    esac
}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
kernel=7.2.8+deb14-amd64
write_index "$kernel" "$fixtures/matched"
debian_installer_has_kernel "$fixtures/matched" "$kernel" || fail 'Exact kernel was rejected.'
write_index 7.2.9+deb14-amd64 "$fixtures/mismatch"
if debian_installer_has_kernel "$fixtures/mismatch" "$kernel"; then
    fail 'Different kernel was accepted.'
fi
write_index 7x2x8deb14-amd64 "$fixtures/regex-lookalike"
if debian_installer_has_kernel "$fixtures/regex-lookalike" "$kernel"; then
    fail 'Kernel name was treated as a regular expression.'
fi
sed '/^Package: scsi-core-modules-/d' "$fixtures/matched" >"$fixtures/incomplete"
if debian_installer_has_kernel "$fixtures/incomplete" "$kernel"; then
    fail 'Incomplete kernel modules were accepted.'
fi
if debian_installer_has_kernel /dev/null "$kernel"; then
    fail 'An empty package index was accepted.'
fi
write_index 7.2.8+deb14-arm64 "$fixtures/arm64"
debian_installer_has_kernel "$fixtures/arm64" 7.2.8+deb14-arm64 || fail 'ARM64 kernel was rejected.'

basearch_alt=amd64
nextos_codename=forky
nextos_udeb_mirror=deb.debian.org/debian
kver=$kernel
gzip -c "$fixtures/matched" >"$fixtures/forky.gz"
gzip -c "$fixtures/mismatch" >"$fixtures/unstable.gz"
select_debian_installer_udeb_suite
[ "$nextos_udeb_suite" = forky ] || fail 'Forky was not selected for the reported failure.'
[ "$(cat etc/udebs-source)" = forky ] || fail 'The initrd still points at unstable.'
grep -Fq "scsi-modules-$kernel.udeb" "$tmp/udeb_forky_list" || fail 'Matching index was not cached.'

gzip -c "$fixtures/mismatch" >"$fixtures/forky.gz"
gzip -c "$fixtures/matched" >"$fixtures/unstable.gz"
select_debian_installer_udeb_suite
[ "$nextos_udeb_suite" = unstable ] || fail 'Unstable fallback did not select a matching kernel.'
[ "$(cat etc/udebs-source)" = unstable ] || fail 'The fallback suite was not persisted.'

nextos_udeb_mirror=mirror.example/debian
blocked_mirror=mirror.example
select_debian_installer_udeb_suite
[ "$nextos_udeb_mirror" = deb.debian.org/debian ] || fail 'Unavailable mirror did not fall back to the official mirror.'
unset blocked_mirror

gzip -c "$fixtures/mismatch" >"$fixtures/unstable.gz"
printf 'original\n' >etc/udebs-source
if (select_debian_installer_udeb_suite) >"$scratch/no-match.log" 2>&1; then
    fail 'No matching kernel must stop preparation before reboot.'
fi
grep -Fq "No Debian installer module source matches kernel $kernel" "$scratch/no-match.log" || fail 'Missing actionable failure message.'
[ "$(cat etc/udebs-source)" = original ] || fail 'Failure modified the initrd suite.'
printf 'not gzip\n' >"$fixtures/forky.gz"
printf 'not gzip\n' >"$fixtures/unstable.gz"
if (select_debian_installer_udeb_suite) >"$scratch/corrupt.log" 2>&1; then
    fail 'Corrupt indexes were accepted.'
fi

nextos_distro=debian
nextos_ks=https://example.invalid/debian.cfg
nextos_kernel=linux-image-cloud-amd64
basearch=x86_64
use_ethx=1
nextos_udeb_suite=unstable
build_nextos_cmdline
[[ "$nextos_cmdline" = *'mirror/suite=forky mirror/udeb/suite=unstable'* ]] || fail 'Installer and target suites were not separated.'
[[ "$nextos_cmdline" = *'net.ifnames=0 biosdevname=0'* ]] || fail 'ethx options were lost.'
unset nextos_udeb_suite
nextos_codename=trixie
build_nextos_cmdline
[[ "$nextos_cmdline" != *'mirror/udeb/suite='* ]] || fail 'Stable Debian acquired a daily suite override.'

nextos_codename=forky
nextos_deb_mirror=mirror.example/debian
nextos_udeb_suite=unstable
write_index "$kernel" "$fixtures/matched"
gzip -c "$fixtures/matched" >"$fixtures/unstable.gz"
printf 'pool/openssh-server-udeb_1.udeb\n' >"$tmp/udeb_unstable_list"
download_and_extract_deb udeb openssh-server-udeb "$scratch/initrd"
grep -Fxq 'http://deb.debian.org/debian/pool/openssh-server-udeb_1.udeb' "$scratch/downloads.log" || fail 'Udeb predownload used the wrong mirror.'
printf 'pool/linux-image-%s_1.deb\n' "$kernel" >"$tmp/deb_unstable_list"
download_and_extract_deb deb "linux-image-$kernel" "$scratch/initrd"
grep -Fxq "http://deb.debian.org/debian/pool/linux-image-${kernel}_1.deb" "$scratch/downloads.log" || fail 'Extra kernel driver used the target suite instead of the installer suite.'

printf 'kernel build A\n' >"$fixtures/linux"
printf 'initrd build A\n' >"$fixtures/initrd.gz"
{
    printf '%s  ./netboot/debian-installer/amd64/linux\n' "$(sha256sum "$fixtures/linux" | cut -d' ' -f1)"
    printf '%s  ./netboot/debian-installer/amd64/initrd.gz\n' "$(sha256sum "$fixtures/initrd.gz" | cut -d' ' -f1)"
} >"$fixtures/SHA256SUMS"
nextos_vmlinuz=https://d-i.debian.org/daily-images/amd64/daily/netboot/debian-installer/amd64/linux
nextos_initrd=${nextos_vmlinuz%/*}/initrd.gz
download_debian_daily_installer "$scratch/linux" "$scratch/initrd.gz"
blocked_mirror=/linux
if (download_debian_daily_installer "$scratch/linux" "$scratch/initrd.gz") >"$scratch/download-error.log" 2>&1; then
    fail 'A failed kernel download reused a stale local kernel.'
fi
unset blocked_mirror
printf 'initrd build B\n' >"$fixtures/initrd.gz"
if (download_debian_daily_installer "$scratch/linux" "$scratch/initrd.gz") >"$scratch/checksum.log" 2>&1; then
    fail 'A mixed daily build was accepted.'
fi
printf '' >"$fixtures/SHA256SUMS"
if (download_debian_daily_installer "$scratch/linux" "$scratch/initrd.gz") >"$scratch/missing-sums.log" 2>&1; then
    fail 'Missing daily checksums were accepted.'
fi

printf 'PASS: exact kernel matching, suite selection, mirror fallback, failure guards, package routing and daily build checksums.\n'
