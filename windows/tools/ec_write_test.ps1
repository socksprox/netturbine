$p = "$PSScriptRoot\ec_probe.exe"
$o = "$PSScriptRoot\ec_out.txt"
Remove-Item $o -ErrorAction SilentlyContinue
function Log([string]$s) { $s | Out-File -Append $o -Encoding ascii }
function Run-Probe() { & $p @args 2>&1 | Out-File -Append $o -Encoding ascii }

Log '=== baseline ==='
Run-Probe 'dump'

Log '=== write FSW1=70 (no-op value, validates write path) ==='
Run-Probe 'write' '0x94' '70'
Run-Probe 'read' '0x94'

Log '=== set hold bit: FSH1 |= 0x10 (0x0C -> 0x1C) ==='
Run-Probe 'write' '0x93' '0x1C'
Run-Probe 'read' '0x93'

Log '=== write FSW1=100 (full speed) ==='
Run-Probe 'write' '0x94' '100'
Start-Sleep -Seconds 5
Log '=== readback after 5s at 100 ==='
Run-Probe 'read' '0x95' '0x94' '0x93'

Log '=== restore: FSW1=70, FSH1=0x0C (auto) ==='
Run-Probe 'write' '0x94' '70'
Run-Probe 'write' '0x93' '0x0C'
Start-Sleep -Seconds 3
Run-Probe 'dump'
Log '=== done ==='
