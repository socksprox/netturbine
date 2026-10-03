# Sends one line to \\.\pipe\netturbine_fan and prints the reply.
# Usage: pipe_probe.ps1 "list"  |  pipe_probe.ps1 "set 0 50"
param([Parameter(Mandatory=$true)][string]$Command)
$pipe = New-Object System.IO.Pipes.NamedPipeClientStream(
    ".", "netturbine_fan", [System.IO.Pipes.PipeDirection]::InOut)
$pipe.Connect(3000)
$w = New-Object System.IO.StreamWriter($pipe)
$r = New-Object System.IO.StreamReader($pipe)
$w.WriteLine($Command)
$w.Flush()
Write-Output $r.ReadLine()
$pipe.Close()
