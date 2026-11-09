Add-Type -AssemblyName System.Drawing
$dir = "D:\Games\CS.Coder\WoW Addons\CSCoder_QuestIndicator\icons"
New-Item -ItemType Directory -Force $dir | Out-Null
$prev = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "media"

function Col($a, $r, $g, $b) { [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }
function Grad($top, $bottom) { New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Rectangle 0, 0, 128, 128), $top, $bottom, 90.0 }

function Save-Tga($bmp, $path) {
	$s = $bmp.Width
	$fs = [System.IO.File]::Create($path)
	$bw = New-Object System.IO.BinaryWriter $fs
	$bw.Write([byte[]](0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0)); $bw.Write([uint16]$s); $bw.Write([uint16]$s); $bw.Write([byte]32); $bw.Write([byte]0x28)
	for ($y = 0; $y -lt $s; $y++) { for ($x = 0; $x -lt $s; $x++) { $c = $bmp.GetPixel($x, $y); $bw.Write([byte]$c.B); $bw.Write([byte]$c.G); $bw.Write([byte]$c.R); $bw.Write([byte]$c.A) } }
	$bw.Close()
}

function New-Canvas {
	$b = New-Object System.Drawing.Bitmap 128, 128, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
	$g = [System.Drawing.Graphics]::FromImage($b)
	$g.SmoothingMode = 'AntiAlias'
	$g.Clear([System.Drawing.Color]::Transparent)
	return @($b, $g)
}

function Bang($g, $top, $bottom, $outline, $mid, $size, $dy) {
	$path = New-Object System.Drawing.Drawing2D.GraphicsPath
	$fmt = New-Object System.Drawing.StringFormat
	$fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
	$path.AddString("!", (New-Object System.Drawing.FontFamily "Arial Black"), 1, $size, (New-Object System.Drawing.RectangleF 0, $dy, 128, 128), $fmt)
	$g.DrawPath((New-Object System.Drawing.Pen $outline, 16), $path)
	$g.DrawPath((New-Object System.Drawing.Pen $mid, 8), $path)
	$g.FillPath((Grad $top $bottom), $path)
	$g.Clip = New-Object System.Drawing.Region $path
	$g.FillEllipse((New-Object System.Drawing.SolidBrush (Col 160 255 255 240)), 40, 2, 24, 60)
	$g.ResetClip()
}

$gold = @((Col 255 255 248 120), (Col 255 240 150 10), (Col 255 20 10 0), (Col 255 120 60 0))
$styles = @{
	gold = $gold
	blue = @((Col 255 170 230 255), (Col 255 30 120 230), (Col 255 5 10 30), (Col 255 20 60 140))
	red  = @((Col 255 255 160 140), (Col 255 210 30 20), (Col 255 25 0 0), (Col 255 120 10 0))
}
foreach ($name in $styles.Keys) {
	$b, $g = New-Canvas
	$p = $styles[$name]
	Bang $g $p[0] $p[1] $p[2] $p[3] 132 4
	$g.Dispose(); Save-Tga $b "$dir\$name.tga"; $b.Save("$prev\i_$name.png")
}

# Badge: dark round shield with a gold rim and a gold "!"
$b, $g = New-Canvas
$g.FillEllipse((New-Object System.Drawing.SolidBrush (Col 255 15 10 5)), 6, 6, 116, 116)
$g.FillEllipse((Grad (Col 255 255 225 120) (Col 255 150 90 10)), 10, 10, 108, 108)
$g.FillEllipse((Grad (Col 255 60 40 20) (Col 255 20 12 6)), 18, 18, 92, 92)
Bang $g $gold[0] $gold[1] $gold[2] $gold[3] 92 6
$g.Dispose(); Save-Tga $b "$dir\badge.tga"; $b.Save("$prev\i_badge.png")

# Pixel: crisp 16x16 grid drawn at 8x
$b = New-Object System.Drawing.Bitmap 128, 128, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($b); $g.Clear([System.Drawing.Color]::Transparent)
$px = @("......XXXX......", ".....XYYYOX.....", ".....XYYYOX.....", ".....XYYYOX.....", ".....XYYYOX.....", "......XYOX......", "......XYOX......", "......XYOX......", "......XYOX......", ".......XX.......", "................", "......XXXX......", ".....XYYOOX.....", ".....XYOOOX.....", "......XXXX......", "................")
$pal = @{ 'X' = (Col 255 25 15 5); 'Y' = (Col 255 255 230 90); 'O' = (Col 255 235 140 20) }
for ($r = 0; $r -lt 16; $r++) { for ($c = 0; $c -lt 16; $c++) { $ch = [string]$px[$r][$c]; if ($pal.ContainsKey($ch)) { $g.FillRectangle((New-Object System.Drawing.SolidBrush $pal[$ch]), $c * 8, $r * 8, 8, 8) } } }
$g.Dispose(); Save-Tga $b "$dir\pixel.tga"; $b.Save("$prev\i_pixel.png")

# Contact sheet for review
$sheet = New-Object System.Drawing.Bitmap 680, 140
$sg = [System.Drawing.Graphics]::FromImage($sheet); $sg.Clear((Col 255 40 50 40))
$i = 0
foreach ($n in "gold", "blue", "red", "badge", "pixel") { $img = [System.Drawing.Image]::FromFile("$prev\i_$n.png"); $sg.DrawImage($img, 6 + $i * 135, 6, 128, 128); $img.Dispose(); $i++ }
$sg.Dispose(); $sheet.Save("$prev\icons_sheet.png")
Get-ChildItem $dir | Select-Object -ExpandProperty Name
