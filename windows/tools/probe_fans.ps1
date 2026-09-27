$p = 'C:\Users\user\Code\netturbine\windows\tools\acpi_probe.exe'
$o = 'C:\Users\user\Code\netturbine\probe_out.txt'
Remove-Item $o -ErrorAction SilentlyContinue
function Run-Probe() { & $p @args 2>&1 | Out-File -Append $o -Encoding ascii }

foreach ($m in @('RDEC', '\_SB.PC00.LPCB.EC0.RDEC')) {
  foreach ($r in @('0x95','0x83','0x94','0x82','0x93','0x81','0x3D')) {
    Run-Probe 'read' $m $r
  }
}
Run-Probe 'read' '\_SB.RBEC' '0x95'
Run-Probe 'read0' 'FAN0._FST'
Run-Probe 'read0' '\_SB.PC00.LPCB.EC0.FAN0._FST'
Run-Probe 'read0' '\_SB.PC00.LPCB.EC0.FAN0._HID'
Run-Probe 'read0' '\_SB.PC00.LPCB.EC0._HID'
"probe done" | Out-File -Append $o
