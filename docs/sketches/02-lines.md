# Sketch 02: Lines

**目標**：Sketch 01 的光點拉成流動的線條，**待機畫面完成**。
**架構位置**：渲染層。
**前置**：01（沿用風場數值與 Bloom）

## 概念：筆尖與墨跡

**Heads & Trails** 範本是兩個粒子系統串起來：

- **Head（筆尖）**：和 Sketch 01 的粒子一樣，被 Turbulence 推著跑
- **Trail（墨跡）**：每個筆尖在 Update 裡用 **Trigger Event** 每秒留下幾顆粒子，透過 **GPU Event** 交給第二個系統；**Particle Strip** 把同一支筆留下的粒子依序連成一條帶子

線條的形狀＝筆尖走過的路徑，也就是把風場畫出來。

| 數值 | 意義 |
|---|---|
| **Strip Capacity** | 同時幾條線（＝筆尖上限） |
| **Particle Per Strip Count** | 每條線最多幾個點（＝長度） |
| 墨跡 Lifetime × 每秒留點數 | 實際長度，不能超過 Particle Per Strip Count |

## 決定

- 線條性格 **B**：約 500 條 × 60 點，看得到流向也看得出一條一條（太少拼不出身影，太密交會時看不出被捲走）
- 筆尖：**隱藏**，畫面只有線條
- 漸層：**沿著線條**，線頭亮、線尾暗並收細

## 步驟

### 1. 場景

1. 複製 `Sketch_01_flow`（Ctrl+D），改名 `Sketch_02_Lines` 並打開
2. Global Volume → Profile 旁按 **Clone**（不 Clone 的話兩個場景共用同一份 Profile，調 02 會改到 01）
3. 刪掉 Hierarchy 裡的 `Flow`，存場景

### 2. 建立 VFX

1. `_Project/VFX/` 右鍵 → Create → Visual Effects → Visual Effect Graph，範本選 **Heads & Trails**，命名 `Lines`
2. 拖進 Hierarchy，Position `(0,0,0)`

### 3. 改造

範本裡墨跡會 **Inherit Source Lifetime / Age**：每顆墨跡和它的筆尖同年齡、同壽命，筆尖死時整條線一起消失。
所以線條是「從出生點一路畫到筆尖」的筆畫，不是固定長度的尾巴。好處是筆尖的位置被新筆尖重用時，舊線已經死光，不會出現橫跨畫面的直線。
長度限制：`Trigger Rate × 筆尖最長壽命 ≤ Particle Per Strip Count`（12 × 5 = 60），超過的點會被丟掉，線就畫不下去。

**筆尖：Spawn**
- Rate 10 → **100**（500 支筆 ÷ 最長壽命 5 秒）

**筆尖：Initialize Particle（Heads）**
- Capacity **500**；Bounds Mode **Manual**，Center `(0,0,0)`、Size `(22, 12, 4)`
- Set Lifetime Random：**3 ~ 5**
- Set Size Random：**0.02 ~ 0.05**（墨跡會繼承，＝線寬）
- 刪掉 **Set Color Random**（顏色改在線條 Output 決定）
- Set Position Shape：Shape **Box**、Position Mode **Volume**，Center `(0,0,0)`、Size `(20, 10, 0.5)`
- 刪掉 **Set Velocity from Direction & Speed**

**筆尖：Update Particle**
- 刪掉 **Multiply Color Over Life**、**Gravity**、**Linear Drag**
- 加 **Turbulence**，沿用 01 的數值：Intensity 1.3 / Drag 1 / Frequency 0.2 / Octaves 2，**放在 Trigger Event 上面**
- Trigger Event（Over Time）：Rate 60 → **12**

**筆尖：Output（Heads Quad）**
- 整個 Context 刪掉（筆尖隱藏；沒有 Output 的系統照樣會模擬）

**墨跡：Initialize Particle Strip**
- Strip Capacity **500**、Particle Per Strip Count **60**；Bounds Mode **Manual**，同上
- 刪掉 **Inherit Source Color** 與 **Inherit Source Alpha**：筆尖已不存顏色，繼承到的是 0（黑且透明），Additive 下整條線隱形；顏色改由 Output 決定
- 其餘 Inherit（Position、Size、Lifetime、Age）不動
- 刪掉 Heads Quad 後 Console 可能出現 `Remove 1 owners that couldnt be deserialized`，是被刪 Context 的殘留參照，存檔後消失，無害

**墨跡：Output（Strip Quad）**
- Blend Mode **Additive**
- **Multiply Size**（Sample Mode Custom）：它的 Sample Time 接著一串運算（`index ÷ (count − 1)`），是「在這條線上的位置」0（線尾）→ 1（筆尖），所以線會從尾巴收細。曲線終點 0.5 → **1**
- 複製一份 **Multiply Color Over Life**，新的那份：
  - Sample Mode **Custom**，Sample Time 接**同一個運算結果**（從 Size 那條線的源頭再拉一條出來）
  - **Color Mode 改成 Color**：複製來的那份沿用範本的 Alpha（只套 alpha），結果顏色沒套上、只剩白色，而且它的 alpha 會 Overwrite 掉 Over Life 的淡出，線到期時「啪」一下整條消失。改成 Color 後兩份分工：一份管顏色、一份管淡出
  - 漸層：深藍（線尾）→ 淡青 → 白（筆尖），HDR Intensity 適度
- 原本那份（Over Life，Color Mode Alpha）保留：整條線在生命後半段一起淡出
- HDR 注意：RGB 三個值都 > 1 會被截成純白，想保留色相就讓某個分量維持低值，或在 Volume 加 **Tonemapping（Neutral）** 柔和壓回
- SubpixelAA 保留：線細於一個像素時補償，避免細線閃爍

## 小實驗

- **彗星尾巴**：改成固定長度、跟著筆尖移動的尾巴。墨跡不繼承壽命、改用自己的短壽命，但必須確保「墨跡不比筆尖活得久」，否則筆尖位置重用時會拉出直線。要用運算節點：`Lifetime = min(尾巴秒數, 筆尖剩餘壽命)`

## 我的數值與筆記

- 線條數 **1000** × 每條點數 **100**（墨跡 Capacity 100000）；筆尖 Spawn Rate **200**、Lifetime 3 ~ 5、Trigger Rate **20**（20 × 5 = 100，剛好填滿）
- Turbulence：Intensity 1.3 / Drag 1 / Frequency 0.2 / Octaves 2（沿用 01）
- 線寬：筆尖 Size 0.04 ~ 0.07 × 沿線曲線 0 → 0.5
- 顏色（沿線，Color Mode Color）：深藍 `(0.13, 0.14, 0.53)` @37% → 淡青 HDR `(0.37, 0.89, 1.24)` @70% → 近白 HDR `(1.07, 1.2, 1.5)` @100%
- 淡出（Over Life，Color Mode Alpha）：alpha 1 → 1 @51% → 0
- Bloom：Threshold 0.8 / Intensity 6，未加 Tonemapping
- 觀察：
  - 筆尖刪掉顏色後，墨跡 Inherit Source Color / Alpha 繼承到 0，Additive 下線條隱形（Scene 視窗只看得到選取外框）
  - 複製 Block 會連設定一起複製：Color Mode、Composition 都要檢查。同一屬性多個 Block 時，Overwrite 會蓋掉前面的結果
  - 顏色全白的根本原因是 Color Mode 只套 Alpha，不是 HDR 截斷；排查時先確認 Block 的模式，再懷疑數值
