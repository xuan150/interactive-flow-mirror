# Sketch 03: Vortex

**目標**：滑鼠假人捲動線條，每個人周圍的線被扭成漩渦。
**架構位置**：輸入層＋人物狀態層＋渲染層（第一次跨層）。
**前置**：02b
**參考**：[lines-vortex-orbit](../refs/lines-vortex-orbit.png)、[person-silhouette-rim](../refs/person-silhouette-rim.png)

## 概念：資料從 C# 流進 VFX

照 [ADR 0001](../adr/0001-visuals-read-person-buffer-and-id-mask.md) 的單向資料流，VFX 只讀人物 buffer，不管人從哪來：

```
MousePersonSource（輸入層）→ PersonTracker（人物狀態）→ GraphicsBuffer → LineVortex VFX
滑鼠新增／拖曳／刪除          人物清單、算速度、每幀上傳     Person[8]        依每個人扭轉線條
```

ADR 的另一個輸入 ID 遮罩，到 Sketch 05 才用。

| 新觀念 | 作用 |
|---|---|
| MonoBehaviour | 掛在物件上的 C# 腳本，Unity 每幀呼叫 Update |
| Input System | 讀滑鼠鍵盤 |
| GraphicsBuffer | GPU 上的陣列，C# 寫、VFX 讀 |
| Exposed Property | VFX 對外開放的插座，C# 透過名字把資料交進去：`Persons`、`PersonCount` |
| `[VFXType]` struct | 讓 VFX Graph 認得 C# 的資料格式；欄位順序就是 GPU 上的排列 |
| Custom HLSL | graph 裡寫一小段 shader 程式；要對每個人跑迴圈加總漩渦，節點做不到 |

## 決定

- 漩渦：靜態扭轉＋緩慢擺動（離人越近轉越多，像排水口螺旋；角度隨時間來回擺，不會越捲越緊）。「漩渦強度跟速度連動」放點子池
- 最多 8 人（buffer 大小固定）
- 操作：左鍵點空白新增（並直接開始拖曳）、左鍵拖曳移動、右鍵刪除；判定半徑 0.6，重疊時取離滑鼠最近的；沒點到人就什麼都不做（不跳警告）；滑鼠靠近時標記變亮，按之前就知道會作用在誰
- 標記：03 用 Gizmos 細圓圈（暫時；Game 視窗要開 Gizmos 才看得到），③ 起加「漩渦中心亮起」，05 換成黑色剪影
- C# 由助教寫、逐段解說
- ② 先做「人附近的線往上鼓起」只為驗證資料有傳到，③ 才改扭轉：一次只驗證一件事

## 步驟

### 0. 場景與 VFX

1. 複製 `Sketch_02_lineField` 場景，改名 `Sketch_03_vortex`，放進同名資料夾並打開；Global Volume 的 Profile 按 **Clone**
2. `_Project/VFX/LineField.vfx` 按 Ctrl+D 複製，改名 `LineVortex`；場景裡的 LineField 物件改名 `LineVortex`，Inspector 的 Visual Effect → Asset Template 換成 `LineVortex`（這樣 03 怎麼改都不會動到 02b）

### ① 假人

1. 腳本在 `Assets/_Project/Scripts/`：`Person.cs`、`PersonTracker.cs`、`MousePersonSource.cs`
2. Hierarchy 右鍵 → Create Empty，命名 `People`，Position `(0,0,0)`
3. 把 `MousePersonSource` 拖到 `People` 上（它宣告需要 `PersonTracker`，會自動一起加上）
4. PersonTracker 的 **Targets** 欄位：加一格，拖入 `LineVortex` 物件
5. MousePersonSource 的 **Camera** 留空會自動用 Main Camera
6. Game 視窗右上角打開 **Gizmos**
7. Play：左鍵點空白處出現圓圈並可直接拖；左鍵拖曳既有的圓圈；右鍵點圓圈刪除；滑鼠靠近時圓圈變亮；最多 8 個

此時線條還不會有反應，因為 VFX 還沒接收資料；Console 不該有錯誤。

