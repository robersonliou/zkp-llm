# Person B — Slides 9–16 逐字稿（Core Papers）

---

## 前置概念：你需要先懂的三個東西

**1. 什麼是電路 (Arithmetic Circuit)**
ZKP 的核心是把「計算」表示成「有限體上的算術方程式集合」，這個集合叫算術電路。每個加法／乘法門都是一個約束，prover 必須提交滿足所有約束的 witness（中間值）。LLM 的挑戰在於：Softmax、GELU 等激活函數完全不是多項式，沒辦法直接表達成算術電路。

**2. 什麼是 PIOP (Polynomial Interactive Oracle Proof)**
比電路更高階的框架。把整個計算編碼成多項式，prover 把多項式「承諾」(commit) 給 verifier，verifier 在隨機點查詢；靠 **Schwartz-Zippel 定理**（兩個不同的 $d$ 次多項式在 $\mathbb{F}_p$ 隨機點幾乎不可能相等）來確認正確性。現代 ZKP 的 soundness 全部建立在這個定理上。

**3. 什麼是 Sumcheck 協議**
一種 PIOP 的基本積木，用來證明「一個多變數多項式在某個超立方體上所有點的和等於聲稱的值」：
$$\sum_{x \in \{0,1\}^n} f(x) = C$$
矩陣乘法 $C = AB$ 可以改寫成 sumcheck，這就是為什麼 zkAttn 用 sumcheck 來高效證明 $QK^T$。Sumcheck 的通訊複雜度是 $O(n)$（$n$ 為變數個數），遠低於逐一驗算的 $O(2^n)$。

---

## Slide 9 — zkVM Landscape

### 知識背景

**問題的本質：通用計算的電路複雜度**

ZKP 電路要驗算一份計算，電路大小（行數）大致等於計算的指令數。一個 LLM forward pass 有幾億條運算；一次 HNSW 搜尋有幾萬次記憶體存取，每次都是 data-dependent（走哪條邊取決於輸入）。

傳統手工電路設計必須把每條可能的執行路徑都編碼進去，電路大小隨程式複雜度指數成長，這讓「直接對 LLM 寫電路」幾乎不可能。

**zkVM 的設計思路**

與其對具體程式寫電路，不如為**指令集架構（ISA）**本身寫一個「通用電路」：只要能證明「每條 RISC-V 指令的取指-解碼-執行都正確」，就能間接證明任何跑在這個指令集上的程式。這就是 zkVM 的核心想法。

**RISC Zero 的密碼學架構**

- **STARK + FRI**：執行軌跡（execution trace）展開成一個巨型矩陣，每一行是一個機器狀態；用 FRI（Fast Reed-Solomon IOP of Proximity）協議對這個矩陣做多項式承諾，驗算邏輯約束。FRI 不需要 trusted setup，安全性假設僅是碰撞抗性雜湊函數（post-quantum）。
- **Groth16 wrapping**：STARK proof 本身約 100 KB；為了縮短最終輸出，把「驗算這份 STARK 的電路」再包成一個 Groth16 SNARK（~200 bytes）。這是一個「proof of a proof verification」——遞迴 proof 組合技術的早期實踐。

**SP1（Succinct Labs）** 也是 RISC-V STARK，2025 benchmark 最快；**Jolt（a16z）** 則全面採用 lookup argument 架構，每條 RISC-V 指令都是查表而非電路約束，理論上更乾淨。

**zkVM 的本質 trade-off**：通用 ISA 電路的「電路開銷」是具體計算的 10–100 倍。這就是為什麼針對 LLM 的 zkLLM、zkRAG 選擇為特定演算法客製 PIOP，而不是把整個 pipeline 跑進 zkVM。

### 逐字稿

> 好，前面介紹完了 ZKP 的理論基礎，現在我們來看業界怎麼解決「通用計算的 ZK 證明」這個問題。
>
> 手工為每個程式寫電路是不可能的——一個 LLM forward pass 有幾億條運算，把所有可能路徑都編碼進電路，大小會爆炸。
>
> zkVM 的解法是：不寫程式的電路，而是寫**指令集架構的電路**。只要能密碼學地驗算「每一條 RISC-V 指令的執行都正確」，就能間接驗算任何跑在這個指令集上的程式。開發者只需要用 Rust 正常寫程式，剩下的由 zkVM 處理。
>
> 這裡有一個很有意思的密碼學技巧叫 **Groth16 wrapping**：zkVM 先用 STARK 做主要計算——STARK 基於 FRI 協議，不需要 trusted setup，安全假設只是雜湊碰撞抗性；接著再用 Groth16 把「驗算這份 STARK 的計算本身」包成一個 200 bytes 的小 proof。這是「proof of a proof」——遞迴 proof 組合的一種早期形式。
>
> 但 zkVM 有一個本質上的代價：通用 ISA 電路的開銷是具體計算的幾十到幾百倍。這就是為什麼接下來的 zkLLM 和 zkRAG 選擇為特定演算法量身設計 PIOP。

