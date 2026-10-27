# Sketch 07a: 看樣：撈

**目標**：附近的背景流線慢慢彎過來，纏成觀眾的光絲；體內稀疏光點緩慢呼吸；背景是純流線（[目標畫面](../ROADMAP.md#三個身影候選)）。
**架構位置**：渲染層（`L07a_Lines.vfx` 的 Update ＋第二個 Output）。
**前置**：07
**拋棄式**：`prototype/lookdev` 分支，`Scenes/Sketches/Sketch_07a_scoop/`。

## 決定

- 輪廓沿用 SilhouetteMask 的剪影
- 穿過身體的背景線**全部被撈去組成身體**，不是只淡出
- 線頭（從背景拉過去的那段直線）留著
- 「斷絲留在對方身上」先用 colorB 殘留代替
- 調色盤是粉彩，細線上和銀白分不出來 → 本色飽和度 ×1.8 再上色
- 07a 場景把 `MousePersonSource` 關掉（見筆記）

## 做了什麼

| 檔案 | 內容 |
|---|---|
| `Sketch_07a_scoop.unity` | Main 複製；Volume Profile、VFX 換成 07a 的；`People` 上的 `MousePersonSource` 停用 |
| `L07a Volume Profile.asset` | Main Volume Profile 複製，沒改 |
| `L07a_Lines.vfx` | MainLines 複製。Update 的 Vortex＋Silhouette 兩個 Block 換成一個 **Scoop**；多一個 Output Particle Quad（Additive、DefaultDot）掛 **Dots** 畫體內光點。線條 Output 沒動 |
| `L07a_Scoop.hlsl` | 光絲（Update） |
| `L07a_Dots.hlsl` | 體內光點（Output）。和 Scoop 分檔，因為每個 context 的 `VFXAttributes` 只宣告該處用到的屬性 |

### 撈怎麼運作

每個線上的點都是一根彈簧，拉向一個目標：

```
平常：目標 = 自己在背景的位置（含起伏）
線穿過某人的身體（離身體中心的高度 ≤ 2.95）：
  這條線在他左右各 W 範圍內的那段被撈走
    線頭進 → 繞輪廓（線在中心以上從頭頂繞，以下從腳底繞）→ 線頭出
    W = 要繞的長度 ÷ (2 × 1.8 拉伸) + 線頭 0.4；同一條線上兩人從中點分，不夠長就先少繞一圈
  繞的位置：2×6 的膠囊當參數，再沿法線找 SilhouetteMask 的真輪廓，往外推（layers、strays、多繞的圈往外螺旋）
人離開：目標回到背景 → 每根光絲照自己的速度鬆開歸位
```

| 狀況 | 看到什麼 |
|---|---|
| 進場 | 大部分光絲很快纏上（先出輪廓），慢的陸續補上。快慢 = settle × 0.35～1.6，偏快 |
| 靜止 | 光帶沿光絲流動（flowGlow），走動時關掉 |
| 移動 | 已纏好的光絲跟著身體走，彈簧只調形狀；約 3 成是飄帶，只跟一半，甩在後面 |
| 快速移動 | 落後太多的光絲斷掉淡出（alpha），之後幾秒長回來 |
| 獨處 | 近無色：銀白或淡金（依 id） |
| 交會 | 面向對方的一側顯出本色；約 35% 光絲面向對方那段岔出去，貼到對方近側最外層，本色、加亮 |
| 分開 | 岔絲被拉長，拉太長就斷掉；本色靠 colorB 殘留慢慢退 |
| 離場 | 光絲慢慢鬆開、回歸背景（使用者最滿意的部分，細調時別動） |

### 數值

Scoop Block（VFX Graph → Update）：

| 值 | 是什麼 |
|---|---|
| settle **3** | 一根光絲纏上／鬆開大約幾秒 |
| layers **0.25** | 靜止時光絲離輪廓散開多寬 |
| loose **1.5** | 走動時額外散開（1.5 ＝ 2.5 倍寬） |
| ribbons **0.3** | 飄帶比例 |
| loops **0.2** | 多繞一圈的比例 |
| strays **0.15** | 有翹出線段的比例（亂絲） |
| strandGlow **0.15** | 光絲亮度（背景約 0.02） |
| flowGlow **3** | 靜止時流動光帶的亮度 |
| revealGap **1.5** | 別人身體多近開始顯本色 |
| forkShare **0.35** | 岔絲比例 |
| forkGap **2** | 身體空隙多少開始岔過去（貼在一起時全岔） |
| snapSpeed **4** | 速度超過多少，落後的光絲會斷 |

Dots Block（第二個 Output）：density **0.05**（約 100 點／人）、brightness **0.4**、dotSize **0.04**。

HLSL 常數：拉伸 `L07A_STRETCH` 1.8、線頭 `L07A_TETHER` 0.4。

## 我的數值與筆記

- ⚠ **Main 場景帶著 `MousePersonSource`**：Play 時點一下 Game View 就多一個觀眾（第一版右上角那團線），後面的 id 跟著往後推 → 調色盤（`id % 4`）顏色全換。看樣場景要關掉
- ⚠ 彈簧追不上移動的人（落後約 2 單位）→ 移動時身影「崩解成不知名生物」。解法是已纏好的光絲直接帶著走，彈簧只調形狀
- ⚠ 粉彩調色盤在 1 px 細線上幾乎看不出顏色 → 飽和 ×1.8，岔絲再 ×2 亮度
- ⚠ UnitySkills 沒有 VFX 的 skill。改 graph 結構用臨時 editor 腳本：asmdef 取名 `Unity.Testing.VisualEffectGraph.Editor`（VFX 套件對這個名字開 InternalsVisibleTo），引用 `Unity.VisualEffectGraph.Editor`／`Runtime`，就能叫內部 API：`VisualEffectResource.GetResourceAtPath(path).GetOrCreateGraph()`、CustomHLSL 的 `m_ShaderFile`／`m_AvailableFunction` 設定、`ResyncSlots(true)`、`slot.Link()`、`resource.WriteAssetWithSubAssets()`。腳本放在不 commit 的 `Assets/_Temp07a`，做完已刪
- ⚠ HLSL 加新參數，Graph 上的新 slot 預設是 **0**（例如 ribbons 0 ＝ 沒有飄帶），記得給值。改名或改型別的參數也會變新 slot
- Custom HLSL 只認得 `attributes.x =` 這種寫法是「寫入」

## 交接（2026-10-27，07a 暫停）

**目前狀態**：第一版回饋：進場很酷但看不出人形、交會不明顯、移動時崩解成不知名生物、離場慢慢歸位很滿意。第二版針對前三點改了（光絲跟著身體、纏得快、交會岔絲＋飽和本色），使用者決定 07a 先到這，之後再細調視覺。

**沒做／留意**（依優先）
1. 全段走位影片還沒錄（ROADMAP 的成果）。錄第一輪、Gizmos 關掉
2. 第二版沒有逐段確認：14–19 秒快速、垂直移動的身影；21–31 秒交會到分開
3. 岔絲只岔向最近的一人（目標是可同時岔向多人）；「斷絲留在對方身上」用 colorB 殘留代替
4. 斷絲用 alpha 淡出，在 Additive 線條上看不看得出來沒確認
5. 膠囊尺寸 2×6 又寫死一份（`ponytail:` 註解），和 `Silhouette.hlsl`、`ColorExchange.cs` 一樣，webcam 時一起改

**下一步**：細調視覺開新對話，從這份文件開始；數值在 VFX Graph 的 Scoop Block 直接調，行為要改就改 `L07a_Scoop.hlsl`。
