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
- **動作語彙**（第一版）：只做快慢。靜止 → 線條凝聚成身影；快走 → 推開線條
- **待機**：沒人時流場線條自己漂浮
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
| 渲染 | 全畫面粒子 + Particle Strip 拖成線；力 = 流場 noise + 每人漩渦 + 漣漪梯度 + 靜止時吸向遮罩；顏色取自人物／痕跡場 | VFX Graph |
| 後製 | URP Volume Bloom；之後選配 LED 點陣 | URP Post-processing |

## 資料夾慣例

```
Assets/_Project/
  Scripts/  Shaders/  VFX/
  Scenes/Main.unity
  Scenes/Sketches/Sketch_0X_*.unity   ← 教學用，可丟棄
docs/sketches/0X-*.md                 ← 每張 sketch 的步驟與筆記（開始做那張時才寫）
```

## 素描本進度

每張 30–60 分鐘出畫面，原理用到再講。每張結束時對照上方架構圖說明它屬於哪一層。

| | # | Sketch | 學到什麼 | 成果 | 前置 | 文件 |
|---|---|---|---|---|---|---|
| [x] | 01 | Flow | VFX Graph 四區塊、Turbulence、Bloom | 會流動的發光粒子 | — | [01-flow](sketches/01-flow.md) |
| [ ] | 02 | Lines | Particle Strip、漸層、透明疊加 | **待機畫面完成** | 01 | |
| [ ] | 03 | Vortex | C# → GraphicsBuffer → VFX；滑鼠假人成為漩渦 | 線條被滑鼠捲動 | 02 | |
| [ ] | 04 | Ripple | Compute shader、ping-pong RT、波動方程 | 點擊產生漣漪並干涉 | 03（可獨立先做） | |
| [ ] | 05 | Silhouette | ID 遮罩蓋印、靜止凝聚／快走推開 | 身影浮現 | 03 | |
| [ ] | 06 | Exchange | 顏色交換＋痕跡場 | 交會帶走彼此顏色、軌跡沉澱 | 03、05 | |
| [ ] | — | Main | 把 01–06 組合到正式架構 | 完整概念作品 | 01–06 | |
| [ ] | 後 | Webcam | 人像分割模型產出 ID 遮罩 | 真人入鏡 | Main | |
| [ ] | 後 | LED 點陣 | 後製 shader | 展場感 | Main | |

## 驗收

- 每張 sketch：Play 後 Game View 肉眼確認「成果」欄的效果
- 效能：Stats 視窗 FPS ≥ 60（粒子數從 1 萬起跳再往上調）
- Main：放 3 個假人，走完 待機 → 進場漣漪 → 靜止凝聚 → 交會換色 → 離開留痕淡出