> Console 可能出現 `ArgumentException: Context does not exist`（堆疊全在 `VFXViewWindow`）：VFX Graph 編輯器檢查「Strip Index 接了運算」時，graph 還沒編譯好就去查屬性表。只在 graph 視窗開著時發生、不影響效果；graph 裡 Ctrl+S 或關掉重開視窗即可。

### ② 資料傳進 VFX（先用鼓起驗證）

只拿第 0 個人做測試：人附近的線往上鼓起。看到鼓起跟著滑鼠走＝資料有傳到。

```
距離 = |這個點的原位 − 第 0 個人的位置|
鼓起 = (1 − Smoothstep(0, 1.5, 距離)) × 0.8 × min(PersonCount, 1)
y    = （原本的 y）＋ 鼓起
```

`min(PersonCount, 1)`：沒有人時是 0。buffer 裡沒人時第 0 格是舊資料或 (0,0)，不乘這個會在畫面中央憑空鼓起。

1. 打開 `LineVortex` graph。左側 **Blackboard** 按 **+** → **Graphics Buffer**，命名 `Persons`；再按 **+** → **Int**，命名 `PersonCount`。兩個都要勾 **Exposed**（名字要和 C# 一字不差）
   - ⚠ 兩個都要建在 **Properties**（整個特效共用一個值，C# 傳進來），不是 **Attributes / Custom Attribute**（每顆粒子各存一份，C# 看不到）。建錯會出現 `Value of name 'PersonCount' was not found`
2. 把 `Persons` 從 Blackboard 拖進 graph。Create Node → **Sample Graphics Buffer**，點節點上的齒輪把型別設為 **Person**；Buffer ← `Persons`、Index **0**；展開輸出 **s** 會看到 position、velocity…
3. Create Node → **Distance**：展開 a 成 x / y，x ← x 的 Lerp、y ← y 的 Lerp（原位，不含起伏）；b ← s 的 **position**
4. **Smoothstep**（x 0、y 1.5、s ← Distance）→ **One Minus** → **Multiply**（b 0.8）
5. 把 `PersonCount` 拖進 graph → **Minimum**（b 1）→ 再一個 **Multiply**：a ← 上一步、b ← Minimum
6. 新的 **Add**：a ← 原本接到 Position.y 的那個 Add 輸出、b ← 上一步；輸出接到 **Position.y**

Play：點一個人，他周圍的線鼓起來、跟著拖曳移動；刪掉後鼓起消失。

### ③ 扭轉（Custom HLSL）

要對**每個人**算一次漩渦再疊起來，需要迴圈，節點做不到 → 用 Custom HLSL Block，程式在 `Assets/_Project/VFX/Vortex.hlsl`：

```
對每個人 i：
  w     = (1 − Smoothstep(0, 半徑, 距離))²     ← 熟悉的「柔和隆起」配方，平方讓中心轉得多、邊緣收得柔
  角度  = 最大角 × w × 擺動（60% ~ 100%，每人相位不同）
  把這個點繞著人轉「角度」
  光暈 += w
```

位置每幀先由 Set Position 從原位重算，再被扭轉 → 不會越捲越緊，人離開就恢復。

> ⚠ shader 編譯失敗時（Console：`Kernel at index (0) is invalid`），D3D12 下 Unity 可能直接閃退。接 HLSL 前先關掉 graph 工具列的 **Auto Compile**，全部接好再手動 Compile／存檔；`vortexGlow` 一定要**先**建好，HLSL 寫到它，不存在就編譯失敗。
> 寫屬性要寫整個：`attributes.position = float3(...)`。VFX 只把 `attributes.xxx =` 或單一字母 swizzle（`.x`）認成「寫入」，`attributes.position.xy = p` 會被當成唯讀而默默丟掉（症狀：光暈有、扭轉沒有）。
> HLSL 裡的 buffer 型別寫 `StructuredBuffer<Person>`：VFX 依 C# `[VFXType]` 的**類別名稱**自動產生 `Person` struct，自己再宣告同名或別名 struct 都會編譯失敗。

