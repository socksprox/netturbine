# Deploys the locally built helper + required PawnIO modules into the
# installed app directory and restarts the service. Run elevated.
$t = $PSScriptRoot
$dst = 'C:\Program Files\Netturbine'
Stop-Service NetturbineFanHelper -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Copy-Item "$t\fan_helper_new.exe" "$dst\fan_helper.exe" -Force
Copy-Item "$t\AMDFamily17.bin" "$dst\AMDFamily17.bin" -Force
Copy-Item "$t\fan_helper_new.exe" "$t\fan_helper.exe" -Force
Start-Service NetturbineFanHelper
Start-Sleep -Seconds 2
Get-Service NetturbineFanHelper | Out-File "$t\deploy_out.txt"
Get-Item "$dst\fan_helper.exe" | Select-Object Length | Out-File -Append "$t\deploy_out.txt"
