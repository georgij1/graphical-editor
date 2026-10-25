param(
  [string]$WebDir = "web"
)

# Renders the application icon (rounded square with a visual-designer glyph)
# and writes every size the web build needs.
Add-Type -AssemblyName System.Drawing

$brand   = [System.Drawing.Color]::FromArgb(255, 3, 158, 211)
$brandLt = [System.Drawing.Color]::FromArgb(255, 79, 195, 235)
$brandDk = [System.Drawing.Color]::FromArgb(255, 2, 105, 150)
$ink     = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)

function New-Brushes {
  param($rect)
  # Single vertical gradient across the whole tile; a second overlay used to
  # leave a visible seam where it ended.
  return New-Object System.Drawing.Drawing2D.LinearGradientBrush `
    $rect, $brandLt, $brandDk, 90.0
}

function New-Circle {
  param([float]$x, [float]$y, [float]$d, $color)
  $bmp = New-Object System.Drawing.Bitmap 1,1
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.Dispose(); $bmp.Dispose()
  $brush = New-Object System.Drawing.SolidBrush $color
  return @{ brush = $brush; rect = (New-Object System.Drawing.RectangleF $x, $y, $d, $d) }
}

function Draw-Glyph {
  param($g, [float]$s)
  # $s is the canvas edge (icon size). All coordinates are relative.
  $m = $s * 0.205           # margin
  $w = $s - 2 * $m          # frame width
  $h = $s - 2 * $m
  $unit = $w / 100.0

  $framePen = New-Object System.Drawing.Pen $ink, ($s * 0.030)
  $framePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $framePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $g.DrawRectangle($framePen, $m, $m, $w, $h)

  # Left sidebar: the editor panels.
  $sidebar = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(64, 255, 255, 255))
  $sb = New-Object System.Drawing.RectangleF ($m + $unit*5), ($m + $unit*5), ($unit*20), ($unit*90)
  $g.FillRectangle($sidebar, $sb)

  # Three rows in the sidebar.
  $row = New-Object System.Drawing.SolidBrush $ink
  for ($i = 0; $i -lt 3; $i++) {
    $y = $m + $unit * (14 + $i * 20)
    $r = New-Object System.Drawing.RectangleF ($m + $unit*9), $y, ($unit*12), ($unit*5)
    $g.FillEllipse($row, $r)
  }

  # Canvas area on the right: a small widget tree.
  $linePen = New-Object System.Drawing.Pen $ink, ($s * 0.022)

  # Root node
  $rootSize = $unit * 11
  $rootX = $m + $unit*44
  $rootY = $m + $unit*12
  $root = New-Object System.Drawing.RectangleF $rootX, $rootY, $rootSize, $rootSize
  $g.FillEllipse($row, $root)

  # Connector down to two children
  $cx = $root.X + $rootSize/2
  $g.DrawLine($linePen, $cx, ($root.Y + $rootSize), $cx, ($m + $unit*36))

  foreach ($dx in @(-15, 15)) {
    $childX = $cx + ($unit * $dx) - ($unit * 5.5)
    $childY = $m + $unit*36
    $g.DrawLine($linePen, $cx, $childY, ($childX + ($unit*5.5)), $childY)
    $g.DrawLine($linePen, ($childX + ($unit*5.5)), $childY, ($childX + ($unit*5.5)), ($childY + ($unit*7)))
    $child = New-Object System.Drawing.RectangleF $childX, ($childY + ($unit*7)), ($unit*11), ($unit*11)
    $g.FillEllipse($row, $child)
  }

  # Bottom hint bar (status bar)
  $bar = New-Object System.Drawing.RectangleF ($m + $unit*30), ($m + $unit*66), ($unit*40), ($unit*5)
  $g.FillRectangle($row, $bar)
}

function New-Icon {
  param([int]$size, [int]$padding)
  $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.Clear([System.Drawing.Color]::Transparent)

  $pad = $padding
  $s = $size - 2 * $pad
  $rect = New-Object System.Drawing.RectangleF $pad, $pad, $s, $s
  $radius = $s * 0.22

  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $radius * 2
  $path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
  $path.AddArc($rect.Right - $d, $rect.Y, $d, $d, 270, 90)
  $path.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
  $path.AddArc($rect.X, $rect.Bottom - $d, $d, $d, 90, 90)
  $path.CloseFigure()

  $brush = New-Brushes $rect
  $g.FillPath($brush, $path)

$g.SetClip($path)
  Draw-Glyph $g $s
  $g.ResetClip()

  # Re-stroke the outline so the glyph never touches the edge.
  $edge = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(60, 0, 0, 0)), 1.0
  $g.DrawPath($edge, $path)
  $g.Dispose()
  return $bmp
}

function Save-Icon {
  param([int]$size, [int]$padding, [string]$path)
  $bmp = New-Icon $size $padding
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output ("wrote {0} ({1}x{1})" -f $path, $size)
}

$icons = Join-Path $WebDir "icons"
if (-not (Test-Path -LiteralPath $icons)) {
  New-Item -ItemType Directory -Path $icons | Out-Null
}

Save-Icon 512 0 (Join-Path $icons "Icon-512.png")
Save-Icon 192 0 (Join-Path $icons "Icon-192.png")
Save-Icon 32  0 (Join-Path $WebDir "favicon.png")
# Maskable icons are cropped to a circle by the launcher, so keep the glyph
# inside the safe zone (80% of the canvas).
Save-Icon 512 52 (Join-Path $icons "Icon-maskable-512.png")
Save-Icon 192 20 (Join-Path $icons "Icon-maskable-192.png")