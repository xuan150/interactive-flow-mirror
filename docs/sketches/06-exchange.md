# Sketch 06: Exchange

**目標**：兩人靠近時互相帶走對方的顏色（漸層互滲、分開後殘留再慢慢退）；人走過留下會沉澱淡出的痕跡。
**架構位置**：人物狀態層（顏色交換）＋場（痕跡場）＋渲染層。
**前置**：03、05

## 概念：本色與帶著的顏色

`Person` 有兩個顏色（[ADR 0001](../adr/0001-visuals-read-person-buffer-and-id-mask.md)）：

| | 是什麼 | 誰改它 |
|---|---|---|
| colorA 本色 | 進場時從調色盤分到的身分色 | 永遠不變 |
| colorB 帶著的顏色 | 畫面上畫的顏色，進場時 = 本色 | `ColorExchange` 每幀更新 |

需要兩個值，是因為被染過之後要知道「退回」到哪裡。

```
每幀，每個人的 B 同時被兩股力拉：
  往附近每個人的 B 靠，越近越快（身體空隙超過 Exchange Gap 為 0）   ← 用 B 不是 A：顏色會接力傳下去
  往自己的 A 退，很慢（Return Rate）
```

兩人靠在一起會往同一個中間色收斂，所以「最多染一半」不用另外寫限制。

**空間漸層**（HLSL）：光看 B 只會覺得「兩人都變色了」，看不出互滲。輪廓上的每個點再看自己離別人的**身體**多近，面向對方的那一側染上對方的 B，貼在一起時最多一半。分開後空間漸層立刻消失，留下 B 的殘留慢慢退。

## 決定

- colorA＝本色、colorB＝帶著的顏色；交換只改 B
- 接力：附近的人的顏色用對方的 **B**
- 殘留慢慢退回本色（約一分鐘）
- 顏色先只畫在**輪廓光**，身體維持黑色剪影
- 痕跡只帶顏色和亮度，不推線
- 漩渦強度淡入**不做**（使用者：漩渦好像不太適合這次）
- 加 asmdef 才能寫 EditMode 測試：`Scripts/FlowMirror.asmdef`、`Tests/EditMode/FlowMirror.Tests.EditMode.asmdef`

## 步驟

### 0. 場景與 VFX

1. 複製 `Sketch_05_silhouette` 場景 → `Sketch_06_exchange`（同名資料夾），Global Volume Profile 按 **Clone**
2. `LineSilhouette.vfx` Ctrl+D → `LineExchange`；場景物件改名、Asset Template 換掉
3. `People` 上 PersonTracker、RippleField、SilhouetteMask 的 **Targets** 指向 `LineExchange`

### ① 顏色交換（C#）

`ColorExchange.Step`（純函式，EditMode 測試 4 個）接在 `PersonTracker.LateUpdate` 算完速度之後。Inspector：

- **Exchange Gap**：兩個身體之間的空隙多近開始互染（身體同 ③ 的膠囊，和 seepRadius 同義）
- **Exchange Rate**：貼在一起時每秒染多快。調慢才看得到過程
- **Return Rate**：每秒退回本色多快

### ② 輪廓光用人的顏色

Output 的兩個漸層 Block 是 **Multiply**，第一個深藍→深紫，紅色通道只有 0.03～0.2：人的顏色乘進去會被吃光。所以輪廓光改用**加**的：

1. Blackboard **+** → **Attribute**，命名 `glow`（**小寫**），型別 **Vector3**
2. **Output Particle Strip** 最底下加 **Set Color**，Composition 改 **Add**，輸入接 Get Attribute `glow`。一定要在兩個漸層 Block **下面**
3. `Silhouette.hlsl` 把輪廓光寫進 `attributes.glow`，`color` 只負責身體內變黑

### ③ 空間漸層（互滲）

Silhouette Block 多一個輸入 **seepRadius**：輪廓離對方**身體邊緣**多近才開始染。身體當成膠囊（中心上下各 2、半徑 1 ＝ 6 高 2 寬）。

### ④ 痕跡場（沒做）

06 暫停時決定先不做，移到 [ROADMAP 點子池](../ROADMAP.md#點子池)，當作最終樣貌腦力激盪的素材。要做時的提示：照抄 04 `RippleField` 的 ping-pong 模式，人走過塗上 colorB；線條取樣後加進 `glow`（不要用乘的，理由同 ②）。

## 我的數值與筆記

- ⚠ 輪廓光第一版用乘的：顏色被藍紫漸層吃掉，只看得到一點偏色 → 改成自訂屬性 `glow` 加在最後
- ⚠ **自訂屬性名稱分大小寫**：HLSL 的 `attributes.glow` 和 Blackboard 名稱差一個大寫，Update 的 compute shader 就編譯失敗
- ⚠ **自訂屬性 graph 裡沒人讀，VFX 會把它拿掉**：停用 Set Color（Add）後 HLSL 一樣找不到 `glow`
- ⚠ 上面兩種失敗的樣子都是**整個畫面全黑**（粒子還在，但 Update 沒跑，全部擠在原點），Console 只有一句 `.compute: Kernel at index (0) is invalid`，graph 上的紅色驚嘆號一點就消失。真正的錯誤要用 `ShaderUtil.GetComputeShaderMessages` 讀 `.vfx` 底下的 ComputeShader 子資源（臨時 editor 選單腳本，用完刪掉）
- ⚠ seepRadius 第一版量對方**中心**：人是 6 高的長條，還沒碰到就被染 → 改量到身體膠囊的距離
- 調色盤偏淡，乘上 rimGlow 加 Bloom 後偏白；互補色（橘＋青）平均會變灰。高飽和調色盤還沒試
- Exchange Rate 從 1 調到 0.3 才看得到換色的過程
- Exchange Radius（量中心距離）統一成 Exchange Gap（量身體空隙，同 seepRadius），整身換色和輪廓光互滲同一刻開始

**停在這裡的數值**
- PersonTracker：Exchange Gap **1.5**、Exchange Rate **0.3**、Return Rate **0.05**
- Silhouette Block：push **0.8**、speedPush **0.5**、rimGlow **10**、seepRadius **1.5**

## 交接（2026-10-27，06 暫停）

**目前狀態**：顏色交換（C# ＋ 測試）、彩色輪廓光、空間漸層都有作用，使用者覺得「目前可以了」。整體效果還不滿意，先停下實作，**開新對話**腦力激盪最終樣貌（視覺怎麼更豐富、華麗），再組合 Main。痕跡場移到 ROADMAP 點子池。

**沒做／未確認**（依優先）
1. **05 的 `LineSilhouette` 壞了**：它也用 `Silhouette.hlsl`，但沒有 `glow` 屬性和 seepRadius 輸入，重新匯入就報 `invalid subscript`。選項：跟上 06 的 ②（推薦）／只加屬性（輪廓光消失）／不管
2. 高飽和調色盤（`PersonTracker.Palette`）
3. 膠囊尺寸寫死對應 SilhouetteMask Height 6，`Silhouette.hlsl` 和 `ColorExchange.cs` 各有一份（`ponytail:` 註解），要改一起改
