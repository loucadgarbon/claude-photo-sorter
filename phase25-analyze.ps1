# Phase 2.5 前置分析：彙整標籤 + 連拍分組統計（只讀不動，供決策）
$ErrorActionPreference = 'Continue'
$TAGS = 'C:\path\to\staging\tags'
$SRC  = 'C:\path\to\photos'
$OUT  = 'C:\path\to\staging\phase25-report.txt'
$L = New-Object System.Collections.Generic.List[string]
function W([string]$m) { $L.Add($m) }

# ── 載入標籤 ──
$tagMap = @{}
foreach ($s in (Get-ChildItem $TAGS -Filter 'batch*.jsonl' -File)) {
  foreach ($line in [System.IO.File]::ReadAllLines($s.FullName)) {
    try { $o = $line | ConvertFrom-Json; $tagMap[$o.file] = $o } catch {}
  }
}
W ("標籤載入: {0} 筆" -f $tagMap.Count)

# ── 連拍分組（時間戳間隔 ≤2 秒的連續序列；(n) 後綴同組）──
function Get-Stamp([string]$name) {
  if ($name -match '^(\d{8})_(\d{6})') {
    return [datetime]::ParseExact($matches[1] + $matches[2], 'yyyyMMddHHmmss', $null)
  }
  return $null
}
$files = Get-ChildItem -LiteralPath $SRC -Filter '*.jpg' -File | Sort-Object Name
$groups = @(); $cur = @()
$prev = $null
foreach ($f in $files) {
  $ts = Get-Stamp $f.Name
  if ($null -eq $ts) { if ($cur.Count) { $groups += ,$cur; $cur = @() }; $prev = $null; continue }
  if ($null -ne $prev -and ($ts - $prev).TotalSeconds -le 2) { $cur += $f }
  else { if ($cur.Count) { $groups += ,$cur }; $cur = @($f) }
  $prev = $ts
}
if ($cur.Count) { $groups += ,$cur }

$bursts   = @($groups | Where-Object { $_.Count -ge 2 })
$keepers  = @($groups | ForEach-Object { ($_ | Sort-Object Length -Descending)[0] })
$demoted  = @($bursts | ForEach-Object { ($_ | Sort-Object Length -Descending) | Select-Object -Skip 1 }) | ForEach-Object { $_ }
W ""
W ("照片總數: {0}" -f $files.Count)
W ("連拍組(≥2張): {0} 組，共 {1} 張" -f $bursts.Count, (($bursts | ForEach-Object { $_.Count }) | Measure-Object -Sum).Sum)
W ("日夾保留(每組1張+單張): {0} 張" -f $keepers.Count)
W ("移入連拍其餘: {0} 張" -f @($demoted).Count)
$big = $bursts | Sort-Object Count -Descending | Select-Object -First 5
W "最大連拍組:"
foreach ($b in $big) { W ("  {0} 張  {1} ~ {2}" -f $b.Count, $b[0].Name, $b[-1].Name) }

# ── 各日彙整 ──
W ""
W "═══ 各日標籤彙整 ═══"
$byDay = $files | Group-Object { $_.Name.Substring(4,4) } | Sort-Object Name
foreach ($d in $byDay) {
  $dayTags = @($d.Group | ForEach-Object { $tagMap[$_.Name] } | Where-Object { $_ })
  $lm = $dayTags | Where-Object { $_.landmark -and "$($_.landmark)" -ne '' -and "$($_.landmark)" -ne 'null' } |
        Group-Object { $_.landmark } | Sort-Object Count -Descending | Select-Object -First 5
  $sc = $dayTags | ForEach-Object { $_.scene } | Group-Object | Sort-Object Count -Descending | Select-Object -First 6
  $pp = $dayTags | Group-Object { $_.people } | Sort-Object Count -Descending
  W ("--- {0}/{1}  共 {2} 張（已標 {3}）" -f $d.Name.Substring(0,2), $d.Name.Substring(2,2), $d.Count, $dayTags.Count)
  W ("    地標: " + $(if ($lm) { ($lm | ForEach-Object { "$($_.Name)×$($_.Count)" }) -join '、' } else { '（無）' }))
  W ("    場景: " + (($sc | ForEach-Object { "$($_.Name)×$($_.Count)" }) -join ' '))
  W ("    人物: " + (($pp | ForEach-Object { "$($_.Name)×$($_.Count)" }) -join ' '))
}
[System.IO.File]::WriteAllLines($OUT, $L)
Write-Output ("報告已寫出: " + $OUT)
Get-Content $OUT
