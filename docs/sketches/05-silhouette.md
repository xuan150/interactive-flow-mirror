# Sketch 05: Silhouette

**目標**：每個人是一個黑色人形剪影，線條繞著身體讓開、擠在輪廓上，邊緣最亮；走得越快線條被推得越開。
**架構位置**：輸入層（ID 遮罩蓋印）＋渲染層。
**前置**：03（04 的漣漪保留）
**參考**：[person-silhouette-rim](../refs/person-silhouette-rim.png)、[lines-ridge-bump](../refs/lines-ridge-bump.png)

## 概念：一張遮罩回答「這裡有誰」

照 [ADR 0001](../adr/0001-visuals-read-person-buffer-and-id-mask.md)，視覺層除了人物 buffer，只再讀一張 **ID 遮罩**：每個像素存「人的 index + 1」，0 = 沒人。之後換成 webcam，只是換一個產生這張遮罩的來源。

```
MousePersonSource → PersonTracker → SilhouetteMask（C#）→ Silhouette.compute → SilhouetteMask RT → Silhouette.hlsl
滑鼠假人            人的位置          每幀蓋印                每個像素查「誰的身體」＋模糊   RG = 身體、BA = 模糊的身體   線條讓開、變黑、輪廓發光
```

| 新觀念 | 作用 |
|---|---|
| 蓋印（stamp） | 把剪影圖貼到每個人的位置；compute shader 對每個像素問「我在誰的剪影裡」 |
| 模糊（Blur） | 兩趟高斯模糊（先橫再直）把身體往外暈開一圈 → **柔和身體**：越靠近身體越接近 1，給線條「快碰到人了」的提示 |
| 法線 | 上下左右各取一點，看哪邊「身體比較多」，反方向就是「往輪廓外」 |

黑色剪影不用另外畫：背景本來就是黑的，身體裡的線亮度乘 0 就是剪影。

## 決定

- 剪影圖：使用者提供站姿、透明背景的 PNG（認得出是人；之後 webcam 也是「一張遮罩」）
- 人高 **6** 單位（畫面高 10），滑鼠點的是**身體中心**
- 03 的漩渦在 05 全部關掉（只改數值），不影響剪影的判斷；漩渦的角色在組合 Main 前討論
- 04 的漣漪保留
- 動作語彙「快走 → 推得更開」在 05 做：用遮罩的 index 查那個人的速度
- 新的 HLSL Block 接在 Vortex 後面，`Vortex.hlsl` 不動
- 畫面範圍 20×10 收成 `PersonTracker.Area`（C# 共用）；兩個 HLSL 仍寫死，改要一起改
- 03 的 Gizmos 圓圈拿掉（剪影取代）

## 步驟

### 0. 場景與 VFX

1. 複製 `Sketch_04_ripple` 場景，改名 `Sketch_05_silhouette`，放進同名資料夾並打開；Global Volume 的 Profile 按 **Clone**
2. `_Project/VFX/LineRipple.vfx` 按 Ctrl+D 複製，改名 `LineSilhouette`；場景裡的 LineRipple 物件改名 `LineSilhouette`，Visual Effect → Asset Template 換成 `LineSilhouette`
3. 確認 `People` 上 PersonTracker、RippleField 的 **Targets** 指向 `LineSilhouette` 物件
4. 打開 `LineSilhouette` graph（看視窗標籤！），Vortex Block 關掉漩渦：
   - maxAngle **0**、pull **0**、glow **0**、streak **0**、coreRadius **0**、coreSoftness **0**
   - radius **0.01**（radius 也決定「漩渦內起伏壓到 20%」的範圍；不能填 0，smoothstep 會除以 0）
5. Compile、存檔。Play：點人只剩漣漪，沒有螺旋和黑洞

### ① ID 遮罩（先看小窗）

1. 剪影 PNG 放到 `Assets/_Project/Textures/Silhouette.png`（新資料夾）。Inspector：**Alpha Is Transparency** 勾起來、Apply
   - 圖要是**透明背景**：程式看 alpha，> 0.5 算身體。上下左右留白越少越好（留白也算進高度）
2. 程式在 `Assets/_Project/Shaders/Silhouette.compute`、`Assets/_Project/Scripts/SilhouetteMask.cs`
3. 把 `SilhouetteMask` 拖到 `People` 上；**Shader** ← `Silhouette.compute`、**Silhouette** ← PNG；Targets 先留空
4. RippleField 的 **Show Debug** 取消勾選（兩個小窗疊在同一個位置）
5. Play：點空白新增人 → 左上小窗出現黃色人形，周圍一圈淡淡的模糊；拖曳時跟著走

> 小窗上下顛倒是 GUI 顯示的關係（04 一樣），② 接上線條後看實際位置。
> 判定半徑從身體**中心**算：要抓人請點肚子附近。抓不到可以把 MousePersonSource 的 **Pick Radius** 調大（例如 1.5）。

### ② 身體變黑、輪廓發光

`Silhouette.hlsl` 讀遮罩：

```
柔和身體 = 遮罩的 A（模糊後的覆蓋率）       ← 越靠近身體越接近 1
亮度    ×= (1 + rimGlow × 柔和身體) × (1 − 身體內？)
```

