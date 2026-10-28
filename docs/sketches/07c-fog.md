# Sketch 07c: 看樣：霧中

**目標**：附近的背景流線被撈去纏成觀眾的光絲（同 07a）；身體內部暗；流線底下墊一層極淡的色霧，用來承載調色盤（[目標畫面](../ROADMAP.md#三個身影候選)）。
**架構位置**：渲染層（`L07c_Lines.vfx`：Update 的 Scoop＋FogState，第二個 Output 畫霧）。
**前置**：07（光絲從 07a 複製）
**拋棄式**：`prototype/lookdev` 分支，`Scenes/Sketches/Sketch_07c_fog/`。

## 決定

- 霧的方向選 **C 底霧＋人染色**：很淡的底霧一直都在，人身邊的霧慢慢被染成他的顏色、變亮，離開後退回。另外列過 A 環境霧（霧不屬於任何人）、B 人帶霧（待機全黑）、D 霧染背景線；D 先不做，看過 C 不滿意再考慮
- 身影維持撈（07a），讓霧成為唯一的新變數，才能和 07a 並排比較
- 光絲全程銀白／淡金，交會時也不變色，顏色全部交給霧（使用者：不然會跟霧打架）。這點和 ROADMAP「獨處時低飽和本色」的共用規則不同
- 身體內部暗：身體範圍內不畫霧，人是霧裡的一個暗剪影
- 交會只做霧疊色，重疊處慢慢變亮；不做大理石紋（那是 08）
- 底霧從「調色盤四色緩慢飄移」改成**單一冷灰藍**（第三輪）：四色混在一起又暗，變成泥綠、灰紫，人的顏色也混在裡面分不出來
- 光點組成身體（使用者提的，參考一份簡報裡由光點構成的人形）不放進 07c，記進 ROADMAP 點子池

## 做了什麼

| 檔案 | 內容 |
|---|---|
| `Sketch_07c_fog.unity` | 07a 場景複製；Volume Profile、VFX 換成 07c 的；`MainLines` 改名 `L07c Lines`；`People` 上 SilhouetteMask 的 **Softness 1 → 2** |
| `L07c Volume Profile.asset` | 07a 的複製，沒改 |
| `L07c_Lines.vfx` | `L07a_Lines.vfx` 複製。Update：Scoop 改用 `L07c_Scoop.hlsl`，後面加一個 **FogState**；07a 畫光點的 Output 改成 **Fog**，貼圖換成 `L07c_FogDot.png`；自訂屬性 `fog`（float4） |
| `L07c_Scoop.hlsl` | 07a 的 Scoop，只改顏色：光絲全程銀白／淡金（`revealGap` 拿掉） |
| `L07c_FogState.hlsl` | 霧的狀態（Update）：每一格染到什麼顏色、重疊了多久 |
| `L07c_Fog.hlsl` | 畫霧（Output）：底霧的雲、染色、重疊變亮、身體挖空。和 FogState 分檔，因為每個 context 只宣告它用到的屬性 |
| `L07c_FogDot.png` | 64×64 白色高斯柔光點（alpha = exp(−4.5 r²)） |

### 霧中怎麼運作

```
霧格：從線上粒子挑，每條線、每 3 個點挑一顆（120 × 200 ＝ 2.4 萬格），位置固定在 rest（不跟著線動）

FogState（Update，接在 Scoop 後面）：每格在自訂屬性 fog 裡記
  rgb ＝ 染到的顏色（Σ 權重 × 觀眾的 colorB），a ＝ 重疊程度
  權重 ＝ 貼著輪廓 × 屬於誰
    貼著輪廓：用 SilhouetteMask 的柔邊 coverage 推算離輪廓多遠 d，reach 以內有顏色
    屬於誰：離這個人的膠囊 2 以內
  染上的速度：d 越遠越慢（貼身 0.3 秒，到 reach 是 dyeTime），所以顏色會從身體往外擴散
             移動中快 (1 + wake × 速度) 倍，走過的地方來得及染上，形成尾跡
  退掉：fadeTime；重疊 ＝ 第二強的權重，meetTime 內變亮

Fog（第二個 Output，Additive）：每格畫一顆高斯柔光點（大小 0.5）
  底霧 ＝ 冷灰藍 × 緩慢飄移的雲（Perlin，雲之間有暗縫）× ambient
  被染到的地方：換成觀眾的顏色（飽和度 ×1.6），雲補滿，亮度 ×(1 + dyeLift)，重疊再 ×(1 + meetGlow × a)
  身體裡的格子不畫（硬邊 coverage）
```

| 狀況 | 預期看到什麼（第三輪還沒看過） |
|---|---|
| 待機 | 一片很淡的冷灰藍霧，雲團緩慢飄 |
| 進場、靜止 | 光絲纏上（同 07a）；他的顏色從身體往外擴散，約 4 秒到輪廓外 1.5 |
| 移動 | 走過的地方留下他顏色的尾跡，2 秒淡掉 |
| 交會 | 兩人的顏色在中間混合；頭頂之間、肩膀附近的重疊區在 2 秒內亮到 5 倍 |
| 分開 | 各自的霧帶著對方的顏色（colorB），慢慢退回 |
| 離場 | 光絲鬆開歸位（同 07a），霧 2 秒退回灰藍 |

### 數值

Fog Block（第二個 Output）：

| 值 | 是什麼 |
|---|---|
| ambient **0.06** | 底霧雲團最濃處的亮度（畫面平均約它的 1/4；背景線約 0.02） |
| dyeLift **2** | 被染的霧亮幾倍（2 ＝ 3 倍；0 ＝ 只換顏色） |
| meetGlow **4** | 重疊滿時再亮幾倍（4 ＝ 5 倍） |

FogState Block（Update）：

| 值 | 是什麼 |
|---|---|
| reach **1.5** | 輪廓外多遠的霧會被染（最多 `L07C_SOFTNESS`） |
| dyeTime **4** | 顏色擴散到 reach 要幾秒 |
| wake **1** | 移動時每 1 單位／秒的速度，染色快一倍（0 ＝ 沒有尾跡） |
| fadeTime **2** | 人走開或離場後，霧退回幾秒 |
| meetTime **2** | 重疊處變亮要幾秒 |

Scoop Block：同 [07a](07a-scoop.md#數值)，少了 revealGap。

HLSL 常數：霧格挑法 `L07C_FOG_ROW` 1、`L07C_FOG_COL` 3（**兩個檔案要一致**）；點大小 `L07C_FOG_SIZE` 0.5；亮度換算 `L07C_FOG_NORM`（高斯點平均覆蓋 0.174）；屬於誰的距離 `L07C_FOG_OWN` 2；`L07C_SOFTNESS` 2（**要等於場景裡 SilhouetteMask 的 Softness**）。

## 我的數值與筆記

- ⚠ **霧用粒子鋪會出現格子**：07a 留下的 DefaultDot 是邊緣明顯的圓盤，格子又疏 → 一格一格，身體邊緣整顆拿掉變成圓柱狀鋸齒。換成高斯點（σ ＝ 大小的 1/6，至少要 0.7 格）、格子密 4 倍才平滑。身體邊緣還是軟的（約 0.2）；要銳利只能逐像素算（全螢幕 shader 或 RT）
- ⚠ **疊加的點要除以覆蓋率**（`L07C_FOG_NORM`）。第一輪假設 DefaultDot 覆蓋 0.3，實際更高 → 霧被放大好幾倍；換高斯點後算準了，反而露出 ambient 設太低（雲團平均只有峰值的約 1/4）
- ⚠ **底霧本身帶調色盤顏色時，看不出人在染色**：人的顏色本來就是其中一色。暗的粉彩混在一起是泥色，暗橘看起來是棕色 → 底霧改中性色，人的顏色加飽和、加亮
- ⚠ **染色比人走過一格還慢就不會有尾跡**（dyeTime 3 秒，人走過一格不到 1 秒）→ 移動時加快染色（wake）
- ⚠ **重疊區定義成「兩人的霧都碰得到」**：霧只伸 0.6 時，兩人間距 0.2 的重疊區只剩身體之間一條縫，被光絲和身體暗邊蓋掉
- ⚠ **SilhouetteMask 柔邊的模糊核半徑就是 Softness**（之外截斷成 0）→ 霧最遠只能伸到 Softness。07c 場景改成 2，HLSL 的 `L07C_SOFTNESS` 要跟著改
- ⚠ HLSL 變數不能叫 `line`、`point`（geometry shader 的關鍵字）
- ⚠ **`rest` 是 x、y 兩個子 slot 分別接 Lerp**：換 Block 函式後重接連線，要連子 slot 一起處理，只看父 slot 會漏接
- 複製素描：直接在檔案系統複製、給 .meta 新 guid，再用 sed 把場景和 VFX 裡的舊 guid 換掉（VFX 的 `m_ShaderFile` 直接指向新的 HLSL），比用 editor 腳本 CopyAsset 省事
- 改 graph 的臨時腳本（做法見 [07a 筆記](07a-scoop.md#我的數值與筆記)），放在不 commit 的 `Assets/_Temp07c`，已刪。這次的做法：照名字快照每個 slot（含子 slot）的連線和數值 → `ResyncSlots(true)` → 照名字接回；新增 Block：`CreateInstance<CustomHLSL>()` → `update.AddChild(block, index)` → `SetSettingValue("m_ShaderFile", ShaderInclude)`；Output 的貼圖在 context 的 `inputSlots[0]`；高斯貼圖用 `Texture2D.EncodeToPNG` 產生，匯入設 Clamp、不壓縮
- ⚠ 我觸發的腳本編譯在使用者 Play 07b 時發生過一次 → 之後先查 `editor_get_state`，Play 中就在背景等停止再套用

## 交接（2026-10-28，07c 暫停）

**目前狀態**：三輪回饋。①霧範圍太大、一格一格、像人在噴霧、淡回太慢、重疊不亮 → 霧貼輪廓、高斯點、染色只換顏色、fadeTime 2、meetGlow 4。②幾乎看不到霧、走路沒尾跡 → ambient 調高、加 wake。③底霧是泥色、看不出人在染色、重疊不亮 → 底霧改冷灰藍、染色從身體往外擴散並加飽和、範圍加大到 1.5（Softness 2）。**第三輪改完還沒看過**；使用者覺得 07 難再調下去，先暫停。

**沒做／留意**（依優先）
1. 第三輪沒看過：底霧冷灰藍夠不夠淡、染色擴散看不看得出來、交會時頭頂之間有沒有變亮、尾跡
2. 全段走位影片還沒錄（ROADMAP 的成果）
3. D（霧染背景線）沒做
4. 霧在身體邊緣是軟的；要銳利得改成逐像素
5. 07a 沒細調的部分照搬：快速垂直移動、岔絲只岔向最近一人
6. 寫死的：膠囊 2×6（第四份）；`L07C_SOFTNESS` 要等於 SilhouetteMask Softness；霧格挑法依賴 rest 的兩個 Lerp（−11～11、−5～5）

**下一步**：要繼續就開新對話，從這份文件開始；數值在 VFX Graph 的 Fog／FogState Block 直接調，行為要改就改兩個 Fog HLSL。
