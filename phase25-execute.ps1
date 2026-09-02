# Phase 2.5 執行：日夾細分 + 連拍分離（同秒為一組）+ ExifTool XMP 標籤
$ErrorActionPreference = 'Continue'
$TAGS = 'C:\path\to\staging\tags'
$SRC  = 'C:\path\to\photos'
$LOG  = 'C:\path\to\staging\phase25-exec.log'
$L = New-Object System.Collections.Generic.List[string]
function W([string]$m) { $L.Add($m); [System.IO.File]::WriteAllLines($LOG, $L) }

# 日夾名由 itinerary.json 提供（用 itinerary-prompt.md 讓 Claude 產生）
$ITIN = 'C:\path\to\staging\itinerary.json'
$itin = Get-Content -Raw -Encoding UTF8 $ITIN | ConvertFrom-Json
$dayNames = @{}
foreach ($p in $itin.dayNames.PSObject.Properties) { $dayNames[$p.Name] = $p.Value }

# ── 載入標籤 ──
$tagMap = @{}
foreach ($s in (Get-ChildItem $TAGS -Filter 'batch*.jsonl' -File)) {
  foreach ($line in [System.IO.File]::ReadAllLines($s.FullName)) {
    try { $o = $line | ConvertFrom-Json; $tagMap[$o.file] = $o } catch {}
  }
}
W ("標籤: {0} 筆" -f $tagMap.Count)

# ── 連拍分組：同一秒（含 (n) 變體）──
$jpgs = Get-ChildItem -LiteralPath $SRC -Filter '*.jpg' -File | Sort-Object Name
$bySecond = $jpgs | Group-Object { if ($_.Name -match '^(\d{8}_\d{6})') { $matches[1] } else { $_.Name } }
$keep = @{}; $demote = @{}
foreach ($g in $bySecond) {
  $sorted = $g.Group | Sort-Object Length -Descending
  $keep[$sorted[0].Name] = $true
  foreach ($x in ($sorted | Select-Object -Skip 1)) { $demote[$x.Name] = $true }
}
W ("同秒組: {0}；日夾保留 {1}；連拍其餘 {2}" -f $bySecond.Count, $keep.Count, $demote.Count)

# ── 建資料夾並搬移 ──
foreach ($dn in $dayNames.Values) { New-Item -ItemType Directory -Path (Join-Path $SRC $dn) -Force | Out-Null }
$movedK = 0; $movedD = 0; $err = 0
$allFiles = Get-ChildItem -LiteralPath $SRC -File | Where-Object { $_.Extension -match '\.(jpg|mp4)$' }
foreach ($f in $allFiles) {
  $mmdd = if ($f.Name -match '^2026(\d{4})_') { $matches[1] } else { $f.LastWriteTime.ToString('MMdd') }
  $day = $dayNames[$mmdd]
  if (-not $day) { W ("SKIP 無日夾: " + $f.Name); continue }
  if ($demote.ContainsKey($f.Name)) {
    $dest = Join-Path $SRC ("連拍其餘\" + $mmdd.Insert(2,'-'))
    if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
    try { Move-Item -LiteralPath $f.FullName -Destination (Join-Path $dest $f.Name); $movedD++ } catch { $err++ }
  } else {
    try { Move-Item -LiteralPath $f.FullName -Destination (Join-Path $SRC "$day\$($f.Name)"); $movedK++ } catch { $err++ }
  }
}
W ("搬移完成: 日夾 {0}、連拍其餘 {1}、失敗 {2}" -f $movedK, $movedD, $err)

# ── 產生 ExifTool argfile（僅 XMP-dc:Subject，UTF-8 原生）──
$argf = 'C:\path\to\staging\exif-args.txt'
$A = New-Object System.Collections.Generic.List[string]
$tagged = 0
foreach ($f in (Get-ChildItem -LiteralPath $SRC -Recurse -Filter '*.jpg' -File)) {
  $t = $tagMap[$f.Name]
  if (-not $t) { continue }
  $subjects = @()
  foreach ($sc in $t.scene) { $subjects += $sc }
  $lm = "$($t.landmark)"
  if ($lm -and $lm -ne 'null') {
    if ($itin.landmarkAliases.PSObject.Properties[$lm]) { $lm = $itin.landmarkAliases.$lm }
    $subjects += $lm
  }
  if ($t.people -and $t.people -ne '無人') { $subjects += $t.people }
  $subjects += $itin.albumTag
  foreach ($s in ($subjects | Select-Object -Unique)) { $A.Add("-XMP-dc:Subject+=$s") }
  $A.Add($f.FullName)
  $A.Add('-execute')
  $tagged++
}
[System.IO.File]::WriteAllLines($argf, $A, (New-Object System.Text.UTF8Encoding($false)))
W ("argfile: {0} 檔待寫標籤" -f $tagged)

# ── 執行 ExifTool ──
$et = "$env:LOCALAPPDATA\Programs\ExifTool\ExifTool.exe"
$sw = [Diagnostics.Stopwatch]::StartNew()
& $et -@ $argf -common_args -P -overwrite_original -charset filename=UTF8 2>&1 |
  Select-Object -Last 3 | ForEach-Object { W ("exiftool: " + $_) }
W ("ExifTool 完成，耗時 {0:N0} 秒" -f $sw.Elapsed.TotalSeconds)

# ── 驗證 ──
$final = Get-ChildItem -LiteralPath $SRC -Recurse -File
W ""
W "═══ 最終結構 ═══"
foreach ($d in (Get-ChildItem -LiteralPath $SRC -Directory | Sort-Object Name)) {
  $n = @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File).Count
  W ("  {0,-28} {1,5} 檔" -f $d.Name, $n)
}
W ("  根目錄殘留: " + @(Get-ChildItem -LiteralPath $SRC -File).Count)
W ("  總計: {0}（應為 5309）" -f $final.Count)
W 'DONE'