---

## Slide 10 — Folding Schemes

### 知識背景

**問題情境：遞增可驗計算（IVC）**

假設一個計算分成 N 步驟（step 1, 2, …, N），每步都有自己的 witness。能不能出一份 proof 說「所有 N 步都正確」，而不是出 N 份各自獨立的 proof？

這就是 **IVC（Incrementally Verifiable Computation）** 的問題。在 ZKP 的語言裡，它等價於「遞迴電路組合」：在電路裡跑一個驗算「上一份 proof 正確」的子電路。

**Folding 的密碼學核心**

設兩個 R1CS instance $(A, B, C)$：
$$A \cdot w_1 \circ B \cdot w_1 = C \cdot w_1 \quad \text{（第一份）}$$
$$A \cdot w_2 \circ B \cdot w_2 = C \cdot w_2 \quad \text{（第二份）}$$

用 verifier 給的隨機挑戰 $r \in \mathbb{F}_p$ 做**隨機線性組合**（random linear folding）：
$$w' = w_1 + r \cdot w_2$$

由 Schwartz-Zippel，只要 $r$ 夠隨機，折疊後的 $w'$ 幾乎必然同時滿足兩份約束。遞迴 N 輪，N 份 instance 折成 1 份，最後只需出一份 proof。

**Nova（Microsoft Research, 2021）**：第一個把 folding 做到實用的方案。關鍵洞見是「每一步的 verifier 電路本身足夠小，可以遞迴嵌入下一步的電路裡」，這讓 IVC 在常數大小的 circuit overhead 內實現。

**HyperNova（ePrint 2023/573）**：把 Nova 的 R1CS 推廣到 CCS（Customizable Constraint Systems），後者可以直接表達 Plonkish 電路和 AIR（Algebraic Intermediate Representation）等現代框架，理論上是最通用的折疊方案。

**Sonobe**（PSE / Ethereum Foundation）是目前最主流的開源實作，支援 Nova 和 HyperNova。

### 逐字稿

> 接著介紹 Folding Schemes，這是理論上最優雅的遞迴 proof 壓縮技術，也是目前 ZKP 研究裡最活躍的方向之一。
>
> 問題是這樣的：假設你要證明一段長計算，分成 N 步，每步都需要一份 proof。最直白的做法是出 N 份 proof，但 N 很大的時候這完全不實用。
>
> Folding 的密碼學思路很優雅：給兩份 R1CS 的解，用 verifier 給出的**隨機係數 $r$** 做線性組合——$w' = w_1 + r \cdot w_2$。由 Schwartz-Zippel 定理，只要 $r$ 夠隨機，組合後的 $w'$ 幾乎必然同時滿足兩份原始約束。遞迴折疊 N 次，N 份 proof 就壓成 1 份。
>
> **Nova** 的突破在於：每一步的驗算電路足夠小，可以「遞迴嵌入」進下一步的電路裡——這讓 IVC（遞增可驗計算）在常數 overhead 內實現，不再是理論上的概念。
>
> **HyperNova** 進一步把框架推廣到更通用的約束系統，覆蓋現代 ZKP 的所有主流電路格式。
>
> 在我們的架構裡，未來的目標是用 folding 把整個推論流程的多份 proof 壓成一份，從根本上降低驗算成本。

---

## Slide 11 — zkLLM: Motivation & tlookup

### 知識背景

**根本問題：LLM 中的「非算術運算」**

算術電路（定義在有限體 $\mathbb{F}_p$ 上）只支援加法和乘法。LLM 的激活函數：

| 函數 | 形式 | 問題 |
|------|------|------|
| Softmax | $\frac{e^{x_i}}{\sum_j e^{x_j}}$ | 含指數，非多項式 |
| GELU | $x \cdot \Phi(x)$ | 含高斯 CDF，超越函數 |
| SwiGLU | $\text{Swish}(xW_1) \cdot xW_2$ | 同上 |

若用多項式逼近 $e^x$，精確到精度 $\epsilon$ 需要 $O(\log 1/\epsilon)$ 次多項式，電路大小爆炸。

**Lookup argument 的解法（Plookup / tlookup 族）**

預先建一張查表 $T = \{(x, f(x)) \mid x \in \mathcal{D}\}$，其中 $\mathcal{D}$ 是合法輸入域。Prover 不計算 $f(x)$，而是**證明「每次用到的 $(x, y)$ pair 都在 $T$ 裡」**。

