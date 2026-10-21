# Lab06 – Puyo Puyo Placement Solver (PPS)

## 從輸入到輸出的流程
1. **輸入**：`in_valid` 連續 72 cycle，`in_cell` 依序送 top-left → 右 → 下一列（flat index 0..71，index 0 = 第 11 列最左）。`in_puyo_a/b` 只在第 1 個 cycle 有效。
2. **22 個 candidate**：0–5 A 在上(col=ID)、6–11 B 在上(col=ID-6)、12–16 A 左 B 右(左欄=ID-12)、17–21 B 左 A 右(左欄=ID-17)。直放需該欄空格≥2，橫放兩欄都需有空格；不合法就跳過。
3. **放置+重力**：每個 Puyo 落到該欄最低空格（橫放兩顆各自落下，可在不同列）。
4. **連鎖評估**（每 cycle 一輪）：`PUYO_SOFT_IP(board)` → `erase_mask/erase_num`；若 `erase_num=0` 結束；否則 chain+1、erased+=num、清除 mask、重力、再丟回 Soft IP。
5. **選最佳**：`max(chain)` → `max(erased)` → `min(ID)`。沒有消除者 chain=erased=0。
6. **輸出**：處理完 22 個後 `out_valid` 拉高 1 cycle，同時給 `out_best_candidate / out_chain / out_erased`。

### 小例子（A=1, B=2）
```
......   row3
......   row2   (col0: 1,2,2 由下往上)
2.....   row2
21....   row1
1132..   row0
```
- cand 0/6/12：都不會連成 4 → (chain 0, erased 0)
- cand 7（B 在上放 col1）：A=1 落 col1 row2 → col1 的 1,1,1 + col0 row0 的 1 = 4 連通，消 4 個；掉落後 2 只有 3 顆相連，不再連鎖 → (1, 4)
- cand 17（B 左 A 右）：結果同為 (1, 4)
- 最佳：chain=1, erased=4 並列 → 取最小 ID = **7**，輸出 `out_best_candidate=7, out_chain=1, out_erased=4`。

## Soft IP 的做法
≥4 連通 ⇔ 該格屬於某個「同色、非空的 tetromino」(連通集合必含經過每格的連通 4 子集)。
generate 對每個 anchor × 19 種 tetromino 方向做比對並 OR 成 `erase_mask`，`erase_num` 為 popcount。純組合、可參數化、無答案 LUT。

## 驗證
`./run_all.sh`（需 iverilog、python3）：
- `tools/golden.py`：獨立的 Python golden（BFS 連通 + 重力 + 22 candidate 評估）
- `tools/gen_pattern.py`：產生 605 組 TOP（含手工邊界案例、爬山法造出的 chain 最高 11 的盤面）與 6 組參數 × 400 筆 Soft IP 向量（含浮空盤面）
- 結果：Soft IP (3,4)(4,6)(5,8)(6,10)(6,12)(8,12) 全 PASS；TOP 605 筆全 PASS，最大 latency 72 cycles（上限 200）

尚未做：DC synthesis / gate-level（需 TA 環境與 syn.tcl，本環境沒有）。
