$p = 'C:\Users\user\Code\netturbine\windows\tools\ec_probe.exe'
$o = 'C:\Users\user\Code\netturbine\ec_out.txt'
& $p @args *>&1 | Out-File -Encoding ascii $o
