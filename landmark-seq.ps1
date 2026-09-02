# 景點夾時序化：target 內 gap>60min 切 block → 依中位時間編號 → 「NN 名稱 HH時」
$ErrorActionPreference = 'Continue'
$ROOT = 'C:\path\to\photos'
$CSVP = 'C:\path\to\staging\landmark-map.csv'
$OUTC = 'C:\path\to\staging\landmark-seq.csv'

$dayDir = @{}
foreach ($d in (Get-ChildItem -LiteralPath $ROOT -Directory | Where-Object { $_.Name -match '^\d\d-\d\d ' })) {
  $dayDir[$d.Name.Substring(0,5)] = $d.Name
}
function Get-Stamp([string]$name) {
  if ($name -match '^(\d{8})_(\d{6})') {
    return [datetime]::ParseExact($matches[1] + $matches[2], 'yyyyMMddHHmmss', $null)
  }
  return $null
}

$rows = Import-Csv -LiteralPath $CSVP | ForEach-Object {
  $_ | Add-Member -NotePropertyName Stamp -NotePropertyValue (Get-Stamp $_.file) -PassThru
}
$noTs = @($rows | Where-Object { $null -eq $_.Stamp })
Write-Output "映射 $($rows.Count) 筆、無時間戳 $($noTs.Count)"

$GAP = [timespan]::FromMinutes(60)
$outRows = New-Object System.Collections.Generic.List[string]
$outRows.Add('file,area,day,folder')
$moved = 0; $miss = 0; $fail = 0

foreach ($dg in ($rows | Group-Object day | Sort-Object Name)) {
  # ── block 化（合併兩區同一條時間軸）──
  $blocks = New-Object System.Collections.Generic.List[object]
  foreach ($tg in ($dg.Group | Group-Object target)) {
    $sorted = @($tg.Group | Sort-Object Stamp)
    $cur = New-Object System.Collections.Generic.List[object]
    $prevTs = $null
    foreach ($ph in $sorted) {
      if ($null -ne $prevTs -and ($ph.Stamp - $prevTs) -gt $GAP) {
        $blocks.Add(@{ Target=$tg.Name; Items=$cur }); $cur = New-Object System.Collections.Generic.List[object]
      }
      $cur.Add($ph); $prevTs = $ph.Stamp
    }
    if ($cur.Count) { $blocks.Add(@{ Target=$tg.Name; Items=$cur }) }
  }
  foreach ($b in $blocks) {
    $ts = @($b.Items | ForEach-Object Stamp | Sort-Object)
    $b.Median = $ts[[int][Math]::Floor($ts.Count/2)]
    $b.Start  = $ts[0]
  }
  $ordered = @($blocks | Sort-Object { $_.Median })

  # ── 編號 + 夾名 ──
  $n = 0
  foreach ($b in $ordered) {
    $n++
    $b.Folder = ('{0:d2} {1} {2:d2}時' -f $n, $b.Target, $b.Start.Hour)
  }

  # ── 搬移 ──
  foreach ($b in $ordered) {
    foreach ($ph in $b.Items) {
      if ($ph.area -eq 'main') { $basep = Join-Path $ROOT $dayDir[$ph.day] }
      else { $basep = Join-Path $ROOT "連拍其餘\$($ph.day)" }
      $newDir = Join-Path $basep $b.Folder
      if (-not (Test-Path -LiteralPath $newDir)) { New-Item -ItemType Directory -Path $newDir -Force | Out-Null }
      $sp = Join-Path $basep "$($ph.target)\$($ph.file)"
      $dp = Join-Path $newDir $ph.file
      $outRows.Add(('"{0}",{1},{2},"{3}"' -f $ph.file, $ph.area, $ph.day, $b.Folder))
      if (-not (Test-Path -LiteralPath $sp)) { $miss++; continue }
      try { Move-Item -LiteralPath $sp -Destination $dp -ErrorAction Stop; $moved++ }
      catch { $fail++; if ($fail -le 3) { Write-Output "FAIL $($ph.file): $($_.Exception.Message)" } }
    }
  }

  # ── 時序遞增檢查 ──
  $prevMed = $null; $mono = $true
  foreach ($b in $ordered) { if ($prevMed -and $b.Median -lt $prevMed) { $mono = $false }; $prevMed = $b.Median }
  $minBlk = ($ordered | ForEach-Object { $_.Items.Count } | Measure-Object -Minimum).Minimum
  Write-Output ("{0}: {1} blocks、最小 {2} 張、時序遞增 {3}" -f $dg.Name, $ordered.Count, $minBlk, $mono)
}
[System.IO.File]::WriteAllLines($OUTC, $outRows, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "搬移: $moved、來源不存在: $miss、失敗: $fail"

# ── 清空的舊景點夾移除 + 驗證 ──
$removed = 0
$allDayPaths = @($dayDir.Values | ForEach-Object { Join-Path $ROOT $_ }) +
               @(Get-ChildItem -LiteralPath (Join-Path $ROOT '連拍其餘') -Directory | ForEach-Object FullName)
foreach ($dp2 in $allDayPaths) {
  foreach ($sub in (Get-ChildItem -LiteralPath $dp2 -Directory | Where-Object { $_.Name -notmatch '^\d\d ' })) {
    if (@(Get-ChildItem -LiteralPath $sub.FullName -Recurse -File).Count -eq 0) {
      Remove-Item -LiteralPath $sub.FullName -Recurse -Force; $removed++
    } else { Write-Output "警告：舊夾非空 $($sub.FullName)" }
  }
}
Write-Output "移除空舊夾: $removed"
$total = (Get-ChildItem -LiteralPath $ROOT -Recurse -File | Measure-Object).Count
Write-Output "遞迴總數: $total（期望 5309）"
Write-Output ""
Write-Output "═══ 各日結構 ═══"
foreach ($d in ($dayDir.GetEnumerator() | Sort-Object Name)) {
  Write-Output "── $($d.Value)"
  foreach ($sub in (Get-ChildItem -LiteralPath (Join-Path $ROOT $d.Value) -Directory | Sort-Object Name)) {
    Write-Output ("    {0}  ({1})" -f $sub.Name, @(Get-ChildItem -LiteralPath $sub.FullName -File).Count)
  }
}
