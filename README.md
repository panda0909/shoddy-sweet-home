# 裝潢蟑螂 | Shoddy Sweet Home

Web：https://panda0909.github.io/shoddy-sweet-home/

## Web 發布

使用 Godot **4.7.2** 與相同版本 Web 匯出模板。推送 `main` 後，GitHub Actions 會匯入資產、跑通行和互動測試、匯出並部署 GitHub Pages。
儲存庫 Pages 的來源使用 **GitHub Actions**。不將 `build/` 或 `.godot/` 提交至 Git。

本機匯出：`godot --headless --path . --export-release Web build/web/index.html`（先建立輸出資料夾）。
透過 HTTP 伺服器開啟匯出檔，不可直接雙擊 HTML。使用單執行緒 Compatibility Web 匯出，不依賴跨來源隔離標頭。
首次下載約 160 MB，建議使用桌面瀏覽器與鍵盤滑鼠；尚未完成行動裝置操作適配。素材授權見 [CREDITS.txt](CREDITS.txt)。

Godot 4 第一人稱搞笑驗屋遊戲原型。

## 目前已完成

- 程序生成的四房間 3D 公寓：客廳、廚房、臥室、浴室
- 第一人稱 WASD 移動與滑鼠視角
- 手電筒、水平儀、空鼓槌、驗電筆四種工具
- 14 個裝潢問題池，每局保證四個房間各抽兩個，再補足到 10 個
- 需要指定工具才能確認的問題
- 3 分鐘倒數、進度條、誤用工具提示
- 發現問題後的搞笑吐槽與 Label3D 標記
- 驗屋報告、分數、評級與重新開始
- 寫實浴室、廚房與客廳 glTF 資產替換，含 PBR 貼圖、玻璃、金屬與高細節家具
- 已完成的可通行入口：大門、客廳、臥室、兩側內門都具備門洞、門框、門扇碰撞與 90° 開關動畫
- 臥室細節化：床架／床頭板／被褥／雙枕、床頭櫃與燈具、衣櫃門把、書櫃、書籍、書桌工作區、椅子、窗簾、掛畫、地毯與植栽

## 操作

| 操作 | 按鍵 |
| --- | --- |
| 移動 | WASD |
| 查看 | 滑鼠 |
| 檢查問題／開關門 | E 或滑鼠左鍵 |
| 切換工具 | 1-4 |
| 釋放滑鼠 | ESC |
| 重新驗屋 | R（結算後） |

## 執行

使用 Godot 4 開啟此資料夾，執行 `main.tscn` 或直接按 Play Project。

場景的門、碰撞、UI、問題與程序化家具都由 `main.gd` 在執行時建立，方便快速調整玩法與增加問題。

浴室、廚房與客廳已改用 `assets/models/` 下的真實資產；授權與來源記錄在 `assets/ASSET_LICENSES.md`。臥室以拆件式程序化家具完成完整擺設，後續可在不改變碰撞與門洞規格下直接換入新的 glTF 資產。
