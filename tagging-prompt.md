# Claude 照片打標指示（範本）

> 這一步不是腳本：開一個 Claude Code session（或 headless `claude -p`），把本指示
> 連同縮圖目錄交給它。Claude 用 Read 工具直接「看」縮圖，逐批輸出 JSONL 標籤。

## 指示

1. 讀 `C:\path\to\staging\thumbs\` 下的縮圖（原檔已由 `thumbnailer.ps1` 縮成 1024px）。
2. 每張輸出一行 JSON 到 `C:\path\to\staging\tags\batchN.jsonl`（每批約 100–200 張，
   分批可續作、可平行）：

```json
{"file":"20260423_113059.jpg","scene":["餐食"],"landmark":null,"people":"無人"}
```

- `scene`：場景類別陣列，從固定清單選（例：地標建築｜自然風景｜餐食｜街景｜室內｜交通｜人物合影）
- `landmark`：可辨識的地標名稱，認不出填 `null`（寧缺勿錯——之後靠時間內插補）
- `people`：`無人`／`家人`／`合影` 等（依你的分類需求自訂）

3. 不確定的欄位保守處理：landmark 只在高把握時填；scene 至少給一個。

## 下游如何使用

- `landmark-map.ps1`：以高把握 landmark 為「錨點」，其餘照片依時間內插
  （距最近錨點 ≤25 分鐘歸入該景點）產生 file→景點映射。
- `landmark-seq.ps1`：景點內 gap>60 分鐘切段，依起始時間編成 `NN 名稱 HH時` 資料夾。
- `phase25-execute.ps1`：連拍（同秒）只留最大檔、其餘進 `連拍其餘\MM-DD\`；
  標籤經 ExifTool 寫入 XMP-dc:Subject（可被相簿軟體搜尋）。
