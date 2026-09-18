$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$reinstall = Get-Content -Raw -LiteralPath (Join-Path $root 'reinstall.sh')
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
Assert-Contains $reinstall '--netmask)' 'The --netmask parser branch is missing.'
Assert-Contains $reinstall '--ip)' 'The --ip parser branch is missing.'
Assert-Contains $reinstall '--gateway)' 'The --gateway parser branch is missing.'
Assert-Contains $reinstall '--dns)' 'The --dns parser branch is missing.'
Assert-Contains $reinstall '14) codename=forky' 'Debian 14 codename mapping is missing.'
Assert-Contains $reinstall 'debian      9|10|11|12|13|14' 'Debian 14 is missing from version validation.'
Assert-Contains $reinstall 'custom_ipv4_addr' 'The normalized custom IPv4 address is missing.'
Assert-Contains $reinstall '''$sh' '$ipv4_mac' '$ipv4_addr' '$ipv4_gateway' '$ipv6_addr' '$ipv6_gateway' '$is_in_china' '$ipv6_extra_addrs' '$custom_dns''' 'Custom DNS is not passed to the initrd network script.'
Assert-Contains $initrd 'custom_dns=$8' 'The initrd network script does not accept custom DNS.'
Assert-Contains $initrd 'if [ -n "$custom_dns" ]; then' 'The initrd network script does not apply custom DNS.'
Assert-Contains $reinstall 'custom_ipv4_addr custom_ipv4_gateway custom_dns' 'Custom network values are not propagated to the boot command line.'
Assert-Contains $trans 'apply_custom_network_config' 'The transition script does not apply custom network configuration.'
Assert-Contains $trans 'dns-nameservers $dns' 'Custom DNS is not persisted in the ifupdown configuration.'
Assert-Contains $trans 'need_set_dns4=true' 'Custom DNS is not included in cloud-init network configuration.'

Write-Output 'PASS: Debian 14 and custom network option wiring is present.'
