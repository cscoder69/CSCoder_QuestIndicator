# Turns media/logo.png into icons/logo.tga (256x256, 32-bit uncompressed, top-left origin),
# the logo the setup guide shows in game.
# usage: powershell -File tools/make_logo_tga.ps1
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$source = [System.Drawing.Image]::FromFile((Join-Path $root "media\logo.png"))
$size = 256
$bitmap = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$graphics.DrawImage($source, 0, 0, $size, $size)
$graphics.Dispose()
$source.Dispose()

$bytes = New-Object byte[] (18 + $size * $size * 4)
$bytes[2] = 2                                  # uncompressed true colour
$bytes[12] = $size % 256; $bytes[13] = [math]::Floor($size / 256)
$bytes[14] = $size % 256; $bytes[15] = [math]::Floor($size / 256)
$bytes[16] = 32                                # bits per pixel
$bytes[17] = 0x28                              # 8 alpha bits, top-left origin
$i = 18
for ($y = 0; $y -lt $size; $y++) {
	for ($x = 0; $x -lt $size; $x++) {
		$c = $bitmap.GetPixel($x, $y)
		$bytes[$i] = $c.B; $bytes[$i + 1] = $c.G; $bytes[$i + 2] = $c.R; $bytes[$i + 3] = $c.A
		$i += 4
	}
}
$bitmap.Dispose()
$out = Join-Path $root "icons\logo.tga"
[System.IO.File]::WriteAllBytes($out, $bytes)
Write-Output "$out ${size}x${size}"
