#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Exercise the real logging function without touching /reinstall.log on the
# runner or keeping a background console watcher alive.
sed -n '/^start_install_logging() {/,/^}/p' "$root/trans.sh" |
    sed "s|/reinstall.log|$scratch/reinstall.log|g" >"$scratch/logging.sh"
grep -q '^start_install_logging() {' "$scratch/logging.sh" ||
    fail 'Missing VNC-safe installer logging implementation.'
cat >>"$scratch/logging.sh" <<'EOF'
get_ttys() { printf '%s\n' "$TEST_TTY"; }
start_install_logging
printf 'installation proceeds without VNC\n'
printf 'diagnostics remain available over SSH\n' >&2
EOF

TEST_TTY="$scratch/disconnected-vnc" bash "$scratch/logging.sh" ||
    fail 'Installer stopped when the VNC device was unavailable.'
grep -Fxq 'installation proceeds without VNC' "$scratch/reinstall.log" ||
    fail 'Standard output was not saved.'
grep -Fxq 'diagnostics remain available over SSH' "$scratch/reinstall.log" ||
    fail 'Standard error was not saved.'
# A failed terminal must not be in the main process's stdout pipeline.
! grep -Eq '^    (exec > >\(|trans 2>&1 \| tee)' "$root/trans.sh" ||
    fail 'Installer is again coupled to a VNC/serial tee pipeline.'
echo 'PASS: installation output survives a missing VNC terminal.'

# Evaluate the exact conditional embedded in the reinstall GRUB entry.
sed -n '/^    $(if ! is_efi &&/,/^    fi)/p' "$root/reinstall.sh" |
    sed '1s/^[[:space:]]*$(//; $s/)[[:space:]]*$//' >"$scratch/grub-display.sh"
grep -q 'terminal_output console' "$scratch/grub-display.sh" ||
    fail 'Missing BIOS text-mode GRUB command.'
grub_gate=$(cat "$scratch/grub-display.sh")
test_mode=bios
basearch=x86_64
is_efi() { [ "$test_mode" = efi ]; }
value=$(eval "$grub_gate")
[ "$value" = $'terminal_output console\nset gfxpayload=text' ] ||
    fail "BIOS GRUB did not use text mode: $value"
test_mode=efi
[ -z "$(eval "$grub_gate")" ] ||
    fail 'UEFI GRUB unexpectedly lost its graphical output.'
test_mode=bios
basearch=aarch64
[ -z "$(eval "$grub_gate")" ] ||
    fail 'ARM GRUB unexpectedly changed its display settings.'
echo 'PASS: BIOS uses VGA text while UEFI and ARM are unchanged.'

# Check the actual Debian/Kali installer kernel command-line construction.
sed -n '/^[[:space:]]*nextos_cmdline="lowmem\/low=1 auto=true priority=critical"/,/^[[:space:]]*nextos_cmdline+=" url=\$nextos_ks"/p' "$root/reinstall.sh" >"$scratch/debian-video.sh"
grep -q 'vga=normal fb=false' "$scratch/debian-video.sh" ||
    fail 'BIOS Debian installer is missing framebuffer-safe boot arguments.'
kernel_video_gate=$(cat "$scratch/debian-video.sh")
nextos_ks=https://example.invalid/preseed.cfg
basearch=x86_64
test_mode=bios
eval "$kernel_video_gate"
case " $nextos_cmdline " in *" vga=normal fb=false "*) ;; *) fail 'BIOS installer is not in VGA text mode.' ;; esac
test_mode=efi
eval "$kernel_video_gate"
case " $nextos_cmdline " in *" vga=normal fb=false "*) fail 'UEFI installer framebuffer was disabled.' ;; esac
test_mode=bios
basearch=aarch64
eval "$kernel_video_gate"
case " $nextos_cmdline " in *" vga=normal fb=false "*) fail 'ARM installer framebuffer was disabled.' ;; esac
echo 'PASS: Debian installer console fallback is BIOS-only.'