1. 拔掉 ② 的鼓起：三輸入 Add 的 **c** 斷開（鼓起只是驗證用）
2. Blackboard **Attributes** → **+** → Custom Attribute，型別 **float**，命名 `vortexGlow`（這次是每個點各自的光暈，所以**是** Attribute）
3. **Update Particle Strip** 裡、**Set Position 下面**加 Block → **Custom HLSL**
   - 選取 Block，Inspector 的 **Shader File** 欄位拖入 `Vortex.hlsl`（取代內嵌的範例程式碼）；Block 上的 **Available Function** 選 **Vortex**
   - persons ← `Persons`、count ← `PersonCount`、time ← Total Time
   - radius **2.5**、maxAngle **2.5**、swayPeriod **6**
4. **Render Strip（Output）** 加 **Multiply Color**：Get Attribute `vortexGlow` → Multiply（b **3**）→ Add（b **1**）→ 接到 Color（離人越近越亮，沒人時 ×1 不變）

Play：每個人周圍的線被捲成螺旋，中心發亮；拖曳時漩渦跟著走；多放幾個人，靠近時兩個漩渦互相干涉。

### ③+ 吸入式漩渦（v2）

v1 的問題：先起伏、再扭轉，扭的是已經在晃的線；起伏振幅（±1）比漩渦半徑（2.5）不小，螺旋時清楚時散掉，和待機打架。

**設計原則：對比。** 沒人時安靜、人帶來擾動。待機太吵，人的效果就只是「另一種吵」。
→ 待機起伏降到約 ±0.3；待機的生命感交給流光與局部遮罩。大起伏留給「人帶來的擾動」（06 痕跡）。

v2 把起伏也交給 HLSL，順序改成：

```
第一輪：用原位算各漩渦的影響，加總 = claim
位置 = 原位 + 起伏 × (1 − 0.8 × claim)     ← 漩渦內起伏剩 20%，穩但不死
第二輪（每個人）：
  往人收縮  offset × (1 − pull × w)        ← 被吸過去
  扭轉角    = maxAngle × w × (0.85 ± 0.15 × sin(距離×4 + 時間×flowSpeed))
                                           ← 強弱沿半徑往內傳：螺旋臂像被吸進去，形狀不散
```

1. Custom HLSL Block 會多出 **rest**、**wave**、**pull**、**flowSpeed**（swayPeriod 移除）
2. **rest**（展開 x / y）← x 的 Lerp、y 的 Lerp
3. **wave** ← 「起伏 noise × 遮罩」那個 Multiply 的輸出
4. **Set Position 刪掉**（位置全由 HLSL 寫入；原本接它的三輸入 Add 也可刪）
5. 數值：radius 2.5、maxAngle 2.5、pull **0.35**、flowSpeed **3**
6. 待機調安靜：起伏 noise 的 range 改成約 `(-0.3, 0.3)`

### ③++ 光流進中心（v3）

v2 的「往內流」其實是扭轉強度一緊一鬆，看起來像把線擰在一起。**根本限制：錨定的線只能在原位附近被推歪，不可能真的流進中心。**
所以 v3 讓螺旋**形狀固定**，流動交給**光**：亮帶沿著螺旋臂往中心收（和 02b 流光同一招，方向改成往內）。要「真的有東西掉進去」再疊粒子層（點子池：發光細絲）。

亮度也改由 HLSL 寫進 `color`：Output 的漸層 Block 都是 Multiply，會自動乘上去，所以 Output **不用另外接光暈**，範圍外 ×1 不變、邊緣平滑。

```
亮度 = 1 + Σ w × (glow + streak × 亮帶)
亮帶 = (0.5 + 0.5 sin(距離/間距 + 時間×速度))^8     ← ^8 讓每條亮帶變細
```

1. 刪掉 Output 的第三個漸層 Block（光暈用的那個）和接它的 Get `vortexGlow` → Multiply → Add；Blackboard 的 `vortexGlow` 也可刪
2. HLSL Block 輸入改為：glow **0.6**、streak **2**、streakSpacing **1.2**、streakSpeed **0.6**（flowSpeed 移除）

> v3 的光「看起來沒效果」不是管線壞掉：glow 暫時改 20 立刻變亮，只是 0.6 太弱、範圍又只在人周圍一小圈。

### ③+++ 黑洞核心（v4）

使用者的判斷：中心要**變暗、吞掉線**，光流進去才像被吃掉；也呼應「人是黑色剪影」（05）。

