$t = $PSScriptRoot
$probe = "$t\ec_probe.exe"
$msr = "$t\msr_probe.exe"

cmd /c "`"$msr`" > `"$t\s_base_cpu.txt`" 2>&1"
cmd /c "`"$probe`" dump all > `"$t\s_base_ec.txt`" 2>&1"

$jobs = 1..8 | ForEach-Object { Start-Job { $x=0; $e=Get-Date; while(($e.AddSeconds(25)) -gt (Get-Date)) { $x++ } } }
Start-Sleep -Seconds 28
$jobs | Remove-Job -Force

cmd /c "`"$msr`" > `"$t\s_hot_cpu.txt`" 2>&1"
cmd /c "`"$probe`" dump all > `"$t\s_hot_ec.txt`" 2>&1"
