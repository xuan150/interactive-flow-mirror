# Sketch 02b: Line Field

**目標**：90 條錨定的水平平行線，緩慢起伏、呼吸、流光，**待機畫面完成**。
**架構位置**：渲染層。
**前置**：02（Particle Strip 的概念）
**參考**：Rutt-Etra 錄影合成器、Joy Division《Unknown Pleasures》封面、使用者提供的平行線起伏影片

## 概念：線條不再被風吹走

02 的線是粒子被風推著跑留下的軌跡；這張的線**每個點都有固定原位**，每一幀重新計算位置：

```
位置 = 原位（第幾條線 → y、線上第幾個點 → x）
     + 起伏（noise，隨時間流動）
     + 呼吸（慢波從左掃到右）
亮度 = 基礎亮度 + 流光（亮斑沿線流過）
```

位置在 **Update** 裡用 Set Position 每幀「重算」而不是「累加」，所以怎麼晃都會回到原位附近。

### 新觀念：Operator

graph 上浮著的數學節點。Block 是「對粒子做一件事」，Operator 是「算出一個值」再接進 Block 的插槽。

- 建立：graph 空白處右鍵 → **Create Node**（或空白鍵），搜尋名稱
- 連線：從節點右側的**輸出圓點**拖到 Block 或其他節點左側的**輸入圓點**；一個輸出可以接很多地方
- 沒接線的輸入可以直接打數字
- Vector3 插槽（例如 Position）左邊的小三角可以展開成 x / y / z，各自接線

| 會用到的 | 作用 |
|---|---|
| Get Attribute（spawnIndex、stripIndex、particleIndexInStrip） | 讀粒子自己的屬性 |
| Divide、Floor、Lerp | 除法、無條件捨去、在兩值之間按比例取值 |
| Total Time | 特效開始後經過的秒數，讓東西隨時間動 |
| Perlin Noise、Sine | 平滑的隨機起伏、規律的波 |

## 決定

- 90 條線 × 每條 200 點（Single Burst 一次生成 18000 個點，永生）
- 線延伸到畫面外（x = -11 ~ 11），起伏時看不到線頭
- 冷藍柔白，之後邊看邊調；保留 Bloom 朦朧光
- 待機要有：起伏 ＋ 呼吸 ＋ 流光，不能完全靜止
- 起伏的 noise 在 y 方向頻率很低，讓相鄰的線起伏相似（整片一起波動，而不是各晃各的）

## 步驟

### 0. 場景

1. 複製 `Sketch_02_lines`（Ctrl+D），改名 `Sketch_02_lineField`，放進同名資料夾並打開
2. Global Volume → Profile 旁按 **Clone**
3. 刪掉 Hierarchy 裡的 `Lines`，存場景
4. 確認 Main Camera Position 是 `(0, 0, -10)`：範本預設 Y = 1，01 起就沒改到，平行線會讓頂端空出一條、底下一條跑出畫面

### ① 90 條筆直的平行線

1. `_Project/VFX/` 建 Visual Effect Graph，範本選 **Simple Trail**，命名 `LineField`，拖進 Hierarchy，Position `(0,0,0)`

**Spawn**
- 刪掉 Constant Spawn Rate，加 **Single Burst**：Count **18000**（開場一次生完）

**Initialize Particle Strip**
- Strip Capacity **90**、Particle Per Strip Count **200**
- Bounds Mode **Manual**，Center `(0,0,0)`、Size `(24, 12, 4)`
- 刪掉 **Set Lifetime**（沒有壽命＝永生）、**Set Position Sequential**、**Set Velocity**
- 加 **Set Size** **0.025**
- **Strip Index**（Context 標題下方的輸入圓點）：第幾條線 = `floor(spawnIndex ÷ 200)`
  - Create Node → `spawnIndex`（Get Attribute: spawnIndex）→ **Divide**（b = 200）→ **Floor** → 接到 Strip Index

**Update Particles**
- 加 **Set Position**，展開 Position 成 x / y / z：
  - **x** = `Lerp(-11, 11, particleIndexInStrip ÷ 199)`：Get Attribute `particleIndexInStrip` → Divide（b = 199）→ **Lerp** 的 s；Lerp 的 x = -11、y = 11
  - **y** = `Lerp(-5, 5, stripIndex ÷ 89)`：Get Attribute `stripIndex` → Divide（b = 89）→ 另一個 Lerp（x = -5、y = 5）
  - **z** = 0