第一版「越近越暗、到中心才是 0」不夠黑：暗區和光暈最強的地方重疊，亮度 (1 + glow × w) 把暗抵消掉，加上 Bloom 把周圍的光暈進洞裡。
改成**實心黑盤＋外圈漸變**，光暈的峰值被推到黑盤外緣，自然成為一圈亮環（像吸積盤圍著事件視界）：

```
hole  = Π smoothstep(coreRadius, coreRadius + coreSoftness, 距離)   ← 每人相乘，重疊的兩個洞都保持黑
亮度 ×= hole
```

1. 確認 graph 的 **Auto Compile** 是關的，存好 `Vortex.hlsl` 後回 Unity，HLSL Block 會多出 **coreRadius**、**coreSoftness**
2. 填值後手動 Compile、存檔。所有欄位滑鼠停著都有 tooltip（寫在 HLSL 參數上方的 `/// 參數: 說明`）
3. 螺旋折角：每條線 100 點 → **300**：Capacity 4000 → **12000**、Particle Per Strip Count **300**（Strip Capacity 維持 40）、Burst Count **12000**、兩個 Divide 的 b 改 **300** / **299**
4. 還不夠黑時：Volume 的 Bloom scatter 0.7 → 約 0.4（光暈收緊，不會填進洞裡）

另外 `PersonTracker.MaxPersons` 改成 `const 8`：buffer 只在 OnEnable 依當時的值開一次，Play 中途改大會 `SetData ... 208 bytes`（= 4 人 × 52 bytes）。

### ④ 漩渦慢慢成形（延後）

人出現時強度 0 → 1，線條逐漸被捲進去；離開時慢慢放開。會改到 `Person`（加 strength）、HLSL、PersonTracker。
03 先停在 v4，這步留到 06（離開留痕）或 Main 一起做：「離開時慢慢放開」和痕跡淡出是同一件事。

## 交接（2026-10-22，03 結束）

**目前狀態**：03 完成到 ③+++ v4。滑鼠假人（最多 8）→ GraphicsBuffer → `Vortex.hlsl`：吸入＋扭轉成固定螺旋、亮帶沿螺旋臂流進中心、中心實心黑盤＋外圈亮環。檔名實際是 `LineVotex.vfx`、資料夾 `Sketch_03_votex`（少了 r）；場景檔已在 04 時改名成 `Sketch_03_vortex`。

**沒做／未確認**
- ④ 強度淡入淡出：延後（見上）
- 待機起伏 range：graph 裡有一個 noise range 已是 (-0.3, 0.3)，但沒確認它就是起伏用的那個
- 黑洞若還是不夠「被吞掉」：疊一層真的往中心掉的粒子（點子池：發光細絲）

**溝通備忘**：使用者的 Output 用「用值查漸層」配方（值接漸層 Sample Time），兩個漸層 Block 都是 Composition Multiply、Color Mode Color；Update 寫進 `color` 的亮度會被乘上去。改 Output 前先讀 .vfx 確認。

**給 04 Ripple 的接點**（新對話開始時先討論，不要直接照做）
- 位置現在**全由 `Vortex.hlsl` 寫入**（Set Position 已刪）。漣漪高度要嘛當成 HLSL 的新輸入（和 `wave` 一樣加在 y），要嘛在 HLSL Block 後面再加一個 Add Position
- 漣漪的波源是「進場」與「移動」：PersonTracker 已有 Add / Move / velocity，可以從這裡把事件交給漣漪場
- ROADMAP 寫 04 可獨立先做：可以從 02b 場景複製，先只用滑鼠點擊當波源，驗證波動方程後再接 03 的人

## 小實驗

- 判定半徑 `Pick Radius`（MousePersonSource）、速度平滑 `Velocity Smoothing`（PersonTracker）

## 我的數值與筆記

- 漩渦半徑 radius 2.5、最大扭轉角 maxAngle 4、吸入 pull 0.35
- 光：glow 20、streak 2、streakSpacing 1.2、streakSpeed 0.6
- 黑洞：coreRadius 0.3、coreSoftness 0.8
- 每條線 300 點、40 條
- 觀察：錨定的線不可能真的流進中心，「被吸進去」要靠光往內流＋中心變黑；暗區要是實心的，漸暗會被光暈抵消
