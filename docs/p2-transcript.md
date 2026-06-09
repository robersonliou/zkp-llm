# Person B — Slides 10–17 逐字稿（Core Papers）

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

## Slide 10 — zkVM Landscape

### 知識背景（報告者背景筆記，非投影片內容）

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

> 好，前面介紹完了 ZKP 的理論基礎，現在我們來看業界怎麼解決「讓任意程式都可以被 ZK 驗算」這個問題。
>
> 核心困難是：要對一段程式產生 ZK proof，傳統做法是手工把這段程式寫成電路。但 LLM 有幾億條運算，HNSW 搜尋還會根據資料動態決定走哪條路——手工寫電路完全行不通。
>
> zkVM 的做法是換一個角度：**不為具體程式寫電路，而是為 CPU 指令集本身寫一個通用電路**。只要能驗算「每條 RISC-V 指令都被正確執行了」，就能間接驗算跑在這個 CPU 上的任何程式。開發者照常用 Rust 寫程式，zkVM 自動處理剩下的事。
>
> RISC Zero 的另一個設計亮點是 **proof 壓縮**：主要計算用 STARK 產生一份約 100 KB 的 proof，然後再用 Groth16 把「驗算這份 STARK 的過程」本身也包成一個 proof，最終輸出只有 200 bytes。這是「用 proof 驗算另一個 proof」——大幅降低鏈上或傳輸的成本。
>
> 但通用方案的代價是效率：驗算任意程式的電路開銷，是針對特定算法量身設計的方案的 10 到 100 倍。這就是為什麼接下來的 zkLLM 和 zkRAG 會選擇為各自的算法單獨設計 proof 系統。

---

## Slide 11 — Folding Schemes

### 知識背景（報告者背景筆記，非投影片內容）

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

> 接著介紹 Folding Schemes，這是目前 ZKP 研究裡最活躍的 proof 壓縮技術。
>
> 問題是：假設整個 AI 推論流程分成很多步驟，每步都需要一份 proof。如果步驟有幾百步，就要出幾百份 proof，儲存和驗算成本完全不實際。
>
> Folding 的解法很直覺：**把兩份 proof「折疊」成一份**。核心操作是把兩份計算的中間值做一個隨機加權混合，混合後的結果同時滿足兩份原始計算的約束——數學上可以嚴格證明這個混合不會引入錯誤。重複這個操作，N 份 proof 就能逐步折成 1 份。
>
> **Nova**（2021, Microsoft Research）是第一個讓這件事在實務上可行的方案。它的關鍵突破是：每次折疊新增的電路開銷是固定的、不隨步驟數增長——所以折一千步和折兩步的成本幾乎一樣。
>
> **HyperNova** 把同樣的框架推廣到更多種類的電路格式，讓現代 ZKP 工具鏈都能直接受益。
>
> 在我們架構的未來規劃裡，folding 是用來把整個推論流程的多份 proof 壓成一份的關鍵技術，從根本上降低最終驗算成本。

---

## Slide 12 — zkLLM: Motivation & tlookup

### 知識背景（報告者背景筆記，非投影片內容）

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

> 現在進入核心論文。第一篇是 **zkLLM**，它直接面對「怎麼讓 LLM 的計算可以被 ZK 驗算」這個根本問題。
>
> 問題出在 LLM 的激活函數。ZK 電路本質上只能做加法和乘法，但 LLM 裡到處都是 Softmax、GELU——這些函數裡有指數、有高斯積分，根本沒辦法直接在電路裡表達。如果硬用多項式去逼近，想要的精度越高，電路就越大，最後大到完全無法實作。
>
> zkLLM 的解法是**換一種思路**：不要在電路裡算 exp(x)，而是預先把 exp 的輸入輸出值列成一張查表，然後讓 prover 去「證明他用的每一個值都能在這張表裡查到」。查表比計算便宜得多，證明查表正確性也有成熟的密碼學方法。
>
> 但 LLM 的數值範圍很廣，表如果太大一樣不實用。這裡有兩個工程技巧：第一，Softmax 減掉每行最大值後結果不變，但所有值被壓進一個很小的範圍；第二，把指數的輸入拆成幾個位數，每個位數各查一張小表，最後把結果乘起來。這樣每張表都很緊湊。
>
> **tlookup** 再往前一步：把整個 attention head 的所有查表操作一次批量驗算，所有 head 共用同一份開銷，大幅攤薄證明成本。
>
> 效果：LLaMA 13B 完整跑一次 forward pass，proving time 不到 15 分鐘，proof size 不到 200 KB——這是第一個在生產規模的 LLM 上實際可用的 ZK proof 系統。

