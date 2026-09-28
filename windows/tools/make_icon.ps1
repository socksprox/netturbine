# Regenerates windows/runner/resources/app_icon.ico from the PNG next to it.
# Produces a multi-size ICO: 32bpp DIB entries for <=128px (maximally
# compatible with rc.exe, Inno Setup, and Shell_NotifyIcon) and a
# PNG-compressed entry at 256px.
#
# Usage: powershell -File windows/tools/make_icon.ps1 [source.png]
param(
  [string]$Source = "$PSScriptRoot\..\runner\resources\netturbine.png",
  [string]$Dest = "$PSScriptRoot\..\runner\resources\app_icon.ico"
)

Add-Type -AssemblyName System.Drawing

$src = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Source))
Write-Output "Source: $($src.Width)x$($src.Height) $($src.PixelFormat)"
if (($src.PixelFormat -band [System.Drawing.Imaging.PixelFormat]::Alpha) -eq 0) {
  Write-Output "WARNING: source has no alpha channel - icon will be an opaque square"
}
$corner = $src.GetPixel(0, 0)
Write-Output "Corner pixel alpha: $($corner.A)"

$bmpSizes = @(16, 20, 24, 32, 40, 48, 64, 128)
$pngSizes = @(256)
$entries = New-Object System.Collections.Generic.List[byte[]]
$meta = New-Object System.Collections.Generic.List[int]

function Resize-Bitmap([System.Drawing.Bitmap]$src, [int]$size) {
  $dst = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($dst)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
  $g.DrawImage($src, 0, 0, $size, $size)
  $g.Dispose()
  return $dst
}

# Emits a 32bpp ICO image: BITMAPINFOHEADER (height doubled) + bottom-up
# BGRA pixel data + a zeroed 1bpp AND mask (transparency comes from alpha).
function Get-DibEntry([System.Drawing.Bitmap]$bmp, [int]$size) {
  $rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
  $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $xor = New-Object byte[] ($size * $size * 4)
  for ($y = 0; $y -lt $size; $y++) {
    [System.Runtime.InteropServices.Marshal]::Copy(
      [IntPtr]($data.Scan0.ToInt64() + $y * $data.Stride),
      $xor, ($size - 1 - $y) * $size * 4, $size * 4)
  }
  $bmp.UnlockBits($data)

  $maskStride = [int](($size + 31) / 32) * 4
  $and = New-Object byte[] ($maskStride * $size)

  $ms = New-Object System.IO.MemoryStream
  $w = New-Object System.IO.BinaryWriter($ms)
  $w.Write([uint32]40)                 # biSize
  $w.Write([int32]$size)               # biWidth
  $w.Write([int32]($size * 2))         # biHeight = XOR + AND
  $w.Write([uint16]1)                  # biPlanes
  $w.Write([uint16]32)                 # biBitCount
  $w.Write([uint32]0)                  # biCompression = BI_RGB
  $w.Write([uint32]($xor.Length))      # biSizeImage
  $w.Write([int32]0); $w.Write([int32]0)   # biXPelsPerMeter, biYPelsPerMeter
  $w.Write([uint32]0); $w.Write([uint32]0) # biClrUsed, biClrImportant
  $w.Write($xor)
  $w.Write($and)
  $w.Flush()
  return $ms.ToArray()
}

function Get-PngEntry([System.Drawing.Bitmap]$bmp) {
  $ms = New-Object System.IO.MemoryStream
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  return $ms.ToArray()
}

$sizes = @()
foreach ($s in $bmpSizes) {
  $b = Resize-Bitmap $src $s
  $entries.Add((Get-DibEntry $b $s))
  $meta.Add($s)
  $b.Dispose()
  $sizes += "$s(dib)"
}
foreach ($s in $pngSizes) {
  $b = Resize-Bitmap $src $s
  $entries.Add((Get-PngEntry $b))
  $meta.Add($s)
  $b.Dispose()
  $sizes += "$s(png)"
}
$src.Dispose()

$ms = New-Object System.IO.MemoryStream
$w = New-Object System.IO.BinaryWriter($ms)
$w.Write([uint16]0)                  # ICONDIR reserved
$w.Write([uint16]1)                  # type = icon
$w.Write([uint16]$entries.Count)
$offset = 6 + 16 * $entries.Count
for ($i = 0; $i -lt $entries.Count; $i++) {
  $dim = $meta[$i]
  if ($dim -ge 256) { $dim = 0 }     # 256 stored as 0
  $w.Write([byte]$dim)               # width
  $w.Write([byte]$dim)               # height
  $w.Write([byte]0)                  # palette colors
  $w.Write([byte]0)                  # reserved
  $w.Write([uint16]1)                # planes
  $w.Write([uint16]32)               # bitcount
  $w.Write([uint32]$entries[$i].Length)
  $w.Write([uint32]$offset)
  $offset += $entries[$i].Length
}
foreach ($e in $entries) { $w.Write($e) }
$w.Flush()

[System.IO.File]::WriteAllBytes($Dest, $ms.ToArray())
Write-Output ("Wrote {0} ({1} bytes): {2}" -f $Dest, $ms.Length, ($sizes -join ', '))
