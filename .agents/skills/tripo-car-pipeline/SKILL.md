---
name: tripo-car-pipeline
description: End-to-end pipeline for generating a high-quality AI car model on Tripo Studio (tripo3d.ai) and importing it into this Godot racing game — image prompt, Generate 3D Smart Mesh with Generate in Parts, texture pass in the Texture workspace, transfer via DCC Bridge or GLB export, wheel splitting, and wiring into CAR_MODELS. Use whenever the user wants to add/regenerate a nicer car model via Tripo3D, Meshy, or any AI 3D generator, mentions "generate in parts", "分件", "DCC Bridge", "send to godot", or wants to replace/optimize an existing vehicle model.
---

# Tripo3D → Godot 赛车模型管线

在本项目（XuanRace，Godot 4.7）中，把一辆 AI 生成的精细车模从 Tripo Studio 搬进游戏并让它可驾驶。整条链路的每一步都踩过坑，严格按下面顺序执行，不要跳步或换序。

## 总览

```
Tripo Studio（浏览器）
  1. generate-image      文字 prompt → 4 张候选图
  2. Generate 3D         选图 → HD Model + Generate in Parts（关 Texture！）
  3. Texture workspace   用同一张图做二次贴图（保留分件）
  ↓
传输到工程
  4a. DCC Bridge（首选）  Send To → Send to Godot → TripoModels/<name>/
  4b. Export GLB（备选）  下载后放 assets/vehicles/
  ↓
工程接入
  5. 如是单网格：tools/split_wheels.py 离线拆轮
  6. game_state.gd CAR_MODELS 加条目（yaw / recolor / parts / glass_patches）
  7. 窗口模式跑 debug 截图验证（方向、轮子、配色）→ 提交推送
```

## 第 1 步：文字 prompt → 候选图

在 Tripo Studio 用 **generate-image**（Nano Banana）。prompt 直接决定 3D 生成的上限，要点：

- 指明 3/4 视角、干净背景、全车完整入镜（`full vehicle visible, 3/4 front view, studio lighting, plain background`）
- 写明是 3D 建模参考（`for 3D modeling reference`），避免艺术化光影
- 车型特征写具体：品牌特征脸、车身姿态、轮胎样式。示例（坦克300）：
  `Tank 300 off-road SUV, boxy retro body, round headlights, roof rails, all-terrain tires, full vehicle visible, 3/4 front view, plain grey background, reference for 3D modeling`
- 出 4 张候选，选轮廓最完整、轮子最清晰的一张进入 3D 生成

浏览器自动化细节见 `references/browser-automation.md`（IAB 不能上传文件、下载事件不稳定、Send To 子菜单合成事件打不开等，先读它再操作浏览器）。

## 第 2 步：Generate 3D Smart Mesh + Generate in Parts

- 用 **HD Model** 模式。注意：**Generate in Parts 开关只在 HD Model 流程里有**；Smart Mesh P2.0 模式的设置是 Topology（Quad/Triangle）+ Polycount，没有分件选项（UI 更新后实测）。
- **Generate in Parts 打开、Texture 必须关闭**（在 HD Model 的 Geometry & Texture 弹层里确认 Texture 关、8K Texture 关）—— 生成时开 Texture 与 Parts 互斥，会产出单网格。这是最容易犯的错。
- 分件粒度选 Balanced（6–15 parts）即可；Ultra Mesh Quality 可开。
- 分件版产出后，车轮是独立部件，游戏内 `_setup_wheels` 能直接识别并包枢轴动画，不需要离线拆轮。
- 验证：工作区页显示顶点数；分件版一般 2~3 万面以上、部件列表里能看到 wheel/tire 部件。

## 第 3 步：Texture workspace 二次贴图

分件生成时不能同时出贴图，但**生成后可以把模型带进 Texture workspace 再贴图，分件结构会保留**。

- 入口：模型 workspace 页 → Texture / PBR 相关入口，用第 1 步选中的同一张参考图做贴图源。
- 贴图版确认：视口里车身出现车漆/玻璃/轮毂纹理，而不是纯色灰模。
- 若贴图后部件被打散重组（发生过：后窗并入车壳），用 `scripts/debug/part_sheet.gd` 出部件隔离接触表确认结构。

## 第 4 步：传输到工程

### 首选：DCC Bridge

插件 `addons/Tripo3d_Godot_Bridge` 已在 `project.godot` 的 `editor_plugins` 启用。启动编辑器后插件在 `127.0.0.1:60650` 起 WebSocket 服务：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --editor --path /Users/liuxinyu/Projects/xuanRace \
  > /tmp/godot_editor.log 2>&1 &
