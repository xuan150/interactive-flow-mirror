# Roadmap

> 任何時候（新對話、compact 後、跳著做）都從這份開始對照。

## 構想

一面 4m × 2m、立在地上的 LED「鏡子」。觀眾走進範圍，螢幕上浮現由流動線條構成的身影；有人進場產生漣漪，多人交會時彼此影響。
實體案不會進行，這是**個人概念作品**：在 Unity 裡用滑鼠假人模擬，效果好再考慮 webcam 真人入鏡。

## 已確定的設計決策

- Unity 6000.3.15f1，3D (URP)，主力 **VFX Graph**
- 畫面 2:1（Game View 1920×960），正交相機 Size 5（可視範圍 20×10 單位），鏡像（左右翻轉，在輸入端處理）
- **交會**：帶走彼此的顏色（靠近時漸層互滲、分開後殘留）＋ 流場互相牽引（每人是一個漩渦）
- **痕跡**：人離開後軌跡慢慢沉澱淡出
- **視覺主體**：90 條**錨定的水平平行線**（參考 Rutt-Etra、Unknown Pleasures）。每個點＝原位＋位移，會起伏但不漂走；冷藍柔白、Bloom 朦朧光。Sketch 02 的流場線條保留為探索紀錄，之後可當交會處的點綴
- **人的呈現**：不投真人影像。人是**黑色剪影**，線條繞著身體流動、讓開，身體邊緣最亮（像逆光，線條擠在一起發亮）；認得出是人但沒有細節（[參考](refs/person-silhouette-rim.png)）
- **動作語彙**（第一版）：只做快慢。靜止 → 線條隆起、讓開出清楚的身影；快走 → 線條被大幅推開、甩動
- **待機**：線條緩慢起伏（noise）＋週期性呼吸慢波＋沿線流動的流光，不能完全靜止
- 視覺層與輸入來源的接縫：見 [ADR 0001](adr/0001-visuals-read-person-buffer-and-id-mask.md)

## 架構：單向資料流

```
[輸入層]  →  [人物狀態]  →  [場（GPU）]  →  [渲染（VFX Graph）]  →  [後製]
滑鼠假人      Person 清單     漣漪場           線條粒子(Strip)        Bloom
(之後 webcam) + 身影 ID 遮罩   痕跡場           讀取以上全部            (選配 LED 點陣)
```

| 層 | 內容 | 技術 |
|---|---|---|
| 輸入 | `MousePersonSource`：左鍵新增/拖曳人、Delete 移除；把剪影貼圖蓋印到 ID 遮罩 | C# + 簡單 shader |
| 人物狀態 | `PersonTracker`：持有人物清單、算速度、顏色交換、上傳 GraphicsBuffer | 純 C#（顏色交換寫成純函式，有 EditMode 測試） |
| 場 | **漣漪場**：波動方程 ping-pong RT（1/4 解析度），進場／移動注入波源<br>**痕跡場**：衰減 RT，人走過塗上自身顏色，緩慢淡出 | Compute Shader 或 Custom Render Texture |
| 渲染 | 90 條錨定平行線（Particle Strip，Single Burst 一次生成、永生）；位置 = 原位 + 位移，位移 = 起伏 noise + 呼吸 + 每人漩渦 + 漣漪高度 + 身影遮罩隆起；亮度含流光；顏色取自人物／痕跡場 | VFX Graph |
| 後製 | URP Volume Bloom；之後選配 LED 點陣 | URP Post-processing |

## 資料夾慣例

```
Assets/_Project/
  Scripts/  Shaders/  VFX/
  Scenes/Main.unity
  Scenes/Sketches/Sketch_0X_*/        ← 教學用，可丟棄；每張一個資料夾，放場景與它的 Volume Profile
docs/sketches/0X-*.md                 ← 每張 sketch 的步驟與筆記（開始做那張時才寫）
```

## 素描本進度

每張 30–60 分鐘出畫面，原理用到再講。每張結束時對照上方架構圖說明它屬於哪一層。

| | # | Sketch | 學到什麼 | 成果 | 前置 | 文件 |
|---|---|---|---|---|---|---|
| [x] | 01 | Flow | VFX Graph 四區塊、Turbulence、Bloom | 會流動的發光粒子 | — | [01-flow](sketches/01-flow.md) |
| [x] | 02 | Lines | Particle Strip、漸層、透明疊加 | 流場線條（探索，待機改由 02b） | 01 | [02-lines](sketches/02-lines.md) |
| [x] | 02b | Line Field | Operator、Single Burst、stripIndex、Total Time、noise | **待機畫面完成** | 02 | [02b-line-field](sketches/02b-line-field.md) |
| [x] | 03 | Vortex | C# → GraphicsBuffer → VFX、Custom HLSL；滑鼠假人成為漩渦 | 線條被捲成螺旋、中心黑洞（強度淡入延後到 06） | 02b | [03-vortex](sketches/03-vortex.md) |
| [x] | 04 | Ripple | Compute shader、ping-pong RT、波動方程 | 進場／移動產生漣漪並干涉 | 03 | [04-ripple](sketches/04-ripple.md) |
| [x] | 05 | Silhouette | ID 遮罩蓋印、黑色剪影、線條繞流、邊緣光暈 | 身影浮現（「線被擠出、繞輪廓最擠」未達預期，Main 前再議） | 03 | [05-silhouette](sketches/05-silhouette.md) |
| [ ] | 06 | Exchange | 顏色交換＋痕跡場 | 交會帶走彼此顏色、軌跡沉澱 | 03、05 | |
| [ ] | — | Main | 把 01–06 組合到正式架構 | 完整概念作品 | 01–06 | |
| [ ] | 後 | Webcam | 人像分割模型產出 ID 遮罩 | 真人入鏡 | Main | |
| [ ] | 後 | LED 點陣 | 後製 shader | 展場感 | Main | |