核心 PIOP（以 Plookup 為例）：
$$\sum_{i} \frac{1}{\beta + f(i)} = \sum_{t \in T} \frac{m_t}{\beta + t}$$
其中 $m_t$ 是 $t$ 在 witness 中的重複次數，$\beta$ 是 verifier 的隨機挑戰。這個 rational sum 的相等性用 sumcheck 驗算，soundness 由 $\beta$ 的隨機性保證。

**Shift invariance trick**
$$\text{softmax}(s_{ij}) = \text{softmax}(s_{ij} - \max_j s_{ij})$$
減掉 row 最大值後結果不變，但所有值都 $\leq 0$，bounded 在 $[-B, 0]$，查表 domain 大小從 $\mathbb{F}_p$（天文數字）縮到 $2B$（工程可行）。

**Base-$b$ 分解**
$$x = \sum_{k=0}^{K-1} d_k \cdot b^k, \qquad e^x = \prod_{k=0}^{K-1} e^{d_k b^k}$$
拆成 $K$ 個 digit，每個 $d_k \in [0, b)$，對應一張只有 $b$ 行的小表。$e^x$ 由 $K$ 次查表結果相乘得到，circuit overhead 只是乘法門。

**tlookup（tensorized lookup）**

普通 lookup 是一個 element 一次查。一個 attention head 有 $n \times n$ 個 attention score 都要查同一張 exp 表。tlookup 把整個 $n \times n$ tensor 一次 batch 進同一個 PIOP，所有 head 共用一份 prover 開銷——證明複雜度從 $O(n^2 \cdot L)$ 降到 $O(n^2 + L)$（$L$ = table size）。

### 逐字稿

> 現在進入核心論文。第一篇是 **zkLLM**，它直接面對「怎麼在有限體算術電路上表達 LLM」這個根本問題。
>
> 問題的核心是：算術電路只能做加法和乘法，而 LLM 裡的 Softmax、GELU、SwiGLU 都含有指數函數、高斯 CDF，這些是超越函數，沒辦法表達成有限次數的多項式。暴力用多項式逼近，精度要求越高，電路大小指數成長，完全不可行。
>
> zkLLM 的解法建立在 **lookup argument** 上：不在電路裡「算」$e^x$，而是預先建一張查表，讓 prover「證明他的每個 $(x, e^x)$ pair 都在這張表裡」。這個證明可以用一個 rational sum check 高效完成，soundness 來自 verifier 給出的隨機挑戰。
>
> 但 LLM 的數值範圍很大，怎麼讓查表的 domain 足夠小？兩個技巧：
>
> 第一，**shift invariance**：softmax 減掉 row 最大值後結果完全不變，但所有值被壓到 $[-B, 0]$ 這個小範圍。
>
> 第二，**base-$b$ 分解**：把 $x$ 拆成進制的 digit，$e^x$ 就變成幾個小數字的指數相乘，每個 digit 對應一張很小的表。
>
> 最後 **tlookup** 的創新是把整個 attention head 的所有 attention score 一次 batch 進同一個 PIOP，所有 head 共用一份表，證明複雜度大幅下降。
>
> 實測：LLaMA 13B 完整 forward pass，proving time 不到 15 分鐘，proof size 不到 200 KB。這是第一個在 production-scale LLM 上實用的 ZK proof。

---

## Slide 12 — zkAttn 5-Step Flow

### 知識背景

**Attention 的計算**
$$\text{Attention}(Q, K, V) = \text{softmax}\!\left(\frac{QK^T}{\sqrt{d_k}}\right) V$$

這裡有兩類截然不同的運算，需要兩種不同的 ZKP 工具：

| 步驟 | 運算 | ZKP 工具 |
|------|------|----------|
| $QK^T$ | 矩陣乘法（多項式） | Sumcheck |
| $\text{softmax}(\cdot)$ | 指數 + 歸一化（非多項式） | tlookup |
| $\text{softmax}(\cdot) \cdot V$ | 矩陣乘法（多項式） | Sumcheck |

**Sumcheck 對矩陣乘法的應用**

矩陣乘法 $C_{ij} = \sum_k A_{ik} B_{kj}$ 可以改寫成多線性延伸（multilinear extension）上的 sumcheck：
$$\hat{C}(x, y) = \sum_{z \in \{0,1\}^{\log n}} \hat{A}(x, z) \cdot \hat{B}(z, y)$$
Verifier 只需要在隨機點查詢 $\hat{A}$ 和 $\hat{B}$ 的值，不需要看整個矩陣，通訊複雜度 $O(n \log n)$（vs. 直接驗算的 $O(n^2)$）。

**5 步的設計邏輯**：每一步要嘛是 sumcheck-friendly（多項式運算），要嘛是 lookup-friendly（有界整數），沒有一步需要強行塞入電路。這是「為演算法量身設計 PIOP」的範本。

### 逐字稿

