Add-Type -AssemblyName System.Drawing
$out = "D:\Games\CS.Coder\WoW Addons\CSCoder_QuestIndicator_logo.png"
$S = 400
function Col($a, $r, $g, $b) { [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }

$b = New-Object System.Drawing.Bitmap $S, $S, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($b)
$g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'

# Background: dark radial vignette with a warm center
$g.Clear((Col 255 12 9 6))
$bg = New-Object System.Drawing.Drawing2D.GraphicsPath
$bg.AddEllipse(-80, -60, $S + 160, $S + 160)
$pb = New-Object System.Drawing.Drawing2D.PathGradientBrush $bg
$pb.CenterColor = (Col 255 70 42 14); $pb.SurroundColors = @((Col 255 10 7 4))
$pb.CenterPoint = New-Object System.Drawing.PointF 200, 180
$g.FillRectangle($pb, 0, 0, $S, $S)

# Soft glow behind the mark
for ($i = 0; $i -lt 14; $i++) {
	$r = 170 - $i * 10
	$g.FillEllipse((New-Object System.Drawing.SolidBrush (Col 14 255 190 60)), 200 - $r, 175 - $r, $r * 2, $r * 2)
}

# Gold ring
$ring = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Rectangle 0, 0, $S, $S), (Col 255 255 230 130), (Col 255 140 80 10), 90.0
$g.FillEllipse((New-Object System.Drawing.SolidBrush (Col 255 15 10 5)), 52, 27, 296, 296)
$g.FillEllipse($ring, 60, 35, 280, 280)
$inner = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Rectangle 0, 50, $S, 260), (Col 255 62 40 18), (Col 255 22 13 6), 90.0
$g.FillEllipse($inner, 78, 53, 244, 244)

# The "!"
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
$path.AddString("!", (New-Object System.Drawing.FontFamily "Arial Black"), 1, 230, (New-Object System.Drawing.RectangleF 0, 50, $S, 260), $fmt)
$g.DrawPath((New-Object System.Drawing.Pen (Col 255 20 10 0), 22), $path)
$g.DrawPath((New-Object System.Drawing.Pen (Col 255 120 60 0), 10), $path)
$fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Rectangle 0, 70, $S, 220), (Col 255 255 248 120), (Col 255 240 150 10), 90.0
$g.FillPath($fill, $path)
$g.Clip = New-Object System.Drawing.Region $path
$g.FillEllipse((New-Object System.Drawing.SolidBrush (Col 150 255 255 240)), 168, 60, 40, 150)
$g.ResetClip()

# Title
$tfmt = New-Object System.Drawing.StringFormat; $tfmt.Alignment = 'Center'
$title = New-Object System.Drawing.Drawing2D.GraphicsPath
$title.AddString("QUEST INDICATOR", (New-Object System.Drawing.FontFamily "Arial Black"), 0, 34, (New-Object System.Drawing.RectangleF 0, 328, $S, 50), $tfmt)
$g.DrawPath((New-Object System.Drawing.Pen (Col 255 15 8 0), 7), $title)
$g.FillPath((New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Rectangle 0, 330, $S, 40), (Col 255 255 236 150), (Col 255 225 150 30), 90.0), $title)
$g.DrawString("CS.Coder", (New-Object System.Drawing.Font "Segoe UI Semibold", 13), (New-Object System.Drawing.SolidBrush (Col 200 230 200 150)), (New-Object System.Drawing.RectangleF 0, 370, $S, 26), $tfmt)

$g.Dispose(); $b.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose()
$out
