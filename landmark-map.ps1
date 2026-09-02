# 景點層指派計算：標籤正規化 + 錨點時間內插 → landmark-map.csv + 統計預覽（只讀不搬）
$ErrorActionPreference = 'Stop'
$TAGS = 'C:\path\to\staging\tags'
$SRC  = 'C:\path\to\photos'
$CSV  = 'C:\path\to\staging\landmark-map.csv'
$RPT  = 'C:\path\to\staging\landmark-preview.txt'

# ── 標籤載入 ──
$tagMap = @{}
foreach ($s in (Get-ChildItem $TAGS -Filter 'batch*.jsonl' -File)) {
  foreach ($line in [System.IO.File]::ReadAllLines($s.FullName)) {
    try { $o = $line | ConvertFrom-Json; $tagMap[$o.file] = $o } catch {}
  }
}

# ── 地標正規化（由 itinerary.json 提供；用 itinerary-prompt.md 讓 Claude 產生）──
$ITIN = 'C:\path\to\staging\itinerary.json'
$itin = Get-Content -Raw -Encoding UTF8 $ITIN | ConvertFrom-Json
$norm = @{}
foreach ($p in $itin.landmarkAliases.PSObject.Properties) { $norm[$p.Name] = $p.Value }
function Get-Canon([object]$t) {
  if ($null -eq $t -or [string]::IsNullOrEmpty($t.landmark)) { return $null }
  $l = "$($t.landmark)"
  if ($norm.ContainsKey($l)) { return $norm[$l] } else { return $l }
}
function Get-Stamp([string]$name) {
  if ($name -match '^(\d{8})_(\d{6})') {
    return [datetime]::ParseExact($matches[1] + $matches[2], 'yyyyMMddHHmmss', $null)
  }
  return $null
}

# ── 收檔（兩區、含非 jpg）──
$dayDirs = Get-ChildItem -LiteralPath $SRC -Directory | Where-Object { $_.Name -match '^\d\d-\d\d ' }
$all = New-Object System.Collections.Generic.List[object]
foreach ($d in $dayDirs) {
  $day = $d.Name.Substring(0,5)   # "04-24"
  foreach ($f in (Get-ChildItem -LiteralPath $d.FullName -File)) {
    $all.Add([pscustomobject]@{ File=$f; Day=$day; Area='main'; Stamp=(Get-Stamp $f.Name) })
  }
}
$burstRoot = Join-Path $SRC '連拍其餘'
foreach ($d in (Get-ChildItem -LiteralPath $burstRoot -Directory)) {
  $day = $d.Name   # "04-24"
  foreach ($f in (Get-ChildItem -LiteralPath $d.FullName -File)) {
    $all.Add([pscustomobject]@{ File=$f; Day=$day; Area='burst'; Stamp=(Get-Stamp $f.Name) })
  }
}

$L = New-Object System.Collections.Generic.List[string]
$L.Add("檔案總數: $($all.Count)（main $(@($all|Where-Object Area -eq 'main').Count) / burst $(@($all|Where-Object Area -eq 'burst').Count)）")
$noStamp = @($all | Where-Object { $null -eq $_.Stamp })
$L.Add("無法解析時間戳: $($noStamp.Count)")
$ext = $all | Group-Object { $_.File.Extension.ToLower() } | ForEach-Object { "$($_.Name)×$($_.Count)" }
$L.Add("副檔名: $($ext -join ' ')")

# ── 各日錨點（含兩區）──
$anchorsByDay = @{}
foreach ($g in ($all | Group-Object Day)) {
  $a = @($g.Group | ForEach-Object {
        $c = Get-Canon $tagMap[$_.File.Name]
        if ($c -and $_.Stamp) { [pscustomobject]@{ T=$_.Stamp; L=$c } }
      } | Where-Object { $_ } | Sort-Object T)
  $anchorsByDay[$g.Name] = @{
    Times = [datetime[]]@($a | ForEach-Object T)
    Names = [string[]]@($a | ForEach-Object L)
  }
}

# ── 指派 ──
$MAXGAP = [timespan]::FromMinutes(25)
$rows = New-Object System.Collections.Generic.List[string]
$rows.Add('file,area,day,target')
foreach ($x in $all) {
  if (@($itin.skipDays) -contains $x.Day) { continue }   # 張數過少、不建景點夾的日子
  $t = $tagMap[$x.File.Name]
  $canon = Get-Canon $t
  $target = $null
  if ($canon) { $target = $canon }
  elseif ($x.Stamp) {
    $an = $anchorsByDay[$x.Day]
    if ($an.Times.Count -gt 0) {
      $i = [Array]::BinarySearch($an.Times, $x.Stamp)
      if ($i -lt 0) { $i = -bnot $i }
      $best = $null; $bestGap = [timespan]::MaxValue
      foreach ($j in @(($i-1), $i)) {
        if ($j -ge 0 -and $j -lt $an.Times.Count) {
          $gap = if ($x.Stamp -gt $an.Times[$j]) { $x.Stamp - $an.Times[$j] } else { $an.Times[$j] - $x.Stamp }
          if ($gap -lt $bestGap) { $bestGap = $gap; $best = $an.Names[$j] }
        }
      }
      if ($best -and $bestGap -le $MAXGAP) { $target = $best }
    }
  }
  if (-not $target) {
    if ($t -and @($t.scene) -contains '餐食') { $target = '餐飲' } else { $target = '移動與街景' }
  }
  $rows.Add(('"{0}",{1},{2},"{3}"' -f $x.File.Name, $x.Area, $x.Day, $target))
}
[System.IO.File]::WriteAllLines($CSV, $rows, (New-Object System.Text.UTF8Encoding($false)))

# ── 預覽統計 ──
$L.Add(''); $L.Add('═══ 指派預覽（main 區）═══')
$parsed = $rows | Select-Object -Skip 1 | ForEach-Object {
  $p = $_ -split ','; [pscustomobject]@{ Area=$p[1]; Day=$p[2]; Target=$p[3].Trim('"') }
}
foreach ($g in ($parsed | Where-Object Area -eq 'main' | Group-Object Day | Sort-Object Name)) {
  $L.Add("--- $($g.Name)")
  foreach ($t in ($g.Group | Group-Object Target | Sort-Object Count -Descending)) {
    $L.Add(("    {0,-14} {1,5}" -f $t.Name, $t.Count))
  }
}
$L.Add(''); $L.Add('═══ 指派預覽（burst 區）═══')
foreach ($g in ($parsed | Where-Object Area -eq 'burst' | Group-Object Day | Sort-Object Name)) {
  $sum = ($g.Group | Group-Object Target | Sort-Object Count -Descending | ForEach-Object { "$($_.Name)×$($_.Count)" }) -join '、'
  $L.Add("--- $($g.Name): $sum")
}
[System.IO.File]::WriteAllLines($RPT, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "完成，映射 $($rows.Count-1) 筆"