> 這張 slide 把 zkLLM 的兩種工具組合起來，展示完整的 attention proof 流程。
>
> Attention 的計算天然可以分成兩類：矩陣乘法，以及 Softmax。這兩類對 ZKP 的友善程度完全不同。
>
> 矩陣乘法是多項式運算，可以用 **sumcheck** 高效處理。Sumcheck 的關鍵性質是：驗算 $n \times n$ 矩陣乘法，通訊複雜度只有 $O(n \log n)$，而不是直接驗算的 $O(n^2)$。Verifier 只要在隨機點查詢多項式的值，靠 Schwartz-Zippel 定理確認正確性。
>
> Softmax 是非多項式，用上一頁說的 shift invariance + base-$b$ 分解 + tlookup 處理。
>
> 5 步的設計哲學是：**每一步都用它最適合的密碼學工具**，沒有一步是暴力硬塞進電路的。步驟 1 和步驟 5 是矩陣乘法走 sumcheck；步驟 2、3、4 是 Softmax 的三段式處理走 tlookup。
>
> 特別重要的是：所有 attention head 共用同一張 tlookup 表，所以整個 transformer layer 的 proving 成本是可以控制的，不會隨 head 數線性成長。

---

## Slide 13 — zkRAG: Motivation

### 知識背景

**HNSW 為什麼難以用電路表達**

HNSW（Hierarchical Navigable Small World）是現代向量資料庫的標準 ANN 搜尋演算法：建立多層圖，從頂層 greedy 往下走，每層找局部最近鄰。

對 ZKP 電路設計者來說，HNSW 有四個結構性難點：

| 難點 | 電路問題 |
|------|----------|
| 優先佇列（Priority Queue） | 每次 push/pop 是 data-dependent 操作，電路大小隨輸入變化 |
| Visited bitmap | Sparse random-access 記憶體讀寫，傳統電路無法高效表達 |
| Multi-level 圖的隨機跳轉 | 走哪條邊取決於距離比較結果，電路必須包含所有分支 |
| 距離計算（L2 / cosine） | 浮點數需要轉成有限體上的定點數，精度損失需要一起證明 |

**Trace verification 的思路**

zkRAG 的核心洞見：**不要在電路裡重新執行 HNSW，而是讓 prover 先執行、再設計 PIOP 來驗證執行 trace 的合法性**。

類比：不需要在電路裡實作一個排序算法，只需要「驗證輸出是排序的且是輸入的排列」。這個驗算的 PIOP 遠比電路裡跑排序算法便宜。

這個設計哲學（prove the trace, not re-execute）是 zkRAG 對 PIOP 設計方法論的重要貢獻。

### 逐字稿

> 第二篇核心論文是 **zkRAG**，2026 年 4 月發布，是第一個專為 HNSW 向量搜尋設計的 ZK proof 系統。
>
> 要理解它的挑戰，先看 HNSW 的結構。HNSW 是一個 greedy graph search——每一步走哪條邊，取決於到 query 的距離比較。這種 data-dependent 控制流是電路設計的噩夢：電路必須包含所有可能的分支，大小會隨資料集指數成長。加上 priority queue 的 heap 操作、sparse bitmap 的記憶體讀寫、浮點距離的精度問題，直接在電路裡執行 HNSW 幾乎不可能。
>
> zkRAG 的突破在於一個設計哲學的轉換：**不在電路裡重跑 HNSW，而是驗證搜尋 trace 的合法性**。
>
> 類比一個更簡單的問題：要證明一個 list 是排序的，不需要在電路裡實作排序算法；只需要「驗證相鄰元素大小關係都成立，且是原始 list 的排列」——這個驗算的代價遠遠更小。
>
> zkRAG 把同樣的思路應用到 HNSW：prover 先正常跑搜尋、得到 trace，再針對 trace 的四個結構性屬性設計四個輕量的 PIOP 來驗算。
>
> 效果：proving time 從用 zkVM 暴力跑的幾個小時縮到 50 秒，約 1000 倍加速。

---

## Slide 14 — zkRAG PIOP Flow

### 知識背景

四個 PIOP 對應 HNSW trace 的四種合法性條件：

**1. Priority-Queue Checker（單調性）**
Heap 的每次 pop 輸出必須是當前最小值。等價於：pop 序列是一個關於距離的非遞增排列。這是 **ordering constraint**，可以轉化成 sumcheck：
$$\sum_i \mathbf{1}[\text{pop}_i \leq \text{pop}_{i-1}] = |\text{pop trace}|$$

**2. Membership Selector（bitmap 正確性）**
哪些節點被 visit 過、哪些沒有。用 lookup argument：正確的 visited set 是一張表，每次存取都要查得到（visit）或查不到（skip），合法性等同 membership PIOP。

