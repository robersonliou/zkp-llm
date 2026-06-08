# Person B — Slides 9–16 逐字稿（Core Papers）

---

## 前置概念：你需要先懂的三個東西

**1. 什麼是電路 (Circuit)**
ZKP 的核心是把「計算」表示成「數學方程式的集合」，這個集合叫電路。每個加法/乘法都是一個約束，prover 必須提交滿足所有約束的 witness（中間值）。

**2. 什麼是 PIOP (Polynomial Interactive Oracle Proof)**
比電路更高階的框架。把整個計算編碼成多項式，prover 把多項式「承諾」(commit) 給 verifier，verifier 在隨機點查詢，靠 Schwartz-Zippel 定理（兩個不同多項式在隨機點幾乎不可能相等）來確認正確性。

**3. 什麼是 Sumcheck**
一種 PIOP 協議，用來證明「一個多變數多項式在某個超立方體上所有點的和等於聲稱的值」。Matrix multiplication 可以轉化成 sumcheck，這就是為什麼 zkAttn 用它來證矩陣乘法。

---

## Slide 9 — zkVM Landscape

### 知識背景

**zkVM（Zero-Knowledge Virtual Machine）** 是「把整台虛擬機器的執行過程包成一個 ZK proof」的技術。

傳統方式：你要證明某個計算，就要手工把它寫成電路（電路工程師的工作，非常難）。  
zkVM 方式：你用正常語言（Rust）寫程式，zkVM 自動產生 proof，開發者幾乎不用動。

**RISC Zero** 的架構是：
- 執行 RISC-V 指令集（一種精簡指令集架構，Linux 也支援）
- 每條指令的執行都被 STARK 電路約束
- 最後用 **Groth16 wrapping**：把「驗證那份 STARK 的計算本身」再包成一個 200 bytes 的 SNARK
- 結果：鏈上驗證只需要 ~200k gas，非常便宜

**Groth16 wrapper 的意義**：STARK 本身 proof size ~100KB，放到鏈上很貴。Groth16 的特性是 proof 極小（~200 bytes），但需要 trusted setup。所以 RISC Zero 用 STARK 做主要計算（不需 trusted setup），再用 Groth16 壓縮最終 proof 送上鏈。兩者優點都有。

**SP1（Succinct Labs）**：也是 RISC-V STARK，2025 年 benchmark 顯示 proving speed 業界最快，但 Cartesi 選 RISC Zero 是因為原生整合。

**Jolt（a16z）**：完全用 lookup argument 架構的 zkVM，理論上很優雅，每個 RISC-V 指令都是查表而非電路約束。

### 逐字稿

> 好，前面介紹完了 ZKP 的理論基礎，現在我們來看目前業界有哪些主流的 zkVM——也就是零知識虛擬機器。
>
> 傳統的 ZKP 需要手工把計算寫成電路，非常費工。zkVM 解決了這個問題：你就用 Rust 正常寫程式，zkVM 自動幫你生成 proof，開發體驗跟一般寫程式沒有差。
>
> 目前主流有三個：**RISC Zero**、**SP1**、還有 **Jolt**。
>
> 其中我們這個 project 選擇 RISC Zero，是因為 Cartesi v0.20.0 原生整合了它。
>
> RISC Zero 有一個很聰明的設計叫 **Groth16 wrapper**。它自己的 STARK proof 大概 100 KB，放到鏈上很貴；所以它再用 Groth16 把「驗證那個 STARK 的計算」包成一個只有 200 bytes 的小 proof。這樣鏈上驗證只要 20 萬 gas，非常便宜。
>
> 這就是 STARK 透明 setup 加上 SNARK 緊湊 proof 的最佳組合。
>
> 不過 zkVM 有個本質上的 trade-off：開發體驗好，但 proof size 和 proving time 比客製電路差。這就是為什麼我們接下來要介紹的 zkLLM、zkRAG 選擇了專為特定任務設計的客製方案。

---

## Slide 10 — Folding Schemes

### 知識背景

**問題情境**：假設 Cartesi 機器跑了 100 萬個 machine cycle，每個 cycle 都要出一份 proof，那你就有 100 萬份 proof，超大。能不能壓縮？

**Folding 的核心想法**：
給你兩份 R1CS instance（就是兩份電路的滿足解），你可以用**隨機線性組合**把它們「折疊」成一份：

