$t = 'C:\Users\user\Code\netturbine\windows\tools'
$o = "$t\swap_out.txt"
Remove-Item $o -ErrorAction SilentlyContinue
Stop-Service NetturbineFanHelper -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Move-Item "$t\fan_helper_new.exe" "$t\fan_helper.exe" -Force
Copy-Item "$t\pawnio_modules\IntelMSR.bin" "$t\IntelMSR.bin" -Force
Start-Service NetturbineFanHelper
Start-Sleep -Seconds 2
Get-Service NetturbineFanHelper | Out-File -Append $o