**Render Strip（Output）**
- Blend Mode **Additive**
- 刪掉 Size 與 Color 的曲線 Block
- 加 **Set Color**：冷藍柔白，例如 `(0.75, 0.85, 1.0)`，HDR Intensity 約 **1**

### ② 起伏（noise）

讓每個點在 y 方向加上一個隨位置與時間變化的平滑值：

```
y = 原位 y + PerlinNoise(x, 原位 y, 時間) × 振幅
```

noise 的輸入座標包含**時間**，所以同一個點取到的值會慢慢改變 → 線在動；
相鄰的線原位 y 只差 0.11，取到的 noise 很接近 → 整片一起波動、彼此平行。

1. Create Node → **Perlin Noise**，選取節點後在 Inspector 把 Dimensions 設為 **Three**（節點名變成 Perlin Noise 3D）
2. 展開 **coordinate** 成 x / y / z：
   - x ← 算 Position.x 的那個 Lerp 輸出（一個輸出可以接多處）
   - y ← 算 Position.y 的那個 Lerp 輸出
   - z ← Create Node → **Total Time**（VFX 的那個）
3. frequency **0.15**、octaves **1**、range `(-0.35, 0.35)`：range 就是輸出的上下限，等於振幅
4. Create Node → **Add**：a ← y 的 Lerp、b ← Noise 輸出；Add 的輸出接到 **Position.y**（取代原本 Lerp 直接接的那條）

frequency 同時縮放空間與時間：越大，波越碎、也動越快。想分開調速度，在 Total Time 後面加一個 Multiply。

### ②+ 只讓局部起伏（權重遮罩）

不要用「動／不動」的開關（例如 index 取餘數）：相鄰點一個動一個不動，連成線就是斷崖鋸齒。
改用 0 ~ 1 的**權重**平滑過渡：

```
y = 原位 y + 起伏 noise × 權重
權重 = Smoothstep(下限, 上限, 低頻 noise)
```

畫面上會有幾塊區域在起伏、其他地方平靜，區域本身也慢慢漂移。身影之後也是同一個邏輯：權重改由人的遮罩決定。

1. 再建一個 **Perlin Noise 3D**（遮罩 noise），coordinate 接法同上（x、y 的 Lerp，z 接時間）
   - frequency **0.12**（比起伏 noise 低很多 → 區塊大）、octaves 1、range `(0, 1)`
2. **Smoothstep**：x（下限）**0.45**、y（上限）**0.7**、s ← 遮罩 noise
   - 低於下限＝0（平靜）、高於上限＝1（完整起伏），中間是平滑 S 曲線
3. **Multiply**：a ← 起伏 noise、b ← Smoothstep；輸出接到 Add 的 **b**（取代起伏 noise 直接接的那條）

Perlin noise 的值多半落在中間（0.5 附近），很少到兩端。平靜區太多就把下限往下調，太少就往上調。

### ③ 呼吸

一道淺淺的隆起從左掃到右，掃完休息一下再來一次：

```
波峰位置 xs = Periodic Total Time（Period 10 秒，Range -14 ~ 26）
隆起     = (1 - Smoothstep(0, 寬度, |x - xs|)) × 振幅
y        = 原位 y + 起伏 × 權重 + 隆起
```

- **Periodic Total Time**：時間每 Period 秒循環一次，輸出在 Range 之間來回線性走一遍 → 直接就是波峰的 x 位置
- Range 故意超出畫面（畫面只到 ±11）：波峰走到 14 ~ 26 時在畫面外＝**休息時間**，呼吸之間有停頓
- 離波峰越近隆起越高，超過「寬度」就是 0

1. Create Node → **Periodic Total Time**：Period **10**、Range `(-14, 26)`
2. **Subtract**：a ← x 的 Lerp 輸出、b ← Periodic Total Time → **Absolute** → 得到「離波峰多遠」
3. **Smoothstep**：x **0**、y **2.5**（寬度）、s ← Absolute → 再接 **One Minus**（1 - 值，讓波峰處＝1）
4. **Multiply**：a ← One Minus、b **0.4**（振幅）
5. 再一個 **Add**：a ← 原本接 Position.y 的那個 Add 的輸出、b ← 隆起；輸出接到 **Position.y**