**3. Hybrid Lookup（圖結構合法性）**
每次從圖裡查到的鄰居，必須是 HNSW 圖真正的邊。用 lookup argument 查已承諾的鄰接矩陣多項式。「Hybrid」指同時用 range check 和 membership check 的組合。

**4. Distance Check（距離正確性）**
每次計算的 L2 或 cosine 距離必須正確。$\text{dist}(u, v)^2 = \sum_k (u_k - v_k)^2$ 是 inner product，直接用 sumcheck 驗算。

所有四個 PIOP 共享同一組**多項式承諾**（polynomial commitments），最後 batch 進一個 sumcheck，出一份 SNARG。Verifier 複雜度：$O(\log T + \log |V|)$，$T$ = trace 長度，$|V|$ = 圖節點數——接近理論下界。

### 逐字稿

> 這張 slide 展示 zkRAG 的四個 PIOP 的密碼學細節。
>
> Prover 先把整個搜尋 trace 提交成多項式承諾——這是後續所有驗算的「可信依據」。
>
> 然後四個 PIOP 分別驗算 trace 的四種屬性。**Priority-Queue Checker** 把 heap 的合法性轉化成 ordering constraint，用 sumcheck 驗算 pop 序列是單調的。**Membership Selector** 把 visited set 的讀寫轉化成 lookup argument。**Hybrid Lookup** 驗算每條搜尋走的邊確實在圖裡。**Distance Check** 用 sumcheck 直接驗算內積——$\|u - v\|^2$ 就是一個 sumcheck。
>
> 四個 PIOP 的精妙之處是：它們共享同一組多項式承諾，最後可以 batch 成一個 sumcheck 聚合，整體只出一份 proof。
>
> Verifier 的複雜度是 $O(\log T + \log |V|)$，幾乎是理論最優——verifier 永遠不需要看完整個 trace 或整個圖。
>
> 這是 PIOP 設計方法論的一個精彩案例：把一個表面上「電路不友善」的演算法，透過 trace decomposition 轉化成幾個各自電路友善的子問題，再 batch 成一份 proof。

---

## Slide 15 — EZKL Pipeline

### 知識背景

**核心問題：浮點數 → 有限體**

深度學習模型在 $\mathbb{R}$（浮點數）上運算；ZKP 電路只能在 $\mathbb{F}_p$（有限體）上運算。這個轉換不是免費的：

- 浮點數 $x$ 需要量化成定點數 $\tilde{x} = \lfloor x \cdot 2^s \rfloor$，$s$ 稱為 scale
- 每次乘法後需要做 **rescaling**（除以 $2^s$），但除法在有限體上需要乘以模反元素，這是一個非線性操作，需要 range check
- 模型精度與電路大小存在 trade-off：scale 越大精度越高，但電路 row 數越多

**Halo2 電路框架**

Halo2 是 Zcash 開發的 PIOP + KZG 的完整框架：
- **KZG polynomial commitment**：把多項式 $f$ 壓成一個 group element $[f(\tau)]_1$（$\tau$ 是 SRS 中的秘密）；可以在任意點開啟並驗證，只需要一個 pairing 操作
- **Universal SRS**：trusted setup 只做一次，之後可以給所有電路重複使用（不同於 Groth16 的 per-circuit setup）
- 原生支援 lookup argument：非算術 op（ReLU、range check）走 lookup table，跟 zkLLM 的 tlookup 是同一族技術

**EZKL 的編譯流程**：
- `gen_settings`：分析 ONNX graph，決定每個 op 走算術約束還是 lookup
- `calibrate`：用代表性輸入校正 scale $s$，確保量化誤差在容許範圍
- `compile_circuit`：ONNX op → Halo2 region（加法、乘法門 + lookup 表）
- `setup`：建立 KZG SRS，產生 proving key（pk，133 MB）和 verification key（vk，66 KB）；**只有 vk 是 verifier 需要的**
- `gen_witness`：前向傳遞，收集所有中間值作為 witness
- `prove`：KZG + Halo2 prover，輸出 ~82 KB proof
- `verify`：用 vk 驗算 proof

**量化誤差分析**：Demo A 的實測，k=15（電路 $2^{15}$ 行），mean absolute error 0.29%，在 embedding 相似度任務中可接受。

### 逐字稿

