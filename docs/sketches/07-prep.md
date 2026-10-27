# Sketch 07: 準備

**目標**：看樣 07a–c、08 和最終影片共用的基底：線條畫質修正、三個候選共用的背景、照時間軸自動走位的觀眾。
**架構位置**：輸入層（`Viewer`、Timeline）＋渲染層（`MainLines`）＋後製（Bloom）。
**前置**：06
**非拋棄式**：放在 main，看樣從 `Scenes/Main.unity` 複製。

## 決定

- 基底場景 `Scenes/Main.unity`（06 場景複製），Volume Profile 是自己的 `Main Volume Profile`（06 其實一直用 02 的 profile）
- 走位約 47 秒、看樣錄全段（ROADMAP 原本寫 10 秒，放不下「慢慢長成」）
- 錄影：使用者自己螢幕錄影，不裝 Recorder。Game View 1920×960、縮放 1x，位元率開高（極淡的細線最怕壓縮）
- 共用背景在 07 做，三個身影候選才比得公平
- 這張以快速進入看樣為主，Unity 操作由 Claude 直接做（UnitySkills＋臨時 editor 腳本＋改 `.vfx` YAML）

## 做了什麼

### 走位（輸入層）

- `Scripts/Viewer.cs`：掛在 `People` 底下的子物件。物件啟用＝觀眾進場（`tracker.Add`），每幀同步位置，停用＝離場。名額滿了就略過。編輯模式畫 2×6 的 Gizmo 框（VFX 在編輯模式看不到身影）
- `People` 底下 `Viewer A/B/C`（Animator＋Viewer，存檔時是**停用**的，免得 Play 第一幀閃一下）
- `Choreography` 物件：PlayableDirector，Play On Awake，**Loop**；`Timeline/Choreography.playable` 每個觀眾兩條軌：`X Present`（Activation）、`X Position`（Animation，Apply Transform Offsets、Remove Start Offset 關，位置是絕對座標）
- 站在地上：身影中心 y = −2（身高 6，腳貼底邊）；從畫面外 x = ±12.5 走進來。關鍵影格切線全平，每次起步、停下都有緩動
- **垂直移動**：背景線是水平的，橫走是順著線滑、上下是橫切線（07a「撈」、光絲被甩在後面差最多的情況），所以走位放了兩段。做法是自由上下（腳會離地，抽象鏡子可接受）；「前後走、遠小近大」要每人帶大小、改 `Person`／SilhouetteMask／兩份寫死的膠囊，留到 webcam

| 秒 | A | B | C | 段落 |
|---|---|---|---|---|
| 0–4 | | | | 待機 |
| 4–8 | 左外 → −5 | | | 單人進場 |
| 8–14 | −5 | | | 靜止 |
| 14–15 | (−5, −2) → (−1, −0.5)（快、往右上） | | | 快速移動，橫切背景線 |
| 17–19 | 慢慢落回 y −2 | 右外 → 2.5 | | 慢速垂直＋B 進場 |
| 21–28 | −1 | → 1.2 停住 | | 交會（身體空隙 0.2） |
| 28–31 | −1 | → 5 | | 分開 |
| 31–38 | −1 | 5 → 2 | (左外, −4) 斜上 → (−4, −2) | 三人 |
| 38–44 | 40 起 → 左外 | 38.5 起 → 右外 | 38 起 → 左外 | 離場 |
| 44–47 | | | | 待機（痕跡退場） |

要改走位：開 Timeline 視窗選 `Choreography`，在 `X Position` 的 clip 上調 x 曲線（y、z 是常數）；進出場時間拖 `X Present` 的 clip。

### 畫質

| 哪裡 | 改了什麼 | 為什麼 |
|---|---|---|
| `PC_RPAsset` | MSAA 關 → **4x**；HDR 精度 32 → **64 bit** | 線寬 ~1 px 沒有 AA 會階梯、閃；R11G11B10 的藍只有 5 bit，極淡的線疊加會出色階 |
| 相機 | **Dithering** 開 | 暗部漸層（Bloom）在影片壓縮後不出條紋 |
| Bloom | 門檻 0.8 → **1**、強度 4 → **1**、High Quality Filtering **開** | 背景線最亮 ~0.17，不會發光；只有身影的輪廓光（> 1）會 |
| `People` | 拿掉 RippleField；SilhouetteMask 的 Show Debug 關 | 漣漪退場；左上角的除錯圖會被錄進去 |