```
x' = x1 + r * x2
w' = w1 + r * w2
```

只要 `r` 是隨機的，如果兩份原來都合法，折疊後的也幾乎確定合法（soundness）。遞迴下去，N 份可以折成 1 份，最後只出一份 proof。

**Nova（Microsoft Research, 2021）**：第一個實用的 folding scheme。概念是 IVC（Incrementally Verifiable Computation）：跑完第 t 步時，你有一份 proof 說「前 t 步都正確」，第 t+1 步只需要驗證「步驟 t+1 本身正確」然後 fold 進去。

**HyperNova（ePrint 2023/573）**：把 Nova 的 R1CS 換成更通用的 CCS（Customizable Constraint Systems），理論上最優。

**Sonobe**：PSE（Privacy & Scaling Explorations，Ethereum Foundation 旗下）的開源 library，實作了多種 folding scheme，是目前實作首選。

### 逐字稿

> 接著是 Folding Schemes，這個概念目前在我們的 demo 裡還沒有實作，但它是未來最重要的優化方向，所以值得介紹。
>
> 想像 Cartesi 機器執行一個 LLM inference，需要跑幾十萬個 machine cycle。如果每個 cycle 都要單獨出一份 proof，那 proof 的數量跟體積會讓整個系統完全不實用。
>
> Folding 的想法是：把兩份 proof **折疊**成一份。數學上，兩個滿足電路約束的解，可以用隨機係數做線性組合，得到的結果幾乎確定也滿足同樣的約束。遞迴折疊 N 次，N 份 proof 就壓成 1 份。
>
> 這個技術最重要的代表作是微軟研究院 2021 年的 **Nova**，它讓所謂的 IVC——遞增可驗計算——變得實用。之後的 **HyperNova** 進一步把框架推廣到更通用的約束系統。
>
> 在我們的架構裡，未來的目標是用 folding 把 N 份 Cartesi step proof 壓縮成一份，大幅分攤 proving cost。

---

## Slide 11 — zkLLM: Motivation & tlookup

### 知識背景

**核心問題**：LLM 推論裡有幾個「非算術運算」：
- **Softmax**：`softmax(xi) = exp(xi) / sum(exp(xj))`，有指數函數
- **GELU**：`x * Φ(x)`，有高斯累積分布函數
- **SwiGLU**：現代 LLM（LLaMA）用的激活函數，也是非多項式

ZKP 電路本質上只能做加法和乘法。要在電路裡計算 `exp(x)`，要用多項式去逼近它，電路大小會爆炸。

**Lookup argument 的解法**：
預先算好一張查表 `T = {(x, exp(x))}`，prover 只需要「證明我查的每個 `(x, exp(x))` pair 都在這張表裡」，而不是重新計算 exp(x)。

**Shift invariance trick**：
```
softmax(s_ij) = softmax(s_ij - max_j(s_ij))
```
這個數學性質讓我們可以先減掉 row 的最大值。減完之後，所有值都 ≤ 0，bounded 在一個小範圍，查表的 table size 就很小。

**Base-b 分解**：
```
x = sum(dk * b^k)
exp(x) = product(exp(dk * b^k))
```
把 x 拆成多進制的 digit，每個 digit 的範圍只有 [0, b)，對應一張小表。整個 exp(x) 只需要查幾張小表再相乘。

**tlookup（tensorized lookup）**：
普通 lookup 是一個一個 element 查表。tlookup 把整個 attention head（一個 tensor）一次 batch 進同一個 PIOP，讓所有 head 共用一張表，大幅減少 proof 大小。

### 逐字稿

> 現在進入核心論文的部分。第一篇是 **zkLLM**，它解決的是「怎麼對整個 LLM forward pass 出 ZK proof」。
>
> 問題的根源在於：LLM 裡有幾個關鍵運算——Softmax、GELU、SwiGLU——它們都含有指數函數，不是多項式。但 ZKP 電路本質上只能做加法和乘法，要直接在電路裡表達指數，電路大小會爆炸，完全不實用。
>
> zkLLM 的解法是 **lookup argument**：預先建一張查表，把 x 對應到 exp(x) 都算好，prover 只需要「證明我的計算都從這張表查來的」，不用重新算指數。
>
> 但 LLM 的數值範圍很大，查表不可能把所有 x 都列出來。zkLLM 用了兩個技巧壓縮表的大小。
>
> 第一個是 **shift invariance**：softmax 減掉 row 最大值之後，結果不變，但所有值都被限制在一個小範圍。
>
> 第二個是 **base-b 分解**：把 x 拆成多進制的 digit，exp(x) 就拆成幾個小數字的指數相乘，每個 digit 查一張很小的表。
>
> 最後 **tlookup** 把整個 attention head 一次 batch 進去，共用同一張表。
>
> 實測結果：LLaMA 13B 的完整 forward pass，proving time 不到 15 分鐘，proof size 不到 200 KB。這是目前業界第一個在 production-scale LLM 上實用的 ZK proof。

