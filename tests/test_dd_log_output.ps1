$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$trans = Get-Content -Raw -LiteralPath (Join-Path $root 'trans.sh')

$loggingBranches = [regex]::Match($trans, '(?s)case 1 in\s*1\)\s*if \[ "\$distro" = "dd" \]; then(?<dd>.*?)else(?<other>.*?)fi')
if (-not $loggingBranches.Success) {
    throw 'DD-specific terminal logging branch is missing.'
}
if ($loggingBranches.Groups['dd'].Value -match '/reinstall\.log') {
    throw 'DD output is still written to /reinstall.log.'
}
if ($loggingBranches.Groups['dd'].Value -notmatch 'tee \$\(get_ttys /dev/\)') {
    throw 'DD output is no longer mirrored to SSH/TTY.'
}
if ($loggingBranches.Groups['other'].Value -notmatch 'tee \$\(get_ttys /dev/\) /reinstall\.log') {
    throw 'Non-DD install modes must retain their /reinstall.log file.'
}

if ($trans -notmatch '(?s)trans\(\) \{.*?if \[ "\$distro" != "dd" \]; then\s*mod_motd\s*fi') {
    throw 'The DD installer must not display the /reinstall.log motd instruction.'
}

if ($trans -notmatch 'if \[ "\$distro" != "alpine" \] && \[ "\$distro" != "dd" \]; then\s*setup_web_if_enough_ram') {
    throw 'The DD installer must not start the web log viewer when file logging is disabled.'
}

Write-Output 'PASS: DD keeps live terminal output while disabling /reinstall.log and its viewers.'