echo $! > /tmp/godot_editor.pid
```

日志出现 `[Tripo Bridge] WebSocket server started` 即可接收。Tripo 网页端 **Send To → Send to Godot** 会把 FBX + `.fbm` 贴图推到 `TripoModels/<model_name>/`。

已知限制：**Send To 子菜单在浏览器自动化下打不开**（合成 hover/click 不触发展开，DOM 里看不到 godot 条目）。手动点击可以。所以自动化做到"打开 Export 面板"为止，请用户点最后一下；或用备选方案。

### 备选：Export GLB 下载

Export 面板选 GLB。IAB 下载事件不稳定：对话框可能空关。重试、用坐标级点击点黄色 Export 按钮，下到 `~/Downloads` 后移入 `assets/vehicles/`。

### API 方案（目前不可用）

`tools/tripo_generate.py` 是完整的 API 管线（text_to_model → 轮询 → 下载 → 拆轮），需要 `TRIPO_API_KEY` 环境变量。注意 **API credits 与 Studio credits 是两个账户**，Studio 充值对 API 无效；当前 API 余额为 0。key 只走环境变量，`.gitignore` 已排除 `.env`/`*.key`，绝不入库。

## 第 5 步：单网格模型拆轮（仅非分件模型需要）

如果拿到的是单网格 GLB（轮子焊在车壳里），用离线手术脚本：

```bash
python3 tools/split_wheels.py <in.glb> <out.glb>
```

原理：底部 45% 高度带做 K-means 找车轴位置 → 3D 球分配轮顶点 → **AABB 几何中心**做枢轴（K-means 质心会被轮拱碎屑带偏，导致绕偏心点公转）→ z>0 侧轮子从 z<0 镜像（镜像平面是 z=0，翻绕序、法线 z 取反）→ 保留 NORMAL/TEXCOORD_0/贴图重写 GLB。

分件模型跳过这步。

## 第 6 步：接入 game_state.gd

在 `scripts/core/game_state.gd` 的 `CAR_MODELS` 加一条：

```gdscript
{ "name": "Camaro ZL1", "path": "res://assets/vehicles/camaro_parts.glb",
  "yaw": -1.5708, "recolor": false, "parts": true },
```

字段规则：

- `yaw`：**Tripo 模型的车头朝向轴不一致，每辆车都要实测**（Camaro -PI/2、Charger +PI/2、Quaternius 0）。不要沿用别人的值。判断方法：先设 0 跑一张行驶截图，车屁股朝前则加/减 PI/2 再试。
- `recolor`：带贴图的模型设 `false`（保留原生材质，不走调色板重着色）。未贴图的分件模型设 `parts: true`，由 `CarRecolor.colorize_parts` 按规则上色（车身→车顶→玻璃→圆形件→装饰，顺序不能乱，乱了轮子会吃到车漆色）。
- `glass_patches`：若侧窗/后窗与车壳是一个部件（贴图版常见），用比例色块补丁补玻璃色，格式见坦克300条目。
- 中文名注意默认字体缺字形（"迈"会变成豆腐块），踩过坑后 Camaro 用了英文名。

新文件入库前更新 `assets/vehicles/LICENSE.txt` 的署名。

## 第 7 步：验证（必须窗口模式）

**headless 模式渲染是黑图**（dummy texture storage），一切视觉验证都要窗口模式跑：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . -s res://scripts/debug/drive_shot.gd
```

（具体 debug 场景看 `scripts/debug/` 目录；截图经 `root.get_texture().get_image().save_png()` 落盘。）

验收清单：

1. 按 W 车头朝前（不是屁股/侧面朝前）
2. 四轮都在、贴地（不悬空 —— 悬空调 `car_controller.gd` 的 `VISUAL_Y_OFFSET`）
3. 行驶中轮子转动且绕轴心（不是绕偏心点公转）
4. 玻璃/车漆颜色正确
5. 在选车界面预览里比例正常（自动缩放 `FIT_LENGTH=4.5` 会处理，但长轴取 `max(size.x, size.z)`，朝向错了会缩错轴）

全部通过后 `git add -A && git commit && git push`。

## 收尾清理

- `TripoModels/` 里测试推送的重复目录删掉（bridge 每次推送都新建文件夹）。
- 编辑器不用了记得 kill（pid 在 `/tmp/godot_editor.pid`），否则 bridge 端口被占。

## 常见坑速查

| 症状 | 原因 | 处理 |
|---|---|---|
| 生成了单网格，没分件 | 开了 Texture，或误用 Smart Mesh P2.0（该模式无分件开关） | 用 HD Model、关 Texture 重新生成，贴图放到 Texture workspace 二次做 |
| 车横着/屁股朝前开 | Tripo 各模型车头轴不一致 | 实测 yaw，别抄别的车 |
| 轮子绕偏心点转 | 枢轴用了顶点质心 | AABB 几何中心（split_wheels.py 已修） |
| 分件上色全红/玻璃不对 | 分类规则顺序错 | body→roof→glass→roundish→trim；后窗并壳用 glass_patches |
| 行驶中看不到轮子 | 追尾视角被车身挡住 | chase_camera 肩部偏移平滑跟随（已修） |
| 画面糊 | Retina 未开 HiDPI / 贴图各向异性低 | allow_hidpi=true、anisotropic=8（已修） |
| Send To 子菜单打不开 | 自动化合成事件不触发 | 请用户手动点，或走 GLB 导出 |
| 截图全黑 | headless 模式 | 窗口模式跑 |