---

## Slide 12 — zkAttn 5-Step Flow

### 知識背景

**Attention 的計算公式**：
```
Attention(Q, K, V) = softmax(QK^T / sqrt(dk)) * V
```

對 ZKP 來說，這裡有兩種運算：
1. **矩陣乘法** QK^T 和 softmax(·)·V：用 sumcheck 協議處理（sumcheck 可以高效證明 inner product / matrix multiply）
2. **Softmax**：就是上一頁的 tlookup 技術

所以 5 步驟是把兩種不同的 ZKP 工具按順序組合起來：
- 步驟 1, 5 → sumcheck（矩陣乘法）
- 步驟 2, 3, 4 → shift + decompose + tlookup（softmax）

### 逐字稿

> 這張 slide 把上一頁的技術組合起來，讓大家看 attention 的完整 proof 流程。
>
> Attention 的計算有兩種截然不同的子運算：矩陣乘法，和 Softmax。zkAttn 針對每種分別用最合適的 ZKP 工具。
>
> 第一步和第五步是矩陣乘法，用 **sumcheck** 協議——這是一個非常高效的多項式協議，專門拿來處理 inner product 和矩陣乘法。
>
> 中間的第二到第四步就是上一頁說的 Softmax 處理：先減掉 row 最大值，再做 base-b 分解，最後 tlookup 查表。
>
> 關鍵的設計是：這 5 步的每一步，要嘛是 sumcheck-friendly，要嘛是 lookup-friendly，沒有一步需要「暴力硬塞進電路」。這就是為什麼整個 attention 能在合理時間內被 prove。
>
> 所有 attention head 共用同一張 tlookup 表，所以整個 transformer layer 的 proving 成本是可以控制的。

---

## Slide 13 — zkRAG: Motivation

### 知識背景

**RAG（Retrieval-Augmented Generation）** 是把向量資料庫查詢跟 LLM 結合：先從文件庫找最相似的段落，再把它餵給 LLM 生成答案。

**HNSW（Hierarchical Navigable Small World）** 是目前最主流的 Approximate Nearest Neighbor（ANN）搜尋演算法：
- 建立多層圖，上層節點少、連接遠，下層節點多、連接近
- 搜尋時從最頂層的節點 greedy 往下走，每層找局部最近鄰
- 最後在最底層找到 approximate nearest neighbor

為什麼 HNSW 很難在 ZKP 電路裡表達：

| 問題 | 原因 |
|------|------|
| Priority queue | 每次 push/pop 都是資料相依的操作，電路大小隨資料變 |
| Visited bitmap | Sparse 讀寫，電路無法有效表達 |
| Random graph traversal | 走哪條邊取決於資料，電路必須包含所有可能路徑 |
| Float distance | 浮點數在有限體上很難做 |

**zkRAG** 的思路是：不要試著在電路裡「執行 HNSW」，而是讓 prover 先「跑完 HNSW 得到 trace（搜尋路徑）」，再設計四個 PIOP 來「驗證這個 trace 是合法的 HNSW 搜尋結果」。Prove the trace, not re-execute.

### 逐字稿