> 第三個工具是 **EZKL**，它是最接近工程實作的一層，解決的是「怎麼把實際的機器學習模型轉成 ZK 電路」。
>
> 這裡有一個根本的障礙：深度學習在浮點數上跑，而 ZKP 電路只能在有限體 $\mathbb{F}_p$ 上運算，兩者的數學結構完全不同。EZKL 的核心工作是做這個轉換——把浮點數量化成定點數（scaled integer），並把量化引入的 rescaling 操作表達成有限體上的 range check。
>
> 整個 pipeline 七步。前三步 gen_settings、calibrate、compile_circuit 是編譯期：分析 ONNX 模型，決定每個 op 走哪種約束——算術的走乘法門，非算術的（如 ReLU）走 lookup argument，跟 zkLLM 的 tlookup 是同一族技術。
>
> setup 建立 KZG 多項式承諾的 SRS——這是 Halo2 框架的核心，把一個多項式壓成一個 group element，驗算只需要一次 pairing 操作，極其高效。
>
> 後三步是執行期：gen_witness 跑前向傳遞收集中間值，prove 生成 82 KB 的 Halo2 proof，verify 驗算它。
>
> 密碼學上最重要的特性：**proving key（133 MB）只有 prover 需要；verification key（66 KB）才是 verifier 用的**。Verifier 只需要極少的資訊就能確認整個 inference 的正確性——這是 SNARK 的核心優點。
>
> 這整個工具鏈就是 **Demo A** 的核心，我們用它證明了一個 384 維到 64 維的 embedding layer。

---

## Slide 16 — Benchmark Comparison

### 逐字稿

> 最後這張 slide 把三篇論文放在一起對比，讓大家清楚每個密碼學系統的定位。
>
> 先看 proving time：zkLLM 負責最重的 transformer forward pass，LLaMA 13B 不到 15 分鐘；zkRAG 負責向量搜尋，trace 驗算 50 秒；EZKL 負責 ML 模型推論，幾十秒；RISC0 負責通用計算的單步驗算，秒級。
>
> 這個對比說明了一個核心的密碼學設計原則：**客製化 PIOP 永遠比通用電路快**。zkRAG 比 zkVM 快 1000 倍，是因為它針對 HNSW trace 的結構設計了對應的 PIOP；zkLLM 比直接在 zkVM 裡跑 LLM 快幾個數量級，是因為 tlookup 專門針對 LLM 的 tensor 結構設計。
>
> 通用性和效率之間，是 ZKP 系統設計的永遠 trade-off。
>
> 我們的 project 選擇了「層次化的客製 proof 系統」：每一層都用最適合它的密碼學工具，各自出 proof，最後統一驗算。後面 Person C 會說明怎麼把它們串起來。

---

## 論文連結

| 論文 | 連結 | 建議閱讀 |
|------|------|----------|
| **zkLLM** — Zero Knowledge Proofs for LLM Inference | https://arxiv.org/abs/2404.16109 | §1 intro + §3 tlookup + §4 zkAttn |
| **Plookup** — lookup argument 始祖 | https://eprint.iacr.org/2020/315 | §1–§2（理解 tlookup 的數學前置） |
| **Nova** — Recursive ZK from Folding | https://eprint.iacr.org/2021/370 | §1 intro + §3 folding construction |
| **HyperNova** — Generalized Folding | https://eprint.iacr.org/2023/573 | Abstract + §1 |
| **zkRAG** — ZK Proofs for HNSW | 搜尋 arxiv "zkRAG HNSW PIOP" | §1 intro + §4 four PIOPs |
| **Halo2 book** | https://zcash.github.io/halo2 | 理解 KZG + lookup gate |
| **EZKL 文件** | https://docs.ezkl.xyz | Quickstart + calibration guide |
| **Sumcheck tutorial** | Justin Thaler, PAZK §4 | sumcheck 協議的標準教材 |

---

## 快速複習單（報告前看這個）

```
核心主軸：LLM 的非算術運算（Softmax/GELU）無法直接表達成算術電路
          → 三篇論文各自用不同密碼學技術解決這個問題

Slide 9  zkVM：為 ISA 寫通用電路 = 證明任何程式
         RISC Zero = STARK(FRI) → Groth16 wrapping（proof of a proof）
         代價：比客製 PIOP 慢 10–100×

Slide 10 Folding：隨機線性組合 w' = w1 + r·w2
         Schwartz-Zippel 保證 soundness → N 份 proof 折成 1 份
         Nova = IVC 首個實用方案；HyperNova 推廣到 CCS

Slide 11 zkLLM：lookup argument 繞過「算」exp(x)
         ① shift invariance：softmax 減 max → 數值 bounded
         ② base-b 分解：exp(x) = ∏ exp(dk·bk) → 幾張小表
         ③ tlookup：整個 attention head batch 進同一 PIOP

Slide 12 zkAttn 5 步：
         矩陣乘（sumcheck）→ shift → digit 分解 → tlookup → 矩陣乘（sumcheck）
         設計原則：每步只用 sumcheck-friendly 或 lookup-friendly 的操作

Slide 13 zkRAG：HNSW 的 4 個電路難點
         解法：prove the trace, not re-execute
         類比：驗排序（O(n)）比電路跑排序便宜得多

Slide 14 4 個 PIOP（各自對應 trace 的一種合法性條件）：
         PQ Checker(monotone sumcheck) + Membership(lookup) +
         Hybrid Lookup(graph edge) + Distance Check(inner product sumcheck)
         → batched sumcheck → 一份 SNARG
         verifier 複雜度：O(log T + log |V|)

Slide 15 EZKL 核心問題：浮點數 → 有限體（定點量化 + rescaling）
         Halo2 = KZG 承諾 + lookup gate
         vk(66KB) = verifier 只需要這個
         pk(133MB) = prover 自用，verifier 不需要看

Slide 16 核心結論：客製 PIOP >> 通用 zkVM（1000× for HNSW）
         設計哲學：層次化客製 proof 系統，每層用最合適的密碼學工具
```



