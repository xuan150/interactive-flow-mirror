# Sketch 07b: 看樣：生

**目標**：光絲從身體表面慢慢吐出（像蠶吐絲），纏成辮子包住暗的身體；人是光的來源（[目標畫面](../ROADMAP.md#三個身影候選)）。
**架構位置**：渲染層（`L07b_Strands.vfx` 只畫光絲；`L07b_Lines.vfx` 是背景）。
**前置**：07
**拋棄式**：`prototype/lookdev` 分支，`Scenes/Sketches/Sketch_07b_spin/`。

## 決定

- 吐絲方式：每人一個「吐絲頭」繞輪廓跑，一趟吐一條 **3 股辮子**，一趟比一趟外圈、方向交替（避免變成一條很長的絲）。剛吐的絲先飄出去，約 1 秒後躺回輪廓
- 交會時 B 還沒吐完也不加速，看半成品相遇的樣子
- 光絲要和背景**有互動**（第一版只遮掉背景，使用者：「把背景遮掉，蠶絲行為也成立」）→ 選 A＋B：
  - A 絲撐開背景：吐得越久，周圍背景線被撐開越寬、留一圈暗縫；縫的邊緣只變暗、不發亮
  - B 斷絲回到背景：斷掉／人離開留下的絲不在原地淡，而是斷成小段、躺進最近的背景線、跟著起伏、拉長淡掉
- 交會改成**搭橋**：岔絲橫跨兩人之間、在對方外層抓一小段再折回，不沿對方輪廓繞（繞的話兩人之間會圍出「第三個人」）；兩人之間的背景不撐開
- 分開時每座橋有自己的拉伸極限，一根一根斷；近半段彈回自己身上，遠半段躺進背景淡掉
- 顏色：獨處時是**自己本色的低飽和版**，交會時變高彩度（原本近乎無色 → 體驗者看不出交會的顏色從哪來）。已改進 ROADMAP 共用規則
- 外層纏太多層 → 5 趟改 3 趟（`trips`）

## 做了什麼

| 檔案 | 內容 |
|---|---|
| `Sketch_07b_spin.unity` | Main 複製；Volume Profile 換成 07b 的；`MainLines` 改名 `L07b Lines` 換成 07b 背景；新增 `L07b Strands`；`People` 的 `MousePersonSource` 停用，`PersonTracker`／`SilhouetteMask` 的 targets 指向兩個 VFX |
| `L07b Volume Profile.asset` | Main Volume Profile 複製，沒改 |
| `L07b_Lines.vfx` | MainLines 複製。Silhouette Block 換成 **Yield**（多一個 Delta Time 節點；自訂屬性 `bend`、`stayA`、`stayB`） |
| `L07b_Strands.vfx` | 從 `L07a_Lines.vfx` 複製（已有 dt 和線條接線）。Update 的 Block 換成 **Spin**；刪掉光點 Output；底色漸層改黑（光絲只靠 glow）；自訂屬性 `spun`、`torn`、`cut`、`home` |
| `L07b_Spin.hlsl` | 光絲：吐絲、辮子、搭橋與斷橋、斷絲躺進背景、顏色 |
| `L07b_Yield.hlsl` | 背景：被光絲撐開、讓路、慢慢合回 |

### 生怎麼運作

**光絲（Spin）**：120 條線 ＝ 8 個人的格子（`id % 8`）× 5 趟 × 3 股。每條線是一趟的一股，整條共用狀態：

```
spun（吐了多長）：負的 = 還在排隊；每趟晚 tripGap 秒開始；trip ≥ trips 的永遠不吐
  吐絲頭 = 剛吐出的那點，最亮（headGlow）
  每點目標 = 真輪廓（膠囊參數 → 沿法線找 SilhouetteMask）往外推：辮子 + 第幾趟 + 剛吐出的飄出 + 亂絲
torn（死了幾秒）：正 = 移動太快甩斷（snapSpeed），負 = 人離開
  死掉 → 每 1 單位一段，躺進最近的背景線（同一組 noise 算起伏），拉長、5% 淡完（snapFade／leaveFade）
  快速移動結束後重吐；人離開就重設給下一個人
cut（橋斷了幾秒）：
  橋：面向對方那段 → 跨過去、下垂、抓住對方外層一小段（每條高度不同）
  兩人分開、身體空隙 > 自己的極限（forkGap × 0.25～0.7）→ 斷
  近半段：彈回（阻尼調低，會晃）；遠半段：躺進背景淡掉；對方走出範圍後缺口 1 秒補回
```

**背景（Yield）**：每個背景點自己記每個人待了多久（`stayA/B`，每點算一樣的數），不用 C#：

```
縫寬 = gap × √(待了多久 / grow)；走動時前方多 plow；面向別人的那側縮掉
沿「身體中軸 → 點」的射線找真輪廓距離 d：
  d 在 0～3 倍縫寬：往外擠到縫外，越擠越暗（不堆亮）
  身體內：擠到縫邊、全暗
多人的推力相加（取大的會讓相鄰點左右跳 → 鋸齒線）
實際位移慢慢追上：讓路快（openTime）、合回慢（closeTime）→ 走動時前推後尾流
```

| 狀況 | 看到什麼 |
|---|---|
| 進場 | 吐絲頭繞著跑，辮子一趟一趟往外長；背景一起慢慢撐開 |
| 靜止 | 光帶沿光絲流動（flowGlow） |
| 快速移動 | 部分光絲甩斷、躺進背景線淡掉；背景前推後合 |
| 獨處 | 自己本色的低飽和版 |
| 交會 | 兩人之間一片交錯的橋，高彩度；中間保留背景線 |
| 分開 | 橋一根根斷，近端彈回、遠端躺進背景 |
| 離場 | 光絲斷成段躺進背景線淡掉，背景慢慢合回 |

### 數值

Spin Block（`L07b_Strands.vfx` → Update）：

| 值 | 是什麼 |
|---|---|
| spinTime **3** | 吐絲頭繞輪廓一圈幾秒（一趟 1～1.3 圈） |
| tripGap **1.5** | 每趟晚幾秒開始 |
| trips **3** | 每人吐幾趟（1～5），從內往外，少的是外層 |
| layers **0.35** | 第 5 趟離第 1 趟多遠 |
| braid **0.05** | 3 股辮子擺開多寬 |
| loose **1.5** | 走動時額外散開 |
| drift **0.5** | 剛吐的絲飄出多遠 |
| settle **0.4** | 光絲追上形狀幾秒（飄帶 3 倍） |
| ribbons **0.3** | 飄帶比例 |
| strays **0.15** | 線尾不躺回的比例（亂絲） |
| strandGlow **0.15** | 光絲亮度（背景約 0.02） |
| headGlow **1** | 吐絲頭亮度 |
| flowGlow **3** | 靜止時流動光帶 |
| revealGap **1.5** | 別人身體多近開始變高彩度 |
| forkShare **0.35** | 搭橋的絲比例（每個對象） |
| forkGap **2** | 身體空隙多少開始搭橋；也決定斷的範圍 |
| snapSpeed **4** | 速度超過多少開始甩斷 |
| snapFade **2.5** | 甩斷／斷橋遠端躺平淡完幾秒 |
| leaveFade **4.5** | 人離開後留下的絲淡完幾秒 |
| aloneSat **0.4** | 獨處時飽和度（0 灰、1 調色盤原色） |

Yield Block（`L07b_Lines.vfx` → Update，Vortex 之後）：gap **0.8**、grow **6**（約吐完時間的八成：3 趟約 7 秒吐完；5 趟時是 8）、plow **1**、openTime **0.25**、closeTime **1.5**。

HLSL 常數：辮子節距 `L07B_BRAID` 0.9、斷絲段長 `L07B_PIECE` 1、身體最寬 `L07B_Y_WIDE` 1.8、擠壓範圍 `L07B_Y_REACH` 3 倍縫寬、面向別人縮縫的距離 `L07B_Y_SHARE` 2（≈ forkGap）。

## 我的數值與筆記

- ⚠ **斷絲要貼得上背景線**：`L07b_Wave` 照抄 `L07b_Lines.vfx` 兩個 Noise operator（Perlin，頻率 0.38 範圍 ±0.3，乘上頻率 0.08 的 smoothstep 0.32～0.56，時間 ×1.2）。改背景起伏要兩邊一起改。Custom HLSL 可直接叫 VFX 的 `GeneratePerlinNoise(座標, 頻率, octaves, roughness, lacunarity).x`（-1～1，operator 再 fit 到 range）
- ⚠ **`ResyncSlots` 會把對不上名字的舊連線交給第一個同型別的新 slot**：Scoop 的 `_wave` 連線跑到 Spin 的 `_spinTime`。換 Block 函式後要檢查每個 slot 的連線
- ⚠ 兩人的推力「取大的」→ 相鄰點在兩人之間跳來跳去，背景線變鋸齒（看起來像高速殘影）。改成相加
- ⚠ 斷絲第一版保持身體輪廓、原地淡掉 → 像整個人的殘影。斷成段、躺平才解決
- ⚠ 交會時岔絲貼到對方輪廓 ＋ 中間背景被撐空 → 暗區被光絲圍起來，就是 07b 畫「人」的方式 → 看起來像第三個人。搭橋＋中間不撐空
- HLSL：`out` 是關鍵字不能當變數名；`int` 的 `%`、`/` 有警告，改 `uint`（負數記得先轉 float）
- HLSL 用到新的自訂屬性前，要先在 graph 加（`graph.TryAddCustomAttribute(名, VFXValueType.Float4, 說明, false, out _)`），不然 `invalid subscript`
- 新增 Delta Time 節點：`ScriptableObject.CreateInstance<VFXDynamicBuiltInParameter>()`（預設就是 Delta Time）→ `graph.AddChild` → `outputSlots[0].Link(slot)`
- 改 graph 用臨時 editor 腳本（做法見 [07a 筆記](07a-scoop.md#我的數值與筆記)），放在不 commit 的 `Assets/_Temp07b`，已刪
- 畫面靠使用者 Play 後截圖（UnitySkills 在 Play 中截圖會讓 Unity 當掉）

## 交接（2026-10-28，07b 暫停）

**目前狀態**：三輪回饋。①光絲和背景沒互動、進場花、移動留下整個人的殘影、離開後原地淡化 → A 撐開背景＋B 斷絲躺進背景。②交會像有第三個人、分開太突然、獨處無色看不出顏色從哪來 → 搭橋、陸續斷、低飽和本色。③使用者：「除了外層的絲纏太多層，其他都很完美」→ trips 5 → 3、grow 8 → 6，**改完還沒看過**。

**沒做／留意**（依優先）
1. 全段走位影片還沒錄（ROADMAP 的成果）。錄第一輪、Gizmos 關掉
2. trips 3、grow 6 還沒看過（使用者接著要錄影）；層數不夠少就把 trips 改 2，grow 跟著約 (trips − 1) × tripGap + 1.3 × spinTime 的八成
3. 使用者對 **C（背景線被絲勾住拖走）** 有興趣：走動時碰到身影外圍的背景線被絲黏住，拖出一段弧，拉太遠就鬆脫、彈回晃幾下。打算加在 Yield 當 `hook` 旋鈕（0 ＝ 關）
4. ROADMAP 的顏色共用規則已改成「獨處低飽和本色」，07a 還是銀白／淡金，沒跟上
5. 搭橋假設兩人左右並排（橋抓對方左／右側），上下相遇沒處理
6. 寫死的：膠囊 2×6（第三份，`ponytail:` 註解）、`id % 8` 格子（id 差 8 會共用光絲）

**下一步**：開新對話，從這份文件開始；數值在兩個 VFX 的 Spin／Yield Block 直接調，行為要改就改兩個 HLSL。
