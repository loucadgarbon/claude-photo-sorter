# 旅行照縮圖管線：讀原檔（觸發 OneDrive hydration）→ 1024px 縮圖到暫存
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
$SRC  = 'C:\path\to\photos'
$OUT  = 'C:\path\to\staging\thumbs'
$LOG  = 'C:\path\to\staging\thumbs.log'
New-Item -ItemType Directory -Path $OUT -Force | Out-Null

function Log([string]$m) { Add-Content -LiteralPath $LOG -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }

$files = Get-ChildItem -LiteralPath $SRC -Filter '*.jpg' -File | Sort-Object Name
Log ("啟動：共 {0} 張" -f $files.Count)

$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep  = New-Object System.Drawing.Imaging.EncoderParameters(1)
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [int64]70)

$done = 0; $skip = 0; $err = 0
foreach ($f in $files) {
    $tp = Join-Path $OUT $f.Name
    if (Test-Path -LiteralPath $tp) { $skip++; continue }   # 可續作
    try {
        $img = [System.Drawing.Image]::FromFile($f.FullName)   # 讀取即 hydrate
        $w = $img.Width; $h = $img.Height
        $scale = 1024.0 / [Math]::Max($w, $h)
        if ($scale -ge 1) { $nw = $w; $nh = $h } else { $nw = [int]($w*$scale); $nh = [int]($h*$scale) }
        $bmp = New-Object System.Drawing.Bitmap($nw, $nh)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = 'HighQualityBicubic'
        $g.DrawImage($img, 0, 0, $nw, $nh)
        $bmp.Save($tp, $enc, $ep)
        $g.Dispose(); $bmp.Dispose(); $img.Dispose()
        $done++
        if ($done % 200 -eq 0) { Log ("進度 {0}/{1}" -f ($done+$skip), $files.Count) }
    } catch {
        $err++
        Log ("ERR {0}: {1}" -f $f.Name, $_.Exception.Message.Substring(0,[Math]::Min(60,$_.Exception.Message.Length)))
        try { if ($img) { $img.Dispose() } } catch {}
    }
}
Log ("完成：新縮圖 {0}、續作跳過 {1}、失敗 {2}" -f $done, $skip, $err)
Log 'DONE'