### 共用背景（`VFX/MainLines.vfx`，從 `LineExchange` 複製）

| | 06 | 07 |
|---|---|---|
| 條數 | 40（間距 ~24 px） | **120**（間距 ~8 px，對照 [參考](../refs/lines-fog-cursor.png)） |
| 每條點數 | 300（每段 ~7 px） | **600**（每段 ~3.5 px，推大時不折角） |
| 粒子數 | 12,000 | **72,000**（Burst Count、Capacity、Strip Capacity、三個 Divide 一起改） |
| 線寬 | 0.015（~1.4 px） | **0.01**（~1 px，SubpixelAA 接手） |
| Output 貼圖 | DefaultDot（Stretch，不可控地調暗） | **None**（Use Base Color Map） |
| 漸層 ①（沿線） | 深藍 → 深紫 | 固定淡銀白 **(0.022, 0.0235, 0.027)**：背景要退到不搶之後身影的色彩 |
| 漸層 ②（掃光） | 光帶處 (3.7, 9.8, 12)，單通道衝到 4+ | **兩端都 ×1**＝沒有掃光（Block 和節點保留，要叫回就改回漸層） |
| 漣漪 | rippleHeight 1.2、rippleGlow 4 | 0 |

掃光是每 8 秒橫掃全畫面的光帶，方向性強，會和「畫面只有身影一個主角」打架；三個候選都用不到。背景的「不能完全靜止」靠起伏（noise ±0.3），線被波擠在一起的地方加法疊色自然變亮。要調背景亮度：改漸層 ① 的顏色。

起伏、Silhouette Block 的數值都沒動。

## 我的數值與筆記

- ⚠ 06 場景的 Volume 指著 **02** 的 Global Volume Profile（複製場景時沒按 Clone），Main 已改成自己的
- ⚠ Unity 6 的 `.vfx` 檔案裡只有 graph，**不存編譯結果**（在 Library 的 import artifact）：直接改 YAML 後 Reimport，檔案看不出有沒有編譯，要 Play 才知道
- ⚠ **改 YAML 停用 Block 沒用**：VFX 17 的啟用狀態在 Block 的 activation slot（`_vfx_enabled`），`m_Disabled` 是舊欄位、只在建立 slot 時讀一次 → 第一次「停用」掃光其實沒生效。改 `_vfx_enabled` 也不行：context 快取了啟用清單，從磁碟改不會更新 → 編譯失敗 `This method should not be called on a disabled block`。要停用 Block 就在 VFX Graph 裡取消勾選；從 YAML 只改數值
- ⚠ VFX Graph 視窗開著時，Console 出現 `ArgumentException: Context does not exist`（來自 `VFXViewWindow.Update`），換場景、複製 VFX 時發生。關掉 VFX Graph 視窗再開
- Loop 時每一輪的觀眾 id 會變，調色盤是 `id % 4` → 第二輪起顏色換了。錄影錄第一輪

## 交接（2026-10-27，07 完成）

**目前狀態**：使用者 Play 確認「可以了」。一路的回饋：線寬可以；顏色要更不明顯 → 降到 0.022、掃光拿掉；人要能上下移動 → 加了兩段垂直走位。

**下一步**：照 [ROADMAP 看樣計畫](../ROADMAP.md#看樣計畫) 從 main 開 `prototype/lookdev`，07a／07b／07c／08 各從 `Scenes/Main.unity` 複製場景＋Volume Profile＋`MainLines.vfx`。每張看樣開新對話。

**沒做／留意**
1. Main 的身影還是 06 的做法（黑色剪影＋輪廓光，rimGlow 10、Softness 1 → 身體外 1 單位都亮）；看樣各自重做
2. Viewer 的 Gizmo 方框在 Game View 開 Gizmos 時會出現，錄影前關掉
3. 前後走（遠小近大）沒做，留到 webcam