1. 確認工具列 **Auto Compile** 是關的
2. Blackboard **Properties** → **+** → **Texture2D**，命名 `SilhouetteMask`，勾 **Exposed**
3. **Update Particle Strip** 裡、**Vortex Block 下面**加 Block → **Custom HLSL**；Shader File ← `Silhouette.hlsl`，Function 選 **Silhouette**
   - mask ← `SilhouetteMask`、persons ← `Persons`、count ← `PersonCount`
   - push **0**、speedPush **0**、rimGlow **30**（10 還看不太出來；03 的 glow 也要 20）
4. 手動 Compile、存檔
5. `People` 的 SilhouetteMask → **Targets** 加一格，拖入 `LineSilhouette`

Play：人的位置出現黑色人形，線條在身體邊緣斷開，輪廓附近變亮。

### ③ 線條讓開

push 改 **0.8**：身體裡的點沿法線被擠到輪廓外，推的距離 = push × 柔和身體²（越深推越遠），所以線在輪廓上最擠、往外慢慢恢復。

- **push**：擠多遠（世界單位）。**不要超過 Softness**：超過時相鄰的點會互相超車，線變鋸齒
- **Softness**（SilhouetteMask，世界單位）：模糊多寬。越大線條越早開始彎、彎得越緩；越小越貼著身體
- 手腳中央「往外」會左右翻面，點被分到兩側、中間連出一條橫跨的線 → 深處且斜率小的點直接變暗

### ④ 走得快 → 推得更開

speedPush 改 **0.5**：走路速度（約 7 單位／秒）以上推力變 1.5 倍，停下來就收回。速度有上限，甩得再快也不會更大。

```
誰 = round(B ÷ A) − 1          ← 模糊後的 B 是 index+1 的平均，除以覆蓋率 = 那個人的 index+1
推力 = push × (1 + speedPush × min(速度 ÷ 7, 1))
```

## 我的數值與筆記

- ⚠ 第一版用 mipmap 當柔和身體（`GenerateMips`），結果高層 mip 是空的：剪影有黑、但推開和發光完全沒反應（D3D12 下 compute 寫入的 RT 似乎產生不了 mip）。改成 compute 第二個 kernel 自己模糊，寬度直接用世界單位（Softness）
- ⚠ 第二版（x、y 都推＋跳格取樣的模糊）：線變成鋸齒、像籠子罩在人身上。水平線上的點被左右推超過點距（約 0.07）就前後錯位、來回折返；跳格取樣讓斜率有顆粒。改成**只推上下**＋兩趟高斯模糊
- ⚠ 第二版拖曳時剪影變肥：滑鼠速度可達 20 單位／秒，speedPush × 速度沒上限，大片線被推空。改成速度 ÷ 7 再封頂 1
- 發光：rimGlow 2 看不出來（和 03 glow 0.6 同樣問題），起手改 10
- 第三版只推上下：頭頂隆起、腳底讓開，但身體裡的線推不出來，只是被遮住（推力 = 斜率，輪廓上最大、身體內反而小）。使用者要的是「完全被擠出、輪廓最擠、越往外越恢復」→ 第四版沿法線推，推力 = push × 柔和身體²
- 發光 rimGlow 30 才明顯

**停在這裡的數值**（場景與 graph 現況）
- SilhouetteMask：Height **6**、Softness **1**；MousePersonSource：Pick Radius **1.2**
- Silhouette Block：push **0.8**、speedPush **0.5**、rimGlow **23**
- Vortex Block：漩渦全關（maxAngle、pull、glow、streak、coreRadius、coreSoftness 0，radius 0.01）

## 交接（2026-10-22，05 暫停）

**目前狀態**：剪影、ID 遮罩、輪廓發光都有作用；「線條被完全擠出、繞著輪廓最擠、往外漸回」**未達預期**，使用者決定先停（「再改也改不太好」），往 06 前進。程式停在第四版（沿法線擠出，推力 = push × 柔和身體²）。

**沒做／未確認**（依優先）
1. 擠出的樣子不到位。根本限制和 03 一樣：**錨定的線只能在原位附近被推歪**。身體寬約 2 單位，要把整段線擠到輪廓外得推 1 單位以上，比 Softness 大就會互相超車變鋸齒。可能方向：
   - 真的距離場（Jump Flooding）取代模糊當「離輪廓多遠」，推的距離可以精確到「剛好出輪廓」
   - 不推點，改推**線**：每條線在人附近整條往上／下繞過（只動 y，永遠不會鋸齒），像 Unknown Pleasures 的隆起
   - 接受現況：身體內靠變黑、輪廓靠發光，擁擠感交給 Bloom
2. 手腳中央的「深處變暗」門檻寫死給 Softness ≈ 1（`Silhouette.hlsl` 的 `ponytail:` 註解）
3. 「甩動」沒做：現在只有走得快 → 推得遠
4. 黑洞與剪影的分工：05 把漩渦整個關掉了，組合 Main 前討論（ROADMAP）

**給 06 Exchange 的接點**（新對話開始時先討論，不要直接照做）
- ID 遮罩已可用：`SilhouetteMask` 的 B ÷ A ＝ 附近那個人的 index + 1（`Silhouette.hlsl` 已示範查人物 buffer），06 依此取 `colorA / colorB` 上色
- 痕跡場可照抄 04 的 ping-pong compute 模式（`RippleField`）
- 畫面範圍 C# 端用 `PersonTracker.Area`；HLSL 仍寫死 20×10（`Vortex.hlsl`、`Silhouette.hlsl`）
- 坑：D3D12 下 compute 寫的 RT 用 `GenerateMips` 似乎得到空 mip，要模糊就自己寫 kernel
