# claude-photo-sorter

用 Claude 的視覺能力整理旅行照片庫的工作流：**Claude 看縮圖打標 → 地標錨點 + 時間
內插分類 → 連拍分組 → 依行程時序建資料夾 → ExifTool 寫入可搜尋標籤**。
一次實戰整理了 5,300+ 張旅行照片。行程資料（日夾名、地標別名、相簿標籤）不寫死在
程式碼裡——由 Claude 依標籤產生 `itinerary.json`（見 `itinerary-prompt.md`），腳本讀檔套用。

## 流程

| 步驟 | 檔案 | 做什麼 |
|---|---|---|
| 1. 縮圖 | `thumbnailer.ps1` | 原檔（OneDrive 會自動 hydrate）→ 1024px JPEG 到暫存，可續作 |
| 2. 打標 | `tagging-prompt.md` | **Claude session 直接看縮圖**，逐批輸出 `tags/batch*.jsonl`（scene/landmark/people） |
| 2.5 行程 | `itinerary-prompt.md` | **Claude 依標籤+時間戳產生 `itinerary.json`**（日夾名/地標別名/相簿標籤/skipDays，見 example） |
| 3. 映射 | `landmark-map.ps1` | 高把握地標當錨點，其餘照片時間內插（≤25 分鐘歸最近錨點）→ `landmark-map.csv` |
| 4. 時序化 | `landmark-seq.ps1` | 景點內 gap>60 分鐘切段、依起始時間編號 → `NN 名稱 HH時` 資料夾名 |
| 5. 搬移 | `landmark-exec.ps1` | 依映射實際搬檔 |
| 6. 連拍+標籤 | `phase25-analyze.ps1` / `phase25-execute.ps1` | 同秒連拍只留最大檔、其餘進 `連拍其餘\`；ExifTool argfile 批次寫 XMP-dc:Subject |

## 設計要點

- **分類是「錨點+內插」不是逐張猜**：Claude 只需在高把握時指認地標，時間戳補完其餘——比逐張分類穩定得多。
- **排序鍵用段落起始時間**，資料夾序號才會與 `HH時` 一致遞增。
- 全部腳本可續作（已存在即跳過），中斷重跑安全。
- ExifTool 標籤用 argfile + UTF-8（無 BOM），避免 PowerShell 引數編碼問題。

## 陷阱（實戰踩過）

- OneDrive 雲端檔未完全上傳時大量搬移，同步引擎可能在原路徑還原舊版檔案（殘影要事後比對清除）。
- PowerShell 變數不分大小寫：`$SRC` 會被迴圈裡的 `$src` 覆寫。
- `@($i-1, $i)` 逗號優先權高於減號，要寫 `@(($i-1), $i)`。

## 使用

把各腳本頂端的 `C:\path\to\photos`（照片庫）與 `C:\path\to\staging`（工作目錄）改成
你的路徑，用 `itinerary-prompt.md` 讓 Claude 產生 `itinerary.json`，然後依上表順序執行。
需要 ExifTool（`$env:LOCALAPPDATA\Programs\ExifTool\`）。

## License

MIT
