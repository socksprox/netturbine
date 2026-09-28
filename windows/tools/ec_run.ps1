$p = "$PSScriptRoot\ec_probe.exe"
$o = "$PSScriptRoot\ec_out.txt"
& $p @args *>&1 | Out-File -Encoding ascii $o