## 目錄
1. [區塊鏈計算瓶頸與 Cartesi 解決方案](#1-區塊鏈計算瓶頸與-cartesi-解決方案)
2. [零知識證明核心：STARK vs SNARK](#2-零知識證明核心stark-vs-snark)
3. [現代 zkVM（零知識虛擬機）的三大架構路線](#3-現代-zkvm零知識虛擬機的三大架構路線)
4. [大語言模型（LLM）推論中的非算術運算瓶頸](#4-大語言模型llm推論中的非算術運算瓶頸)
5. [高效能向量檢索：HNSW 演算法與可驗證搜尋（PIOP）](#5-高效能向量檢索hnsw-演算法與可驗證搜尋piop)

---

## 1. 區塊鏈計算瓶頸與 Cartesi 解決方案

### 核心痛點
* **計算瓶頸**：傳統區塊鏈（如以太坊 EVM）受限於鏈上共識機制，計算資源極度昂貴且緩慢，無法執行複雜的業務邏輯。
* **開發限制**：被迫使用 Solidity 等專用語言，難以複用傳統軟體成熟的開源生態（如 Python, Go, Rust）。
* **去中心化驗證兩難**：若直接將計算移至鏈下（Off-chain），鏈上智能合約將無法保證其結果的真實性。

### Cartesi Machine Emulator 的定位
`cartesi/machine-emulator` 是一個用 C++ 編寫的**確定性（Deterministic）RISC-V 虛擬機**：
* **原生 Linux 支援**：由於模擬標準 RISC-V 架構，可直接啟動完整的 Linux 作業系統，允許 DApp 運行主流語言編寫的複雜邏輯。
* **Optimistic Rollups 整合**：利用「確定性」確保相同輸入必有相同輸出。當節點發生爭議時，可在鏈上透過「互動式爭議解決協定」進行單步跳躍驗證（欺詐證明），大幅降低鏈上驗證成本。

---

## 2. 零知識證明核心：STARK vs SNARK

在可驗證計算中，STARK 與 SNARK 代表了兩種截然不同的數學權衡：

| 特性維度 | SNARK (以 Groth16 為例) | STARK |
| :--- | :--- | :--- |
| **全名** | Succinct Non-Interactive Argument of Knowledge | Scalable Transparent Argument of Knowledge |
| **可信設定 (Trusted Setup)** | **需要**（若隨機源洩漏有安全性風險） | **不需要**（完全透明，基於抗碰撞雜湊） |
| **證明體積 (Proof Size)** | **極小 (~200 bytes)** | 龐大 (~幾十到幾百 KB) |
| **鏈上驗證成本 (Gas)** | **極低 (~200k Gas)** | 極高（不適合直接上鏈結算） |
| **抗量子計算破壞** | 否（基於橢圓曲線） | **是**（僅基於雜湊函數） |
| **最佳應用場景** | 最終的鏈上結算與輕量化驗證 | 大規模、複雜系統的計算軌跡約束 |

### RISC Zero 的「組合拳」架構
為同時獲得兩者優勢，RISC Zero 採用了 **Proof Composition（證明組合/摺疊）** 技術：
1. **主要計算（STARK）**：用來約束龐大且複雜的 RISC-V CPU 指令電路，生成速度快且不需可信設定。
2. **最終壓縮（Groth16 Wrapper）**：將巨大的 STARK 證明作為輸入，丟進 Groth16 SNARK 電路中再次封裝，將體積壓縮至 **~200 bytes**，實現超低成本的鏈上驗證。

---

## 3. 現代 zkVM（零知識虛擬機）的三大架構路線

隨著技術演進，zkVM（虛擬機 + 零知識證明）發展出三種具備代表性的技術範式：

1. **RISC Zero（工程與商業化先鋒）**
   * **特點**：最早將 RISC-V zkVM 概念大規模商業化。
   * **路線**：採用「STARK 執行 + Groth16 壓縮」的標準雙層封裝管線，周邊工具鏈（如 Bonsai 服務）與傳統 Host 端整合最成熟。
2. **SP1 / Succinct Labs（極致效能派）**
   * **特點**：在 2025 年的基準測試（Benchmark）中展現出業界最快的證明生成速度（Proving Speed）。
   * **路線**：核心同樣是 RISC-V STARK，但透過大量高度客製化的 **Precompiles（預編譯模組）** 與動態分片（Sharding），將密碼學運算效能逼到極限。
3. **Jolt / a16z Crypto（全新學術範式）**
   * **特點**：由頂尖創投 a16z 的研究團隊提出，徹底顛覆傳統電路設計。
   * **路線**：基於 Lasso 論文，完全採用 **Lookup Argument（查表機制）**。將 CPU 的每條指令運算虛擬化為一張巨大的表格，證明過程即是「證明運算結果存在於合法表格中」，拋棄了傳統代數幾何電路約束，代碼極精簡且易於審計。

---

## 4. 大語言模型（LLM）推論中的非算術運算瓶頸

在 LLM 推論中，大眾目光常聚焦於矩陣乘法（GEMM）等算術運算，但**非算術運算（或非線性激活函數）**往往是導致延遲（Latency）的 Memory-bound（受限於記憶體頻寬）瓶頸：

* **Softmax**
  * *公式*: $\text{Softmax}(x_i) = \frac{e^{x_i}}{\sum e^{x_j}}$
  * *目的*: 將 Self-Attention 的分數或最後一層的 Token 輸出轉化為總和為 1 的**機率分佈**。
  * *硬體挑戰*: 需要多輪掃描向量（找最大值防溢位、算指數、求和、除法），數據在暫存器與顯存（HBM）間頻繁搬移。
* **GELU (Gaussian Error Linear Unit)**
  * *公式*: $\text{GELU}(x) = x \cdot \Phi(x)$
  * *目的*: 經典 Transformer 模型（如 GPT-3）的非線性激活函數。比傳統 ReLU 更優雅，在負數區域依據高斯分佈平滑趨近於 0，避免神經元壞死，訓練更穩定。
* **SwiGLU (Swish Gated Linear Unit)**
  * *公式*: $\text{SwiGLU}(x) = \text{Swish}(xW + b) \otimes xV$
  * *目的*: 現代 LLM（如 Llama 3, Gemma）標配的效能怪獸。透過雙通路門控機制（一邊進行 Swish 激活控制閘門，一邊進行線性變換後逐元素相乘），顯著提升模型的表達與泛化能力。

> **工程優化實務**：在部署推論時（如使用 vLLM 或 TensorRT-LLM），通常會透過 **Kernel Fusion（算子融合）** 將這些非算術運算與前後的矩陣乘法打包在同一個 GPU Kernel 中算完，大幅減少記憶體讀寫次數。

---

## 5. 高效能向量檢索：HNSW 演算法與可驗證搜尋（PIOP）

在 LLM 發展出的 **RAG（檢索增強生成）** 應用中，如何快速在海量 Embedding 中找到最相似的文檔是關鍵所在。

### HNSW (Hierarchical Navigable Small World) 原理
HNSW 是一種高維度向量的近似最近鄰搜尋（ANNS）演算法，將暴力搜索的 $O(N)$ 時間複雜度成功降至 **$O(\log N)$**：
* **NSW（導航小世界）**：建立具備長線（跨區域快速跳躍）與短線（局部精細定位）的社交網絡化圖形結構，透過貪婪搜尋逼近目標。
* **Hierarchical（分層機制）**：靈感源自跳表（Skip List）。頂層點稀疏，負責跨縣市的「高速公路」導航；向下層層變密，最底層（Layer 0）包含所有數據，負責最終的「市區巷弄」精準搜索。
* **工程權衡**：速度極快且召回率高（通常 >95%），但**極度消耗記憶體（RAM Hungry）**，因為圖結構與指標需全部常駐記憶體。

### 什麼是 first HNSW-specific PIOP？
這是將向量搜尋與前沿密碼學 ZKP 結合的重大突破，意即**「世界上第一個專門為 HNSW 演算法量身設計的多項式互動奧拉克爾證明（Polynomial Interactive Oracle Proof）框架」**。
* **破局點**：過去若要在 zkVM 裡驗證向量資料庫（Vector Database）的檢索正確性，通用電路的計算開銷高到無法實用。
* **意義**：PIOP 是 ZKP 的內部數學電路設計藍圖。透過 HNSW 專用的多項式方程設計，繞過了虛擬機的龐大開銷。這讓**可驗證向量搜尋（Verifiable Vector Search）**走向現實，用戶可以在不洩露隱私的前提下，以極低成本驗證資料庫回傳的 RAG 檢索結果是否真實、未經篡改。

---