---

## Slide 13 — zkRAG: Motivation

### 知識背景（報告者背景筆記，非投影片內容）

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

### 逐字稿

> 第二篇核心論文是 **zkRAG**，2026 年 4 月發布，是第一個針對向量資料庫搜尋設計的 ZK proof 系統。
>
> 問題在於：RAG 的核心操作是 HNSW——一種在高維向量圖裡 greedy 尋找最近鄰的算法。HNSW 的每一步要走哪條邊，完全由當下的距離計算動態決定；它還用了 priority queue 來管理候選節點，用 bitmap 記錄哪些節點已經走訪過。這些動態、data-dependent 的結構，對 ZK 電路設計來說極度不友善——電路必須預先編碼所有可能的執行路徑，規模會隨資料集指數爆炸。
>
> zkRAG 的核心洞見是**換一個問題問法**：不要試圖在電路裡重新跑一遍 HNSW，而是讓 prover 先正常跑完搜尋，記錄下整個執行過程，再去**證明這份紀錄是合法的**。
>
> 類比：如果有人交給你一份「排好序的清單」，要驗證它是否真的排好了，你只需要逐一比較相鄰項目——這遠比在電路裡跑完整的排序算法便宜。zkRAG 把同樣的邏輯應用到 HNSW 的執行紀錄上。
>
> 效果非常顯著：同樣的搜尋任務，用通用 zkVM 需要幾個小時；zkRAG 只需要 50 秒，**約 1000 倍加速**。

---

## Slide 14 — zkRAG PIOP Flow

### 知識背景（報告者背景筆記，非投影片內容）

四個 PIOP 對應 HNSW trace 的四種合法性條件：

**1. Priority-Queue Checker（單調性）**
Heap 的每次 pop 輸出必須是當前最小值。等價於：pop 序列是一個關於距離的非遞增排列。這是 **ordering constraint**，可以轉化成 sumcheck。

**2. Membership Selector（bitmap 正確性）**
哪些節點被 visit 過、哪些沒有。用 lookup argument：正確的 visited set 是一張表，每次存取都要查得到（visit）或查不到（skip），合法性等同 membership PIOP。

**3. Hybrid Lookup（圖結構合法性）**
每次從圖裡查到的鄰居，必須是 HNSW 圖真正的邊。用 lookup argument 查已承諾的鄰接矩陣多項式。「Hybrid」指同時用 range check 和 membership check 的組合。

**4. Distance Check（距離正確性）**
每次計算的 L2 或 cosine 距離必須正確。$\text{dist}(u, v)^2 = \sum_k (u_k - v_k)^2$ 是 inner product，直接用 sumcheck 驗算。

Verifier 複雜度：$O(\log T + \log |V|)$，$T$ = trace 長度，$|V|$ = 圖節點數——接近理論下界。

### 逐字稿

> 這張 slide 說明 zkRAG 具體怎麼驗算搜尋紀錄。
>
> Prover 先把整個搜尋過程的紀錄提交出去，作為後續所有驗算的基礎。接著用四個各自針對不同問題的輕量驗算器：
>
> 第一個驗算 **priority queue 的行為是否正確**——每次彈出的節點是否真的是當時距離最小的那個。
>
> 第二個驗算 **visited bitmap 是否一致**——有沒有節點被重複走訪，或應該跳過的沒跳過。
>
> 第三個驗算 **走過的每條邊是否真的存在於圖中**——prover 不能捏造不存在的捷徑。
>
> 第四個驗算 **每一步的距離計算是否正確**——向量間的距離是高維內積，可以用一種高效的協議批量驗算。
>
> 四個驗算器共用同一份底層資料提交，最後批量合成一份 proof 輸出。
>
> 空間上的效益很明顯：verifier 的工作量只跟 trace 長度的**對數**成正比，不需要逐步重新看完整個搜尋過程——搜尋了一萬個節點，verifier 只需要看大約十幾個關鍵點就能確認正確性。

---

## Slide 15 — EZKL Pipeline

### 知識背景（報告者背景筆記，非投影片內容）

**核心問題：浮點數 → 有限體**

深度學習模型在 $\mathbb{R}$（浮點數）上運算；ZKP 電路只能在 $\mathbb{F}_p$（有限體）上運算。這個轉換不是免費的：

