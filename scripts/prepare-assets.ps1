$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$projectDirectory = Split-Path -Parent $PSScriptRoot
$assetDirectory = Join-Path $projectDirectory 'assets'
[void](New-Item -ItemType Directory -Path $assetDirectory -Force)

# Keep the original eight-pixel corners and take a single pixel from each
# middle edge. CSS repeats these strips at their original pixel size.
$boxSource = [System.Drawing.Bitmap]::new((Join-Path $projectDirectory 'button-box.png'))
$boxSlice = [System.Drawing.Bitmap]::new(17, 17)
try {
    for ($sliceY = 0; $sliceY -lt 17; $sliceY++) {
        $sourceY = if ($sliceY -lt 8) { $sliceY } elseif ($sliceY -eq 8) { 32 } else { $sliceY + 47 }
        for ($sliceX = 0; $sliceX -lt 17; $sliceX++) {
            $sourceX = if ($sliceX -lt 8) { $sliceX } elseif ($sliceX -eq 8) { 32 } else { $sliceX + 47 }
            $boxSlice.SetPixel($sliceX, $sliceY, $boxSource.GetPixel($sourceX, $sourceY))
        }
    }
    $boxSlice.Save((Join-Path $assetDirectory 'button-box-slice.png'), [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $boxSlice.Dispose()
    $boxSource.Dispose()
}

# Read the supplied ICO's embedded PNG directly: its directory dimensions
# do not match the non-square PNG. Repackage square, browser-sized entries.
$iconBytes = [System.IO.File]::ReadAllBytes((Join-Path $projectDirectory 'favicon_512x512.ico'))
$imageLength = [System.BitConverter]::ToInt32($iconBytes, 14)
$imageOffset = [System.BitConverter]::ToInt32($iconBytes, 18)
$sourceStream = [System.IO.MemoryStream]::new($iconBytes, $imageOffset, $imageLength)
$iconSource = [System.Drawing.Image]::FromStream($sourceStream)
$iconEntries = [System.Collections.Generic.List[object]]::new()
$iconSizes = @(16, 32, 48, 64, 128, 256)

try {
    foreach ($iconSize in $iconSizes) {
        $squareIcon = [System.Drawing.Bitmap]::new($iconSize, $iconSize)
        $graphics = [System.Drawing.Graphics]::FromImage($squareIcon)
        $pngStream = [System.IO.MemoryStream]::new()
        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
            $imageScale = [Math]::Min($iconSize / $iconSource.Width, $iconSize / $iconSource.Height)
            $imageWidth = [int][Math]::Round($iconSource.Width * $imageScale)
            $imageHeight = [int][Math]::Round($iconSource.Height * $imageScale)
            $imageLeft = [int][Math]::Floor(($iconSize - $imageWidth) / 2)
            $imageTop = [int][Math]::Floor(($iconSize - $imageHeight) / 2)
            $destination = [System.Drawing.Rectangle]::new($imageLeft, $imageTop, $imageWidth, $imageHeight)
            $graphics.DrawImage($iconSource, $destination, 0, 0, $iconSource.Width, $iconSource.Height, [System.Drawing.GraphicsUnit]::Pixel)
            $squareIcon.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
            $entryBytes = $pngStream.ToArray()
            $iconEntries.Add([pscustomobject]@{ Size = $iconSize; Bytes = $entryBytes })
            if ($iconSize -eq 32) {
                [System.IO.File]::WriteAllBytes((Join-Path $projectDirectory 'favicon-32.png'), $entryBytes)
            }
        } finally {
            $pngStream.Dispose()
            $graphics.Dispose()
            $squareIcon.Dispose()
        }
    }

    $outputStream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($outputStream)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$iconEntries.Count)
        $entryOffset = 6 + 16 * $iconEntries.Count
        foreach ($entry in $iconEntries) {
            $directorySize = if ($entry.Size -eq 256) { 0 } else { $entry.Size }
            $writer.Write([byte]$directorySize)
            $writer.Write([byte]$directorySize)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$entry.Bytes.Length)
            $writer.Write([uint32]$entryOffset)
            $entryOffset += $entry.Bytes.Length
        }
        foreach ($entry in $iconEntries) {
            $writer.Write([byte[]]$entry.Bytes)
        }
        $writer.Flush()
        [System.IO.File]::WriteAllBytes((Join-Path $projectDirectory 'favicon.ico'), $outputStream.ToArray())
    } finally {
        $writer.Dispose()
        $outputStream.Dispose()
    }
} finally {
    $iconSource.Dispose()
    $sourceStream.Dispose()
}

Write-Output 'Created 17x17 pixel-preserving frame, square favicon PNG, and multi-size ICO.'