> 第二篇核心論文是 **zkRAG**，於 2026 年 4 月發布，是史上第一個專為 HNSW 設計的 PIOP。
>
> 要理解它，先要知道 HNSW——現代向量資料庫（像 Chroma、Qdrant、Weaviate）全部都用它做 ANN 搜尋。它建立一個多層圖，從頂層貪婪地往下搜尋，效率極高，但也正因為「貪婪且資料相依」，它在 ZKP 電路裡非常難表達。
>
> 難點有四個：優先佇列的 push/pop、visited bitmap 的 sparse 讀寫、multi-level 圖的隨機跳轉、還有浮點數的距離計算。每一個都是傳統電路設計的噩夢。
>
> 所以如果你用通用 zkVM 暴力證 1M 筆向量的 HNSW 搜尋，需要幾個小時。
>
> zkRAG 的關鍵設計思路是：**不要在電路裡重新執行 HNSW，而是驗證搜尋的 trace 是合法的**。Prover 先正常跑 HNSW 得到搜尋路徑，再設計 PIOP 來驗證這條路徑滿足 HNSW 的所有規則。
>
> 結果：proving time 從幾個小時縮到 50 秒，大約 1000 倍加速。

---

## Slide 14 — zkRAG PIOP Flow

### 知識背景

zkRAG 把 HNSW 搜尋驗證拆成四個子問題，各自設計 PIOP：

1. **Priority-Queue Checker**：證明 heap 操作是合法的。用單調排序：每次 pop 出來的元素必須是當前最小（或最大），這可以轉化成 ordering constraint，用 sumcheck 驗證。

2. **Membership Selector**：證明 visited bitmap 的讀寫是正確的。哪些節點被 visit 過、哪些沒有。用 lookup argument：正確的 bitmap 狀態是一張表，prover 證明每次存取都在這張表裡。

3. **Hybrid Lookup**：證明 neighbor list 的存取是合法的（HNSW 圖的邊）。用 lookup 查 HNSW 圖的鄰居表。

4. **Distance Check**：證明每次計算的距離（L2 或 cosine）是正確的。用 sumcheck 來驗證 inner product。

四個 PIOP 都收斂到同一個 **batched sumcheck**，合出一個 SNARG（Succinct Non-interactive ARGument）。

Verifier complexity：O(log T + log |V|)，T = 搜尋 trace 長度，|V| = 圖的節點數。

### 逐字稿

> 這張 slide 展示 zkRAG 的架構細節。
>
> 我們說 zkRAG 驗證的是搜尋 trace，但這個 trace 裡包含四種不同類型的操作，每種都需要不同的 PIOP 來處理。
>
> Prover 先把整個搜尋 trace 提交成多項式承諾。然後四個 PIOP 分頭驗證：**Priority-Queue Checker** 驗證 heap 操作的順序是合法的；**Membership Selector** 驗證哪些節點被 visit 過；**Hybrid Lookup** 驗證從圖裡查的鄰居是真實存在的邊；**Distance Check** 驗證每次算的距離是正確的。
>
> 四個 PIOP 全部匯入同一個 batched sumcheck，最後出一份統一的 ZK proof。
>
> Verifier 的複雜度是 O(log T + log |V|)，幾乎是理論最優，驗證速度極快。

---

## Slide 15 — EZKL Pipeline

### 知識背景

**ONNX（Open Neural Network Exchange）** 是各大深度學習框架共同支援的模型交換格式。PyTorch、TensorFlow 等都可以匯出 ONNX。

**Halo2** 是 Zcash 開發的 SNARK 框架，特色是：
- 不需要每個電路都做 trusted setup（用 universal SRS）
- 原生支援 lookup argument
- 以 Rust 實作，效能好

**KZG polynomial commitment**：把一個多項式壓縮成一個 group element（commitment），可以之後在任意點開啟（open）並驗證。需要 SRS（Structured Reference String）——一次性的 trusted setup，之後可以重複使用。`k=15` 表示電路最多 2^15 = 32768 行。

**EZKL 的工作流程**：
1. `gen_settings`：分析 ONNX 模型結構，決定需要什麼精度（scale）
2. `calibrate`：用一批 representative input 校正數值範圍，決定 fixed-point precision
3. `compile_circuit`：把 ONNX 的每個 op 轉成 Halo2 約束或 lookup 表
4. `setup`：用 KZG SRS 產生 proving key（pk，133 MB）和 verification key（vk，66 KB）
5. `gen_witness`：跑 forward pass，收集所有中間值
6. `prove`：用 pk 和 witness 生成 proof（~82 KB）
7. `verify`：用 vk 驗證 proof

關鍵：**只有 vk（66 KB）需要給 verifier（或放上鏈）**，pk 是 prover 自己用的。

### 逐字稿