- 浮點數 $x$ 需要量化成定點數 $\tilde{x} = \lfloor x \cdot 2^s \rfloor$，$s$ 稱為 scale
- 每次乘法後需要做 **rescaling**（除以 $2^s$），但除法在有限體上需要乘以模反元素，需要 range check
- 模型精度與電路大小存在 trade-off：scale 越大精度越高，但電路 row 數越多

**Halo2 電路框架**

Halo2 是 Zcash 開發的 PIOP + KZG 的完整框架：
- **KZG polynomial commitment**：把多項式 $f$ 壓成一個 group element $[f(\tau)]_1$；可以在任意點開啟並驗證，只需要一個 pairing 操作
- **Universal SRS**：trusted setup 只做一次，之後可以給所有電路重複使用
- 原生支援 lookup argument：非算術 op（ReLU、range check）走 lookup table，跟 zkLLM 的 tlookup 是同一族技術

**EZKL 的七步流程**：
`gen_settings` → `calibrate` → `compile_circuit` → `setup (KZG SRS)` → `gen_witness` → `prove` → `verify`

關鍵：proving key（pk，133 MB）只有 prover 需要；verification key（vk，66 KB）才是 verifier 用的。Demo A 實測 k=15，mean absolute error 0.29%。

### 逐字稿

> 第三個工具是 **EZKL**，它解決的是最貼近工程的問題：怎麼把一個訓練好的深度學習模型，自動轉換成可以產生 ZK proof 的電路。
>
> 根本障礙是數字格式不同。神經網路跑在浮點數上；ZK 電路只能用整數在一個特殊的數字系統裡運算。EZKL 的核心工作就是做這個格式轉換——把模型的浮點權重和激活值量化成整數，精度損失控制在可接受的範圍內。Demo A 實測的誤差只有 0.29%。
>
> 整個流程是七個步驟：先讀進 ONNX 格式的模型，自動分析每個算子，編譯成 ZK 電路，設定密碼學參數，然後就可以對任意輸入產生 proof、並在鏈上驗算。
>
> 有一個很重要的非對稱性：**proving key 有 133 MB，verification key 只有 66 KB**。Proving key 是 prover 用的，verifier 完全不需要看，只需要拿著那份 66 KB 的 key 就能確認整個 inference 是否正確執行。這正是 ZK proof 的核心價值：生成難、驗算極其便宜。
>
> 我們的 **Demo A** 就是用這套工具鏈，對一個 embedding 模型的推論產生完整的 ZK proof。

---

## Slide 16 — Benchmark Comparison

### 逐字稿

> 最後這張 slide 把幾個系統的效能放在一起比較，幫大家建立直覺。
>
> 從 proving time 來看：zkLLM 負責最重的 transformer 推論，LLaMA 13B 不到 15 分鐘；zkRAG 的向量搜尋驗算是 50 秒；EZKL 的小型模型幾十秒；RISC Zero 的通用單步驗算在秒級。
>
> 這個數字說明一件事：**針對具體問題量身設計的 proof 系統，可以比通用 zkVM 快上千倍**。zkRAG 的 50 秒 vs. zkVM 的幾個小時，差距完全來自「針對 HNSW 的結構設計專屬驗算器」這個選擇。
>
> 背後的 trade-off 是通用性。zkVM 可以驗算任何程式；zkLLM 只能驗算 transformer；zkRAG 只能驗算 HNSW 搜尋。我們的架構選擇接受這個 trade-off——**每一層任務用最適合它的工具，各自出 proof，再整合在一起**。
>
> 後面 Person C 會說明我們的整體架構如何把這些 proof 串接起來。

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

Slide 10 zkVM：為 ISA 寫通用電路 = 證明任何程式
         RISC Zero = STARK(FRI) → Groth16 wrapping（proof of a proof）
         代價：比客製 PIOP 慢 10–100×

Slide 11 Folding：隨機線性組合 w' = w1 + r·w2
         Schwartz-Zippel 保證 soundness → N 份 proof 折成 1 份
         Nova = IVC 首個實用方案；HyperNova 推廣到 CCS

Slide 12 zkLLM：lookup argument 繞過「算」exp(x)
         ① shift invariance：softmax 減 max → 數值 bounded
         ② base-b 分解：exp(x) = ∏ exp(dk·bk) → 幾張小表
         ③ tlookup：整個 attention head batch 進同一 PIOP


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
