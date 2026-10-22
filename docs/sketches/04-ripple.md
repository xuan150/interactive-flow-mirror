# Sketch 04: Ripple

**目標**：人進場時盪開一圈漣漪、移動時拖出波紋；多個波相遇時干涉。
**架構位置**：場層（第一次有「記憶」的場）＋渲染層。
**前置**：03
**參考**：[lines-ridge-bump](../refs/lines-ridge-bump.png)

## 概念：有記憶的場

01–03 的畫面每幀從原位重算，不記得上一幀。波要往外傳，下一刻的高度得從「現在」和「上一刻」算：

```
下一刻 = 2 × 現在 − 上一刻 + C² × （四個鄰居的平均高度 − 自己）× 4
```

鄰居比自己高 → 被往上拉；這股拉扯一格傳一格，就是往外擴散的圈。

```
PersonTracker（人物狀態）→ RippleField（C#）→ Ripple.compute（GPU）→ RippleTex → LineRipple VFX
人的位置、速度              進場／移動 → 波源      每幀跑數次波動方程        高度圖      線條隨波起伏
```

| 新觀念 | 作用 |
|---|---|
| Compute Shader | 在 GPU 上對每個像素同時跑一段程式；這裡每個像素是一格水面 |
| RenderTexture | GPU 上的圖，可以被 compute shader 寫入；這張不顯示，存的是高度 |
| Ping-pong | GPU 不能邊讀邊改同一張圖 → 兩張輪流：讀 A 寫 B、讀 B 寫 A… |
| 固定時間步 | 一步跑 1/240 秒，每幀跑好幾步；步子太大波會爆掉（整片發散），所以速度有上限 |

每格存兩個數（R = 現在、G = 上一刻），所以一張圖就帶著兩幀的資訊。

## 決定

- 從 03 場景複製：左鍵新增人＝進場、拖曳＝移動，剛好是兩種波源，不另寫點擊腳本
- Compute Shader 做 ping-pong（不用 Custom Render Texture：比較黑箱）
- 解析度 480×240（Game View 的 1/4），蓋住相機可視範圍 20×10
- 邊界吸收：靠邊 16 格額外衰減，波到邊緣淡掉、不反彈（多人時才不會亂）
- 表現：線條上下位移＋波峰稍亮
- 先用 debug 小窗看灰階高度圖確認波是對的，再接進 VFX（一次只驗證一件事）

## 步驟

### 0. 場景與 VFX

1. 複製 `Sketch_03_vortex` 場景（資料夾仍是 `Sketch_03_votex`），改名 `Sketch_04_ripple`，放進同名資料夾並打開；Global Volume 的 Profile 按 **Clone**
2. `_Project/VFX/LineVotex.vfx` 按 Ctrl+D 複製，改名 `LineRipple`；場景裡的 LineVotex 物件改名 `LineRipple`，Visual Effect → Asset Template 換成 `LineRipple`
3. 確認 `People` 上 PersonTracker 的 **Targets** 指向場景裡的 `LineRipple` 物件（複製場景後通常會自動指向，看一眼就好）

### ① 漣漪場（先看高度圖）

1. 程式在 `Assets/_Project/Shaders/Ripple.compute`、`Assets/_Project/Scripts/RippleField.cs`
2. 把 `RippleField` 拖到 `People` 上
3. **Shader** 欄位拖入 `Ripple.compute`；Targets 先留空（③ 才接）
4. Play：左上角出現一個黑色小窗，就是高度圖
   - 左鍵點空白新增人 → 小窗裡從那點盪開一圈亮環
   - 放兩三個人 → 環相遇時交疊處變亮、穿過彼此繼續走
   - 拖曳 → 身後拖出一串波紋
   - 環走到小窗邊緣淡掉，不反彈

小窗只顯示波峰（亮）；平面和波谷都是黑的，這是 debug 用，不影響之後的效果。

> 小窗如果上下顛倒（在下面點、環出現在上面）是 GUI 顯示的關係，場本身沒錯，③ 接上線條後看實際位置。

調手感（都有 tooltip）：
- **Wave Speed**：環擴散的速度（世界單位／秒）。調太大會被自動壓在穩定上限
- **Decay**：每秒衰減，越大環越快消失
- **Enter Strength**、**Move Strength**：進場那一發多大、移動拖出的波紋多大
- **Source Radius**：波源大小，越大環越粗

### ② 線條隨波起伏

高度圖交給 `Vortex.hlsl`，它用每個點的**原位**查高度，加到 y（和待機起伏一樣，在漩渦內壓到 20%，螺旋才不會被震散），波峰再稍微變亮：