## 組合前要重新討論

使用者的節奏：**04–06 先快速做完**，組合 Main 之前再來回討論、重新整理「希望完成的樣子」。已知要在那時定的事：

- **漩渦的角色**：03 的漩渦（螺旋＋中心黑洞）現在每個人隨時都有。05 加上剪影後，一個人身上同時有剪影、螺旋、黑洞，可能太滿，黑洞也和剪影搶「黑色的人」。傾向：單獨一人時漩渦很弱或沒有，兩人靠近才變強（接 03 延後的強度淡入、06 交會）
- **進場漣漪怎麼觸發**：滑鼠假人是憑空出現，真人是從邊緣走進來，進場那一發會落在邊界被吸收。實際漣漪主要靠走動波紋；進場那發可改成「走到定點停下時」打一發（呼應「靜止 → 線條隆起」），或拿去做幽靈訪客／抬手
- **剪影的擠壓感**：05 的線只被推歪一點、身體內靠變黑，沒有「完全被擠出、輪廓最擠」。可選方向見 [05 交接](sketches/05-silhouette.md#交接2026-10-2205-暫停)
- 三個效果的分工：04 漣漪＝「有事發生」（進場／移動，幾秒就散）；05 剪影＝「有人在這」（在場全程）；03 漩渦＝「兩人之間有關係」（交會）

## 數學積木

Operator 的積木、配方與學習資源：[vfx-math-cheatsheet](vfx-math-cheatsheet.md)。遇到新積木就補進去。

## 參考圖

存在 [docs/refs/](refs/)，做的時候對照。

| 圖 | 是什麼 | 對應 |
|---|---|---|
| [lines-wave-vertical](refs/lines-wave-vertical.png) | 平行線整片緩慢起伏 | 02b 待機 |
| [lines-ridge-bump](refs/lines-ridge-bump.png) | 平行線被推出一道隆起 | 05 身影、04 漣漪 |
| [lines-vortex-orbit](refs/lines-vortex-orbit.png) | 線條繞著中心旋成軌道 | 03 漩渦、06 交會 |
| [particles-filaments-purple](refs/particles-filaments-purple.png) | 大量細小粒子擠在流場匯聚處，成為發光細絲 | 點子池 |
| [person-silhouette-rim](refs/person-silhouette-rim.png) | 黑色人形剪影，線條繞著身體流動，邊緣最亮 | 05 身影、人的呈現 |

## 點子池

還沒排進 sketch 的點子，組合 Main 時評估。

- **辮子（意外發現）**：拔掉「原位 y」，讓 `y = 起伏 noise × 權重`。平靜區所有線疊成**一條線**，起伏區因為 noise 仍用各自原位 y 取樣而**散開交織成一束辮子**，再收回一條。「一條線分岔、交會、收束」。保存在 `Assets/_Project/VFX/Ideas/Idea_Braid.vfx`（02b 數值＋20 條線）；圖：[graph](refs/ideas/braid-graph.png)、[成果](refs/ideas/braid-result.png)
  - 可能用法：待機時一條線，有人進場時從他身上分岔成辮子；或兩人交會時兩束辮子纏在一起
- **發光細絲**（[參考](refs/particles-filaments-purple.png)）：幾十萬顆極小、半透明粒子被流場推著，擠在匯聚處的就疊加成亮絲。Sketch 01 Frequency 調高時「粒子被困住」就是雛形。可用在交會（兩人之間長出細絲）或痕跡（走過處沉澱成紋路再散開）
- **幽靈訪客**：待機時偶爾在隨機位置冒出一圈很淡的漣漪，像剛有人經過（需要 04 漣漪場）
- **牽線**：距離夠近的兩人之間長出細線，走遠時拉長、變細、斷掉
- **抬手**：送出較大的漣漪（假人用右鍵模擬）
- **集體共振**：很多人同時靜止時，漣漪干涉成克拉德尼圖形般的穩定幾何圖樣
- **彗星尾巴**：02 的線改成固定長度、跟著筆尖跑的尾巴（墨跡壽命 = min(尾巴秒數, 筆尖剩餘壽命)）
- **漩渦強度跟移動速度連動**：滑鼠／人移動越快漩渦越強，停下來變弱（互動小彩蛋）
- **人形籠子（05 意外發現）**：線條上的點被左右、上下一起推離身體（推超過點距），線來回折返，在人身上罩出一個人形的鋸齒籠子。可當「被困住」或特殊狀態的語彙。重現：`Silhouette.hlsl` 改回 `p -= grad * push`（x、y 都推）、push 2 以上

## 驗收

- 每張 sketch：Play 後 Game View 肉眼確認「成果」欄的效果
- 效能：Stats 視窗 FPS ≥ 60（粒子數從 1 萬起跳再往上調）
- Main：放 3 個假人，走完 待機 → 進場漣漪 → 靜止凝聚 → 交會換色 → 離開留痕淡出
