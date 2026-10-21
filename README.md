# Lab06 – Puyo Puyo Placement Solver (PPS)

提交用檔案：`01_RTL/PUYO_TOP.v`、`01_RTL/PUYO_SOFT_IP.v`（目前 = `versions/v9`，重力模組已併入 `PUYO_TOP.v`）。
`versions/v0 … v9` 保留每一版的 RTL，`tools/` 是 golden model、pattern 產生器與評估腳本。

## 1. 規格重點與輸入到輸出的流程
1. **輸入**：`in_valid` 連續 72 cycle，`in_cell` 由左上角開始逐列送（flat index 0 = 左上，71 = 右下）；`in_puyo_a/b` 只在第 1 個 cycle 有效。
2. **22 個 candidate**：0–5 A 在上（欄 = ID）、6–11 B 在上（欄 = ID-6）、12–16 A 左 B 右（左欄 = ID-12）、17–21 B 左 A 右（左欄 = ID-17）。直放需該欄空格 ≥ 2，橫放兩欄都要有空格，否則不合法。
3. **放置 + 重力**：每顆 Puyo 落到該欄最低空格（橫放兩顆各自落下）。
4. **連鎖**：`PUYO_SOFT_IP` 找出本輪所有 ≥4 連通的格子 → 清除 → 重力 → 再丟回 Soft IP，直到沒有可消除；每個有消除的輪次 chain +1，累計消除數。
5. **選最佳**：chain 大 → 總消除數大 → candidate ID 小。沒有任何消除的 candidate 一律是 (0, 0)。
6. **輸出**：`out_valid` 高 1 cycle，同時給 `out_best_candidate / out_chain / out_erased`。

小例子（A=1, B=2；最底列在最下面）：
```
2.....   row2
21....   row1
1132..   row0
```
cand 0 / 6 / 12 都湊不到 4 顆 → (0, 0)；cand 7（B 在上放第 1 欄）：A=1 落在 col1 最上面，與 col1 的 1,1 及 col0 底部的 1 連成 4 顆 → 消 4 顆，掉落後 2 只剩 3 顆相連 → (chain 1, erased 4)；cand 17 也是 (1, 4)，並列取較小 ID → 輸出 `7, 1, 4`。

## 2. 優化歷程（面積 × 週期 × 平均 latency）
同一套評估流程（`tools/eval.sh`）：Verilator 跑 605 筆 TOP + 2400 筆 Soft IP 向量（全版本皆 PASS），yosys + abc 以自訂的「NAND2 等效面積 / 粗略延遲」小型元件庫做**相對**估算（flop 以 6 個 NAND2 計、T = 組合最長路徑 + 0.3ns）。**絕對數字不等於 DC 結果，只用來比較版本。**

| 版本 | 面積 | T (ns) | 平均 latency | 分數 (×10³) | 這一版做了什麼 |
|---|---|---|---|---|---|
| v0 | 31.3k | 5.65 | 29.19 | 5167 | 基準：單級迴圈，Soft IP 枚舉 19 種 tetromino，每輪都做 popcount |
| v1 | 15.5k | 2.18 | 28.24 | 957 | Soft IP 共用「相鄰格比較」；移位暫存器載入並順便記高度；非法 candidate 不花 cycle；erase 計數移出迴圈 |
| v2 | 17.5k | 1.31 | 29.64 | 681 | **2 級 pipeline（A: Soft IP，B: 重力/累計/比較），2 個 candidate 交錯**，兩級每 cycle 都有事做；重力改前綴 popcount 樹 |
| v3 | 18.6k | 1.37 | **17.83** | 455 | **探針過濾**（見 3.）+ A==B 時剔除重複 candidate + 預設答案 = 最小合法 ID |
| v4 | 16.5k | 1.43 | 17.83 | 422 | 盤面改存「2-bit 顏色 + 每欄高度」；累計消除數改成「剩餘 Puyo 數 = Σ高度」 |
| v5 | 15.2k | 1.41 | 17.83 | 383 | Soft IP 改成**度數判斷**（不再枚舉形狀）；待處理候選用暫存向量 + one-hot 直接產生放置描述 |
| v6 | 14.1k | 1.42 | 17.83 | 358 | 重力改**階層式壓縮**（每 4 格一組，再依 one-hot 計數串接） |
| v7 | 14.4k | 1.40 | 17.83 | 360 | 無效格不算「保留」→ 新高度由 one-hot 卷積編碼，免減法器（先降關鍵路徑；面積略增） |
| v8 | 13.8k | 1.36 | 17.83 | 334 | Soft IP 2-bit 比較 + 共用非空旗標；重力用產生器寫成 one-hot 樹狀合併（GS=2） |
| **v9** | **13.4k** | **1.32** | **17.83** | **316** | Soft IP 以 if-generate 重寫（無越界索引）；資料暫存器不重置、重力併入 TOP（只提交兩個檔案） |

