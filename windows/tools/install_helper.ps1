$o = 'C:\Users\user\Code\netturbine\windows\tools\install_out.txt'
Remove-Item $o -ErrorAction SilentlyContinue
Get-Process fan_helper -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
& 'C:\Users\user\Code\netturbine\windows\tools\fan_helper.exe' install *>&1 | Out-File -Append $o -Encoding ascii
Start-Sleep -Seconds 2
Get-Service NetturbineFanHelper | Out-File -Append $o
