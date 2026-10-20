# Sketch 01: Flow

**目標**：幾千顆粒子像被風吹著流動、發光。
**架構位置**：渲染層，也是待機畫面的雛形。

## 概念：一顆粒子的一生

VFX Graph 由四個 Context 由上往下組成，全部跑在 GPU：

| 區塊 | 負責 | 白話 |
|---|---|---|
| **Spawn** | 每秒生幾顆 | 出生率 |
| **Initialize Particle** | 出生時的屬性（位置、壽命、速度） | 出生在哪、活多久 |
| **Update Particle** | 每一幀做什麼（受力、移動） | 這一生被什麼推著走 |
| **Output** | 怎麼畫（形狀、顏色、大小、混合） | 長什麼樣子 |

每個區塊可疊多個 Block，由上往下執行。

## 步驟

### 1. 場景與相機

1. 建立資料夾 `Assets/_Project/Scenes/Sketches/` 與 `Assets/_Project/VFX/`
2. File → New Scene → **Standard (URP)**，存成 `Sketches/Sketch_01_Flow`
3. **Main Camera**：
   - Projection **Orthographic**，Size **5**
   - Position `(0, 0, -10)`
   - Environment → Background Type **Solid Color**，純黑
   - Rendering → **Post Processing** 打勾
4. Game 視窗解析度 `+` 新增 **1920×960**（Fixed Resolution）

### 2. 建立 VFX

1. `_Project/VFX/` 右鍵 → Create → Visual Effects → **Visual Effect Graph**，範本選 **Simple Loop**，命名 `Flow`
2. 拖進 Hierarchy，Position `(0,0,0)`
3. 雙擊打開 graph

### 3. 改造四個區塊

**Spawn**
- Constant Spawn Rate **2000**

**Initialize Particle**
- Capacity **20000**
- Bounds：Center `(0,0,0)`，Size `(22, 12, 4)`
- 刪掉原本的位置 Block，加 **Set Position (Shape: AABox)**，Size `(20, 10, 0.5)`
- **Set Lifetime Random**：4 ~ 8
- 有 Set Velocity 的話刪掉（不要初速，讓場推動）

**Update Particle**
- 刪掉 Gravity（若有）
- 加 **Turbulence**：Intensity **2**、Drag **1**、Frequency **0.3**、Octaves **2**

**Output**
- Blend Mode **Additive**
- Set Size **0.04**
- 加 **Set Color over Life**：青 → 紫；Alpha 頭尾 0、中間 1
- 顏色 HDR Intensity **2 ~ 3**

### 4. Bloom

1. 選 **Global Volume** → Profile → Add Override → Post-processing → **Bloom**
2. Threshold **0.8**，Intensity **1.5**

## 小實驗（一次只改一個）

- **Frequency** 0.1 ↔ 1.0：漩渦變大或變碎
- **Intensity : Drag** 比例：被風拖著走 ↔ 慢慢漂
- **Spawn Rate、Size**：密度與質感

## 我的數值與筆記

（做完後記下喜歡的參數與觀察，Main 場景會從這裡抄）

- Turbulence：Intensity __ / Drag __ / Frequency __ / Octaves __
- Spawn Rate __，Size __，Lifetime __
- 顏色：
- 觀察：