```
高度 = RippleTex 在（原位 ÷ (20, 10) + 0.5）的 R
y    = 原位 y + （起伏 + 高度 × rippleHeight）× （1 − 0.8 × claim）
亮度 = 1 + rippleGlow × 高度（只取正的）… 再乘漩渦的光與黑洞
```

> 03 的 `LineVotex` 共用同一個 `Vortex.hlsl`，重開它的 graph 也會多出這三格；rippleHeight、rippleGlow 是 0 就完全沒影響。
> HLSL 參數型別 `VFXSampler2D` 在 Block 上會變成一個 Texture2D 插槽。

1. 打開 `LineRipple` graph，確認工具列 **Auto Compile** 是關的（03 的教訓：編譯失敗可能閃退）
2. Blackboard **Properties** → **+** → **Texture2D**，命名 `RippleTex`，勾 **Exposed**（名字要和 C# 一字不差）
3. 回 Unity 後 HLSL Block 多出 **ripple**、**rippleHeight**、**rippleGlow**
   - ripple ← `RippleTex`
   - rippleHeight **1**、rippleGlow **1**
4. 手動 Compile、存檔
5. `People` 的 RippleField → **Targets** 加一格，拖入 `LineRipple` 物件

Play：點空白新增人，一圈波從他身上盪開、經過的線上下起伏一下、波峰微亮；拖曳時線上拖出波紋。
小窗看夠了就把 RippleField 的 **Show Debug** 取消勾選。

## 我的數值與筆記

- 波速 Wave Speed **2**（原 4，太快）、衰減 Decay **1.5**（原 0.5，人靜止後還震很久）
- 人靜止就不產生新波：只有進場和移動會打波
- 平面上的波會在環的內側留一段餘震（二維波的天性），靠 Decay 收掉
- ⚠ 曾把 Area 改成 (10, 5) 想讓波聚攏：結果波被放大兩倍、位置偏移、站在中間區塊以外的人打不出波。Area 必須等於相機範圍 20×10（HLSL 取樣也寫死 20×10），已改成程式常數、不再出現在 Inspector。要波小／細：調 **Source Radius**、**Enter / Move Strength**、graph 的 **rippleHeight**
- ⚠ ② 曾誤改到 03 的 `LineVotex` graph：打開 graph 前看視窗標籤是哪個 .vfx
- Wave Speed 超過約 8（480×240 時）會被穩定上限壓住，填再大都一樣
- 真人是從畫面邊緣走進來，「進場那一發」會落在邊界吸收區；實際漣漪主要來自**走動的波紋**。進場這發先留著當測試（見 ROADMAP「組合前要重新討論」）

**最終數值**（已設為程式預設值）
- RippleField：Resolution 480×240、Wave Speed **2**、Decay **0.8**、Source Radius **0.15**、Enter Strength **0.6**、Move Strength **0.1**
- HLSL Block：rippleHeight **1.2**、rippleGlow **4**（其餘沿用 03：radius 2.5、maxAngle 4、pull 0.35、glow 20、streak 2）
- 03 的 `LineVotex` 也多了 ripple 三格，rippleHeight、rippleGlow 為 0 → 沒影響

## 交接（2026-10-22，04 結束）

**目前狀態**：04 完成。`RippleField` 每幀跑數步波動方程（ping-pong RT），人進場打一發、移動拖出波紋；`Vortex.hlsl` 用原位查高度加到 y、波峰變亮，漩渦內壓到 20%。

**沒做／未確認**
- 進場漣漪的觸發方式（真人從邊緣走進來）→ 組合前討論，見 ROADMAP
- 點子池「幽靈訪客」「抬手」「集體共振」現在都做得到了：往 `RippleField.AddSource` 丟波源即可

**給 05 Silhouette 的接點**（新對話開始時先討論，不要直接照做）
- 「C# 產生一張 RT → `vfx.SetTexture` → HLSL 用 `VFXSampler2D` 以原位取樣」這條路 04 已經打通，05 的 ID 遮罩可照抄：`SampleTexture(tex, rest / float2(20, 10) + 0.5, 0)`（Update 是 compute，必須指定 mip 0）
- 畫面範圍 20×10 現在寫死在兩處：`RippleField.Area` 和 `Vortex.hlsl`；05 若再多一處，考慮收成一個共用值
- 照 ADR 0001，滑鼠假人要把剪影貼圖**蓋印**到 ID 遮罩（每像素 = 人的 index + 1）
- 先討論：03 的黑洞和 05 的黑色剪影會搶「黑色的人」（ROADMAP「組合前要重新討論」）。05 可能要先把黑洞關掉（coreRadius 0）再做剪影