> 第三個工具是 **EZKL**，它是最接近工程實作的一層。
>
> EZKL 做的事情是：把任意 ONNX 格式的機器學習模型，自動編譯成 Halo2 ZK 電路，然後你就可以對這個模型的推論出 ZK proof。
>
> 整個流程有 7 步。前面的 gen_settings 和 calibrate 是分析模型，決定要用多少精度來表示浮點數——因為 ZKP 電路是在有限體上運算，浮點數需要轉成定點數。compile_circuit 把 ONNX 的每個操作轉成 Halo2 約束，非算術的操作（像 ReLU）走 lookup argument，跟 zkLLM 的 tlookup 是同一家族的技術。
>
> setup 這步產生兩個 key：proving key 很大（133 MB），是 prover 用來生成 proof 的；verification key 很小（66 KB），是 verifier 用的，可以部署到鏈上。
>
> 最後 prove 生成一份 82 KB 的 Halo2 proof，verify 驗證它。
>
> 這整個工具鏈就是我們 **Demo A** 的核心，我們用它證明了一個 384 到 64 維的 embedding layer。

---

## Slide 16 — Benchmark Comparison

### 逐字稿

> 最後這張 slide 把三篇論文加上 RISC0 zkVM 放在同一張表裡比較，讓大家清楚每個工具適合的位置。
>
> zkLLM 負責最重的 LLM forward pass，13B 參數不到 15 分鐘；zkRAG 負責向量搜尋，50 秒；EZKL 負責 embedding 等 ML 運算，幾十秒；RISC0 負責單步驗算，秒級。
>
> 這張表說明了一個核心設計原則：**不同 pipeline 層用不同的專門 backend**。如果你用通用 zkVM 暴力證整個 RAG pipeline，光是 HNSW 搜尋就需要幾個小時——根本不可能 production 用。
>
> 正確做法是：每層用最適合的工具，各自出 proof，最後由 Cartesi v0.20.0 的 Solidity verifier 統一驗證。
>
> 這也是我們整個 project 的核心設計哲學，後面 Person C 會說明怎麼把它們串起來。

---

## 論文連結

| 論文 | 連結 | 備註 |
|------|------|------|
| **zkLLM** — Zero Knowledge Proofs for LLM Inference | https://arxiv.org/abs/2404.16109 | 建議閱讀 §1 (intro) + §3 (tlookup) |
| **Nova** — Recursive ZK Arguments from Folding Schemes | https://eprint.iacr.org/2021/370 | Microsoft Research |
| **HyperNova** — Generalized Folding Schemes | https://eprint.iacr.org/2023/573 | 閱讀 Abstract 即可 |
| **Plookup** — lookup argument 始祖 | https://eprint.iacr.org/2020/315 | 理解 tlookup 的前置 |
| **EZKL 文件** | https://docs.ezkl.xyz | 最實用 |
| **EZKL GitHub** | https://github.com/zkonduit/ezkl | |
| **RISC Zero GitHub** | https://github.com/risc0/risc0 | |
| **Sonobe** (folding library) | https://github.com/privacy-scaling-explorations/sonobe | |
| **Halo2 book** | https://zcash.github.io/halo2 | 理解 EZKL 電路設計 |
| **zkRAG** | 搜尋 arxiv "zkRAG HNSW" | 2026-04-12 release |

---

## 快速複習單（報告前看這個）

```
Slide 9  zkVM：用正常程式語言寫，自動出 proof
         RISC Zero = STARK + Groth16 wrapper = 200B on-chain proof

Slide 10 Folding：N 份 proof 折成 1 份，Nova → HyperNova
         DEAAP 未來用它壓 Cartesi step proofs

Slide 11 zkLLM 解決 Softmax/GELU 不是多項式的問題
         3 招：lookup table + shift invariance + base-b 分解
         tlookup = 整個 attention head batch 一起查

Slide 12 zkAttn 5步：矩陣乘(sumcheck) → shift → 分解 → tlookup → 矩陣乘

Slide 13 zkRAG = 驗搜尋 trace，不重算 HNSW
         1000x 比 zkVM 快（50s vs 幾小時）

Slide 14 4個 PIOP → batched sumcheck → 一份 SNARG
         verifier: O(log T + log |V|)

Slide 15 EZKL：ONNX → Halo2 → 82KB proof
         vk(66KB) 上鏈，pk(133MB) prover 自用

Slide 16 核心結論：不同層用不同工具，不要單一 zkVM 暴力跑
```
