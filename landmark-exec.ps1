# 依 landmark-map.csv 建景點子夾並搬移（兩區）。注意：PS 變數不分大小寫，根路徑用 $ROOT
$ErrorActionPreference = 'Continue'
$ROOT = 'C:\path\to\photos'
$CSVP = 'C:\path\to\staging\landmark-map.csv'

$dayDir = @{}
foreach ($d in (Get-ChildItem -LiteralPath $ROOT -Directory | Where-Object { $_.Name -match '^04-\d\d ' })) {
  $dayDir[$d.Name.Substring(0,5)] = $d.Name
}

$rows = Import-Csv -LiteralPath $CSVP
$dirs = $rows | ForEach-Object {
  if ($_.area -eq 'main') { Join-Path $ROOT "$($dayDir[$_.day])\$($_.target)" }
  else { Join-Path $ROOT "連拍其餘\$($_.day)\$($_.target)" }
} | Sort-Object -Unique
foreach ($p in $dirs) { if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
Write-Output "目標夾: $($dirs.Count) 個"

$moved = 0; $miss = 0; $fail = 0
foreach ($r in $rows) {
  if ($r.area -eq 'main') { $basep = Join-Path $ROOT $dayDir[$r.day] }
  else { $basep = Join-Path $ROOT "連拍其餘\$($r.day)" }
  $sp = Join-Path $basep $r.file
  $dp = Join-Path $basep "$($r.target)\$($r.file)"
  if (-not (Test-Path -LiteralPath $sp)) { $miss++; continue }
  try { Move-Item -LiteralPath $sp -Destination $dp -ErrorAction Stop; $moved++ }
  catch { $fail++; if ($fail -le 3) { Write-Output "FAIL $($r.file): $($_.Exception.Message)" } }
}
Write-Output "搬移: $moved、來源不存在: $miss、失敗: $fail"

Write-Output ""
Write-Output "═══ 驗證 ═══"
$total = (Get-ChildItem -LiteralPath $ROOT -Recurse -File | Measure-Object).Count
Write-Output "遞迴總數: $total（期望 5309）"
foreach ($d in ($dayDir.GetEnumerator() | Sort-Object Name)) {
  $flat = @(Get-ChildItem -LiteralPath (Join-Path $ROOT $d.Value) -File).Count
  $subs = (Get-ChildItem -LiteralPath (Join-Path $ROOT $d.Value) -Directory | ForEach-Object {
    "$($_.Name)($(@(Get-ChildItem -LiteralPath $_.FullName -File).Count))" }) -join ' '
  Write-Output "$($d.Value): 平放殘留 $flat | $subs"
}
foreach ($d in (Get-ChildItem -LiteralPath (Join-Path $ROOT '連拍其餘') -Directory | Sort-Object Name)) {
  $flat = @(Get-ChildItem -LiteralPath $d.FullName -File).Count
  $subs = (Get-ChildItem -LiteralPath $d.FullName -Directory | ForEach-Object {
    "$($_.Name)($(@(Get-ChildItem -LiteralPath $_.FullName -File).Count))" }) -join ' '
  Write-Output "連拍其餘\$($d.Name): 平放殘留 $flat | $subs"
}