結果：位置上的隆起和本來就在動的起伏**打架**，掃過去時像是起伏被打斷。

### ④ 流光（把 ③ 的隆起改接到亮度）

同一個「以某點為中心的柔和隆起」配方，不推位置、改推**亮度**：一道光帶掃過線條，起伏不受干擾。

```
亮度 = 基礎 0.5 ＋ 隆起 × 2
```

基礎值讓沒被光帶照到的線不會全暗；Additive 下亮度越高、Bloom 越會暈開。

1. 把 ③ 的第二個 Add 拿掉：第一個 Add 的輸出接回 **Position.y**
2. ③ 的振幅 Multiply 改成 b **2**（強度），後面接 **Add**（b **0.5**，基礎）
3. **Render Strip（Output）** 加 **Multiply Color**，Color ← 上一步的 Add（單一數值接到顏色會自動套到 RGB；接不上的話改用 Multiply Alpha，基礎值要 < 1）

使用者的做法（更彈性）：不用 One Minus ＋ Multiply Color，而是把 Smoothstep（離波峰多遠）直接接到一個 **Color 漸層 Block 的 Sample Time**，漸層一端是 HDR 亮色、另一端是基礎色，光帶的顏色與亮度分布直接在漸層上畫。

**讓光帶不是一整根垂直柱子**：每條線的波峰加一個固定偏移，`波峰 = PeriodicTotalTime(Period 固定) + 偏移(stripIndex)`。
- 斜光帶：偏移 = stripIndex × 0.6
- 參差光帶：偏移 = Perlin Noise 1D（coordinate ← stripIndex、frequency 0.3、range ±3），不接時間
- ⚠ 不要改每條線的 **Period**（例如 `8 + stripIndex × 0.2`）：週期不同＝時鐘快慢不同，一開始對齊，久了完全散開

## 小實驗

- 線數、點數、線寬：密度與質感
- noise 的 x / y / 時間頻率：起伏的大小、整片一致或各自晃動、速度

## 我的數值與筆記

- 線數 **20** × 點數 **100**（Burst 2000、Divide 100 / 99 / 19），線寬 **0.02** ＋ **Subpixel Anti-Aliasing**（試過 90、30 條；少線＝一條條大膽的筆畫，身影解析度到 05 再看）
- 顏色：保留範本的沿線取樣漸層（不用單一 Set Color）：左端 HDR 亮青 `(0.59, 1.56, 1.92)` → 右端淡白 `(0.77, 0.89, 0.97)`，有深度、之後的流光與交會換色都能疊在上面
- 起伏：Perlin 3D，frequency **0.38**、octaves 1、range **-0.82 ~ 1.28**（偏向往上隆起），時間 × **1.2**
- 遮罩：Perlin 3D，frequency **0.08**、range 0 ~ 1，Smoothstep **0.32 ~ 0.56**
- 呼吸：振幅 __、波長 __、週期 __
- 線寬最後調為 **0.015**
- 呼吸＋流光（合併）：Periodic Total Time Range -14 ~ 26，Smoothstep 0 ~ 2.5（離波峰距離）→ 漸層 Sample Time（波峰 HDR 亮色、遠處基礎色）
  - Period 目前是 `8 + stripIndex × 0.2`，**會越跑越散**；Main 時改成固定 Period 8 ＋ 位置偏移（見 ④）
- Bloom：Threshold 0.8 / Intensity **4**
- 狀態：學會組裝即收尾，最終數值到 Main 統一調
- 觀察：
  - 想讓部分點不動時，「index 取餘數」這種開關會讓相鄰點一動一不動，連線成斷崖鋸齒；要用 0 ~ 1 的平滑權重（低頻 noise + Smoothstep）
  - 線寬 < 1 像素會出現階梯與空隙（aliasing），加點數沒用；用 Subpixel AA、MSAA 或加粗。判斷畫質要看 Game 視窗 1x，縮小預覽會更斷
