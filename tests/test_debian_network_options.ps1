$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$reinstall = Get-Content -Raw -LiteralPath (Join-Path $root 'reinstall.sh')
$debianConfig = Get-Content -Raw -LiteralPath (Join-Path $root 'debian.cfg')
$initrd = Get-Content -Raw -LiteralPath (Join-Path $root 'initrd-network.sh')
$trans = Get-Content -Raw -LiteralPath (Join-Path $root 'trans.sh')

function Assert-Contains([string]$Text, [string]$Expected, [string]$Message) {
    if (-not $Text.Contains($Expected)) {
        throw $Message
    }
}

Assert-Contains $reinstall 'debian      9|10|11|12|13|14' 'Debian 14 is missing from the command usage.'
Assert-Contains $reinstall 'confhome=https://raw.githubusercontent.com/smithwhere/reinstall/main' 'Runtime companion files still point to the upstream repository.'
Assert-Contains $reinstall 'netmask:' 'The --netmask option is missing from getopt configuration.'
Assert-Contains $reinstall 'ip:' 'The --ip option is missing from getopt configuration.'
Assert-Contains $reinstall 'gateway:' 'The --gateway option is missing from getopt configuration.'
Assert-Contains $reinstall 'dns:' 'The --dns option is missing from getopt configuration.'
Assert-Contains $reinstall 'hostname:' 'The --hostname option is missing from getopt configuration.'
Assert-Contains $reinstall '    ethx \' 'The --ethx option is missing from getopt configuration.'
Assert-Contains $reinstall '    static-ipv4 \' 'The --static-ipv4 option is missing from getopt configuration.'
Assert-Contains $reinstall '--netmask)' 'The --netmask parser branch is missing.'
Assert-Contains $reinstall '--ip)' 'The --ip parser branch is missing.'
Assert-Contains $reinstall '--gateway)' 'The --gateway parser branch is missing.'
Assert-Contains $reinstall '--dns)' 'The --dns parser branch is missing.'
Assert-Contains $reinstall '--hostname)' 'The --hostname parser branch is missing.'
Assert-Contains $reinstall '--ethx)' 'The --ethx parser branch is missing.'
Assert-Contains $reinstall '--static-ipv4)' 'The --static-ipv4 parser branch is missing.'
Assert-Contains $reinstall '14) codename=forky' 'Debian 14 codename mapping is missing.'
Assert-Contains $reinstall 'debian      9|10|11|12|13|14' 'Debian 14 is missing from version validation.'
Assert-Contains $reinstall 'initrd_mirror=d-i.debian.org/daily-images' 'Debian 14 does not use the matching daily installer mirror.'
Assert-Contains $reinstall 'initrd_dir=$basearch_alt/daily/netboot/debian-installer/$basearch_alt' 'Debian 14 daily installer path is missing.'
Assert-Contains $reinstall 'custom_ipv4_addr' 'The normalized custom IPv4 address is missing.'
Assert-Contains $reinstall '''$sh' '$ipv4_mac' '$ipv4_addr' '$ipv4_gateway' '$ipv6_addr' '$ipv6_gateway' '$is_in_china' '$ipv6_extra_addrs' '$custom_dns''' 'Custom DNS is not passed to the initrd network script.'
Assert-Contains $initrd 'custom_dns=$8' 'The initrd network script does not accept custom DNS.'
Assert-Contains $initrd 'if [ -n "$custom_dns" ]; then' 'The initrd network script does not apply custom DNS.'
Assert-Contains $initrd 'static_ipv4=$9' 'The initrd network script does not accept --static-ipv4.'
Assert-Contains $initrd 'should_disable_dhcpv4=true' 'The initrd network script does not force static IPv4 mode.'
Assert-Contains $reinstall 'custom_ipv4_addr custom_ipv4_gateway custom_dns' 'Custom network values are not propagated to the boot command line.'
Assert-Contains $reinstall 'static_ipv4' 'The --static-ipv4 state is not propagated to the boot command line.'
Assert-Contains $reinstall '''$ipv6_extra_addrs' '$custom_dns' '$static_ipv4''' 'The current IPv4 mode is not passed to the initrd network script.'
Assert-Contains $reinstall 'static_ipv4 conflicts with --netmask, --ip and --gateway' 'The --static-ipv4 conflict validation is missing.'
Assert-Contains $reinstall 'custom_hostname' 'The custom hostname is not propagated to the boot command line.'
Assert-Contains $reinstall 'net.ifnames=0 biosdevname=0' 'The --ethx kernel naming parameters are missing.'
Assert-Contains $trans 'custom_hostname' 'The transition script does not apply the custom hostname.'
Assert-Contains $trans '/etc/hostname' 'The transition script does not persist the custom hostname.'
Assert-Contains $trans 'GRUB_CMDLINE_LINUX' 'The transition script does not persist eth0 naming for the installed system.'
Assert-Contains $debianConfig 'custom_hostname' 'The Debian preseed does not apply the custom hostname.'
Assert-Contains $debianConfig '/target/etc/hostname' 'The Debian preseed does not persist the custom hostname.'
Assert-Contains $debianConfig 'GRUB_CMDLINE_LINUX' 'The Debian preseed does not persist eth0 naming for the installed system.'
Assert-Contains $trans 'apply_custom_network_config' 'The transition script does not apply custom network configuration.'
Assert-Contains $trans 'dns-nameservers $dns' 'Custom DNS is not persisted in the ifupdown configuration.'
Assert-Contains $trans 'need_set_dns4=true' 'Custom DNS is not included in cloud-init network configuration.'

Write-Output 'PASS: Debian 14, custom network, hostname, ethx, and static IPv4 option wiring is present.'
