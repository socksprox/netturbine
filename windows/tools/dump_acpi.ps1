$out = "$PSScriptRoot\acpi"
New-Item -ItemType Directory -Force $out | Out-Null
Get-ChildItem 'HKLM:\HARDWARE\ACPI' -Recurse |
  Where-Object { $_.ValueCount -gt 0 } |
  ForEach-Object {
    $k = $_
    $i = 0
    foreach ($n in $k.GetValueNames()) {
      $b = $k.GetValue($n)
      if ($b -is [byte[]] -and $b.Length -gt 36) {
        $sig = [Text.Encoding]::ASCII.GetString($b[0..3])
        [IO.File]::WriteAllBytes("$out\$sig-$($k.PSChildName)-$i.bin", $b)
        $i++
      }
    }
  }
"done" | Out-File "$out\_done.txt"
