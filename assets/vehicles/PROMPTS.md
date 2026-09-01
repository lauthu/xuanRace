# Tripo 3D 模型生成提示词档案

每辆车的文生图 prompt + 生成参数记录，用于后续微调复现。
管线统一为：**generate-image（Nano Banana）→ HD Model + Generate in Parts（关 Texture）→ Texture 工作区 4K 二次贴图**。
通用后缀（所有车辆 prompt 都应包含）：

```
full vehicle visible, 3/4 front view, studio lighting, plain grey background, reference for 3D modeling
```

经验：
- 写 `four wheels pointing straight forward` 可减少前轮烘焙偏角（否则要用 straighten_wheels.py 矫正）。
- 要车内有驾驶员：闭式车厢写 `racing driver in helmet and racing suit visible through windshield`，开式座舱写 `racing driver in full helmet and racing suit seated in cockpit`。
- 中文品牌特征写具体（家族脸、姿态、轮胎样式）能显著提高选图质量。

---

## 已生成模型

### 斯巴鲁 Impreza WRX STI GC8（subaru_gc8_driver.glb）✅ 已接入
```
Subaru Impreza WRX STI GC8 1990s rally car, blue with gold wheels, four wheels
pointing straight forward, racing driver in helmet and racing suit visible through
windshield, full vehicle visible, 3/4 front view, plain grey background,
reference for 3D modeling
```
- HD Model + Parts（27 部件）→ Texture 4K → straighten_wheels.py 矫正后轮 4~6°
- 驾驶座含赛车服+头盔驾驶员

### 坦克300（tank300_parts_textured.glb）✅ 已接入
```
Tank 300 off-road SUV, boxy retro body, round headlights, roof rails,
all-terrain tires, full vehicle visible, 3/4 front view, plain grey background,
reference for 3D modeling
```
- HD Model + Parts（28 部件）→ Texture 4K；无驾驶员（补新车时可加驾驶员重写）

### Camaro ZL1（camaro_parts_textured.glb）✅ 已接入
```
Chevrolet Camaro ZL1 muscle car, aggressive front fascia, wide body,
racing driver in helmet visible through windshield, full vehicle visible,
3/4 front view, plain grey background, reference for 3D modeling
```
（凭记录重建，原始措辞可能略有出入）
- HD Model + Parts → Texture 4K；无驾驶员

### 道奇 Charger（charger_parts.glb）✅ 已接入
```
Dodge Charger muscle sedan, crosshair grille, fastback roofline,
full vehicle visible, 3/4 front view, plain grey background,
reference for 3D modeling
```
（凭记录重建）
- HD Model + Parts → Texture 4K；无驾驶员

### 树种库（assets/trees/）✅ 已接入
单树白底竖版 3:4，HD Model + Texture 一步生成（未分件）：
```
single <pine|oak|birch|leafless dead> tree, full tree visible, centered,
plain white background, reference for 3D modeling
```
（凭记录重建）

### 野外小件库（assets/props/）✅ 已接入
```
single <boulder|rock ledge|bush|fern>, centered, plain white background,
reference for 3D modeling
```
（凭记录重建）

---

## 待生成模型（本轮目标：全部带赛车手）

### 1. 极速跑车（替换 Quaternius sports_car.glb）
```
Modern GT sports car, sleek low-slung coupe body, aggressive front splitter,
large rear wing, racing livery, four wheels pointing straight forward,
racing driver in helmet and racing suit visible through windshield,
full vehicle visible, 3/4 front view, studio lighting, plain grey background,
reference for 3D modeling
```
- 状态：待生成

### 2. F1 赛车（替换 Kenney raceCarRed.glb）
```
Formula 1 open-wheel race car, exposed wheels, wide front and rear wings,
halo cockpit protection, racing driver in full helmet and racing suit seated
in cockpit, four wheels pointing straight forward, full vehicle visible,
3/4 front view, studio lighting, plain grey background,
reference for 3D modeling
```
- 状态：待生成

### 3. 拉力赛车（替换 Kenney hatchback-sports.glb）
```
Rally hatchback race car, wide fender flares, roof scoop, large rear spoiler,
mud flaps, rally livery, four wheels pointing straight forward,
racing driver in helmet and racing suit visible through windshield,
full vehicle visible, 3/4 front view, studio lighting, plain grey background,
reference for 3D modeling
```
- 状态：待生成

### 4. 吉普越野车（替换 Kenney suv.glb）
```
Off-road 4x4 jeep SUV, boxy rugged body, roof rack, spare tire on rear door,
snorkel, all-terrain tires, four wheels pointing straight forward,
racing driver in helmet and racing suit visible through windshield,
full vehicle visible, 3/4 front view, studio lighting, plain grey background,
reference for 3D modeling
```
- 状态：待生成

### 5. 未来赛车（替换 Kenney race.glb）
```
Futuristic concept race car, low aerodynamic body, enclosed bubble canopy,
glowing accent lines, large rear diffuser, four wheels pointing straight
forward, racing driver in helmet visible under canopy, full vehicle visible,
3/4 front view, studio lighting, plain grey background,
reference for 3D modeling
```
- 状态：待生成
