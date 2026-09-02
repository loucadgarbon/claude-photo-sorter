# Claude 行程檔產生指示（範本）

> 打標（`tagging-prompt.md`）完成後，開一個 Claude session 依本指示產生
> `itinerary.json`——腳本吃的行程資料全部來自這個檔，程式碼本身不含任何行程。

## 指示

讀 `tags/batch*.jsonl` 的全部標籤與照片檔名時間戳（`YYYYMMDD_HHMMSS`），產生
`C:\path\to\staging\itinerary.json`（UTF-8，格式見 `itinerary.example.json`）：

1. **`dayNames`**：每個出現的日期一筆，`"MMDD": "MM-DD 摘要"`。摘要 = 該日
   出現次數最多的 2–3 個地標（依時間順序、以 `·` 連接）；無地標的日子用
   行程性質（抵達／歸途／移動日）。
2. **`landmarkAliases`**：掃描所有 landmark 值，把指涉同一地點的變體
   （語言差異、車站/纜車/展望台等子設施、錯字）映射到統一名稱；車站類可
   映射到籠統類（如「移動與街景」）。
3. **`albumTag`**：整趟旅行的相簿標籤（寫入每張照片的 XMP Subject）。
4. **`skipDays`**：照片極少（<5 張）不值得建景點夾的日子，`"MM-DD"` 格式。

規則：統一名稱以你在 dayNames 使用的寫法為準；不確定是否同一地點時不要合併。