**5167k → 316k（16.4 倍）**。latency 29.2 → 17.8、T 5.65 → 1.32、面積 31.3k → 13.4k。

## 3. 用到的規律
- **探針過濾（最大的 latency 收益）**：所有 candidate 的新 Puyo 只會落在每欄「最低空格」與「其上一格」共 12 個固定落點。把多個互不相鄰的 candidate 的棋子放在**同一塊板子**上、只用 Soft IP 跑一次，就能知道哪些 candidate「可能」消除（多放棋子只會讓群組變大，所以只會有誤報、不會漏報）。A≠B 時 4 塊探針（lo/hi × 相鄰欄 A、B 交替的兩種相位）覆蓋 22 個 candidate，A==B 時 5 塊。沒被標記的合法 candidate 一定是 (0,0)，答案預設為最小合法 ID。探針與 candidate 共用同一個 Soft IP、同一條 pipeline，額外面積幾乎為零。
- **A==B**：「B 在上」與「A 在上」、「B 在左」與「A 在左」盤面完全相同，直接剔除（ID 較小者必勝）。
- **重力穩定的盤面**：空格只會在每欄頂端之上 → 只存 2-bit 顏色 + 4-bit 高度（flop 934 → 731），重力選擇網路也變 2-bit 寬。
- **剩餘 Puyo 數取代消除數**：每個 candidate 起始總數相同（盤面 + 2），所以「消除最多」等價「剩餘最少」，每個 context 本來就帶著高度，省掉所有累計器；`out_erased = 起始總數 − 剩餘`。
- **小於 4 的連通塊只有單格、雙格、三格直線/L 形**，可以只用同色鄰居數（及鄰居的鄰居數）判定，不必枚舉 19 種 tetromino（Soft IP 面積 10.5k → ~3.3k）。
- **載入用移位暫存器**（無寫入位址解碼）；欄位環狀計數器、高度計數器在串流時順便完成。
- **2 級 pipeline + 2 個 context 交錯**：A、B 兩級每個 cycle 都有一個 context，所有板子暫存器每 cycle 都在更新；Soft IP、重力各只有一份，由探針與所有 candidate 共用。

## 4. 驗證
- `./run_all.sh`：重新產生 pattern，跑 Soft IP（(3,4)(4,6)(5,8)(6,10)(6,12)(8,12) 各 400 筆）與 TOP（605 筆，含手工邊界案例與爬山法造出的長連鎖盤面，最長 chain 11）。
- `tools/stress.sh versions/v9 1500`：6 種分佈（mix / 近滿 / 近空 / 兩三色 / A==B / 長連鎖）各 1500 筆，含「out_valid 後立刻送下一筆」的緊縮間隔 → 全 PASS，最大 latency 82（規格上限 200）。
- 4-state 模擬（iverilog，資料暫存器不重置、無效時 `in_cell`/`in_puyo_*` 為 X）：150 筆 PASS。
- Golden（`tools/golden.py`）與 RTL 完全獨立：BFS 連通 + 逐欄重力 + 22 個 candidate 逐一評估。
- RTL 檢查：無禁用字（error/congratulation/latch/fail）、無顯示/列印、無非 ASCII、yosys 檢查無 latch、`iverilog -g2001` 嚴格編譯通過。

## 5. 尚未做 / 風險
- **沒有 Design Compiler、沒有 gate-level 模擬**：`02_SYN/syn.tcl` 只是依規格寫的草稿，未執行；面積/週期請以 DC 實跑為準，時脈週期需依 DC 結果再微調。
- `PUYO_SOFT_IP` 多了一個參數 `COUNT_EN`（預設 1，行為與規格相同）；TOP 以 `COUNT_EN=0` 實例化，因為 TOP 用不到 `erase_num`，避免合成出無用的 popcount。若助教要求 TOP 內的 Soft IP 也要使用預設參數，改成 `COUNT_EN=1` 即可（面積會增加）。
- 這個設計依賴規格保證：輸入盤面重力穩定且沒有可消除群組、A/B 顏色為 1..4、至少有一個合法 candidate。
- 估算工具的限制：abc 對加法/比較器的映射偏保守，真實 DC 結果的相對關係可能略有不同。
