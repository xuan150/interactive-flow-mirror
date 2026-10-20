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

### Block 放哪、用哪個

- **放哪個 Context**：問「什麼時候發生」。出生一次 → Initialize；每幀、會被記住 → Update；只影響畫出來的樣子 → Output
- **用哪個 Block**：先想要改哪個屬性（左側 Attributes：position、velocity、color、size…），名稱規則是 `動作 + 屬性 + 方式`，例如 `Set Lifetime Random`、`Multiply Color Over Life`
- 在 Context 裡按空白鍵搜尋，選單只列出能放在該 Context 的 Block
- 範例庫：Package Manager → Visual Effect Graph → Samples → **Learning Templates**

## 步驟

### 1. 場景與相機

1. 建立資料夾 `Assets/_Project/Scenes/Sketches/` 與 `Assets/_Project/VFX/`
2. File → New Scene → **Standard (URP)**，存成 `Sketches/Sketch_01_Flow`
3. **Main Camera**：
   - Projection **Orthographic**，Size **5**
   - Position `(0, 0, -10)`（範本預設 Y 是 1，要改成 0）
   - Environment → Background Type **Solid Color**，純黑
   - Rendering → **Post Processing** 打勾
4. Game 視窗解析度 `+` 新增 **1920×960**（Fixed Resolution）

### 2. 建立 VFX

1. `_Project/VFX/` 右鍵 → Create → Visual Effects → **Visual Effect Graph**，範本選 **Simple Loop**，命名 `Flow`
2. 拖進 Hierarchy，Position `(0,0,0)`
3. 雙擊打開 graph（編輯模式下也會持續模擬，Scene 視窗的 Visual Effect 面板可暫停／重播）

### 3. 改造四個區塊（以 Simple Loop 範本為準）

**Spawn**
- Constant Spawn Rate：Rate **2000**

**Initialize Particle**
- Capacity **20000**（每秒 2000 × 最長壽命 8 秒，再留餘裕）
- Bounds Mode **Manual**，Center `(0,0,0)`，Size `(22, 12, 4)`（改完標題的 ⚠ 會消失）
- Set Lifetime Random Uniform：A **4**、B **8**
- Set Position Shape：Shape **Box**、Position Mode **Volume**，Center `(0,0,0)`、Size `(20, 10, 0.5)`
- 刪掉 **Set Velocity from Direction & Speed**（不要初速，讓場推動）
- 最下面加 **Set Size** **0.04**

**Update Particle**
- 刪掉 **Gravity** 與 **Linear Drag**（Turbulence 自帶 Drag）
- 加 **Turbulence**：Intensity **2**、Drag **1**、Frequency **0.3**、Octaves **2**

**Output Particle Unlit Quad**
- Blend Mode **Additive**
- 保留 Orient: Face Camera Plane
- 刪掉 **Multiply Size Over Life**（曲線從 0 開始，粒子出生時看不見）
- **Multiply Color Over Life** 漸層：Alpha 頭尾 0、中間 255；顏色青 → 紫，HDR Intensity **2 ~ 3**

存檔：graph 裡 Ctrl+S；場景另外在主視窗 Ctrl+S。

### 4. Bloom

Standard (URP) 場景範本**沒有附 Global Volume**，要自己建：

1. Hierarchy 右鍵 → Volume → **Global Volume**
2. Inspector 的 Profile 按 **New**（建在場景旁的 `Sketch_01_Flow/` 資料夾，只屬於這個場景）
3. Add Override → Post-processing → **Bloom**：Threshold **0.8**，Intensity **1.5**

不要改 `Assets/Settings/DefaultVolumeProfile`，那是全專案預設，每個場景都會吃到。

## 小實驗（一次只改一個）

- **Frequency** 0.1 ↔ 1.0：漩渦變大或變碎
- **Intensity : Drag** 比例：被風拖著走 ↔ 慢慢漂
- **Spawn Rate、Size**：密度與質感

## 我的數值與筆記

- Turbulence：Intensity **1.3** / Drag **1** / Frequency **0.2** / Octaves **2**
- Spawn Rate 2000，Size 0.04，Lifetime 4 ~ 8
- 顏色：Multiply Color Over Life，紫（約 24%）→ 淡青白（中段）→ 白（約 85%），HDR；Alpha 頭尾 0、中間 1
- Bloom：Threshold 0.8 / Intensity **6**
- 觀察：
  - Frequency 調到 2 以上，畫面像固定不動。Turbulence 的 noise 場本身不隨時間變，頻率越高漩渦格子越小，粒子在小格子裡打轉、走不遠，看起來就像停住。要大範圍流動就用低頻
  - 最喜歡的是 Bloom Intensity 拉高、光暈慢慢散開的朦朧柔和感，之後的線條也往這個方向調
