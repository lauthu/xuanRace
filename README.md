# XuanRace 🏎️

基于 **Godot 4** 的 3D 第三人称赛车游戏框架。

## 快速开始

1. 安装 [Godot 4.x](https://godotengine.org/download)（建议 4.2 及以上）
2. 用 Godot 编辑器打开本目录（导入 `project.godot`）
3. 按 `F5` 运行，从主菜单点击「开始比赛」

## 操作方式

| 按键 | 功能 |
| --- | --- |
| `W` / `↑` | 油门 |
| `S` / `↓` | 刹车 / 倒车 |
| `A` `D` / `←` `→` | 转向 |
| `R` | 重置车辆到起点（完赛后按下重新开始） |
| `Esc` | 返回选车界面 |

## 游戏流程

主菜单 →「开始比赛」→ **第 1 步：选择车型**（F1 / 拉力 / 吉普 / 未来赛车，3D 旋转预览）
→ **第 2 步：选择颜色**（8 色色板，实时换色预览）→ **第 3 步：选择赛道**（2D 俯视预览）
→「开始比赛」→ 赛道。比赛中按 `Esc` 回到选车界面。
车型、颜色、赛道选择保存在 `GameState` Autoload 中，跨场景传递。

## 赛道系统

| 赛道 | 形状 | 路面 |
| --- | --- | --- |
| GP 赛道 | Catmull-Rom 样条专业赛道（发夹弯/S 弯/直道） | **Road Generator 插件**生成的公路：车道线、路肩、自带碰撞体 |
| 沥青赛道 | 椭圆 | 深色沥青 + 红白路缘 + 中央虚线 |
| 砂石拉力 | 圆角矩形（超椭圆） | 沙石路面 + 干黄草地 |
| 颠簸越野 | 波浪不规则环 | 泥土地 + 真实起伏地形（HeightMapShape 碰撞，车会真的颠簸） |
| 野外区域 | 方形旷野（无赛道） | 缓坡丘陵 + 蜿蜒河流——涉水时水流阻力 + 动力衰减；自由探索模式（无圈数，HUD 显示探索时间）；树木带碰撞，选赛道时开启「允许破坏」可撞倒树木 |

赛道中心线由 `scripts/track/track_shapes.gd` 统一定义，赛道生成、HUD 缩略图、
选车预览三处共用同一数据源。新增赛道：在 `TrackShapes` 加一个形状函数 +
`TrackBuilder.SURFACE_PROFILES` 加一个材质档案 + `game_state.gd` 的 `TRACKS` 加一行。

换色原理（`scripts/car/car_recolor.gd`）：Racing Kit 的扁平材质直接改写饱和度最高的
材质颜色；Car Kit 的调色板贴图则按三角形面积定位车身油漆条纹，按亮度比例替换颜色，
保留渐变明暗，车窗/轮胎/车灯不受影响。新增车型只需往 `game_state.gd` 的
`CAR_MODELS` 加一行，换色与自适应缩放全自动。

## 目录结构

```
xuanRace/
├── project.godot               # 工程配置（主场景 = 主菜单）
├── scenes/
│   ├── main.tscn               # 比赛主场景（灯光、环境、各模块组装）
│   ├── car/car.tscn            # 车辆（VehicleBody3D + Kenney F1 模型 + 追逐相机）
│   ├── track/track.tscn        # 赛道（几何由脚本程序化生成）
│   └── ui/
│       ├── main_menu.tscn      # 主菜单
│       ├── car_select.tscn     # 选车界面（3D 旋转预览）
│       └── hud.tscn            # 比赛 HUD
├── assets/
│   ├── kenney_racing_kit/      # Kenney Racing/Car Kit（CC0 开源资源，含许可说明）
│   ├── ui/menu_bg.png          # 主菜单背景图
│   └── audio/racing_bgm.wav    # 背景音乐（CC0，含许可说明）
└── scripts/
    ├── main.gd                 # 主场景逻辑：模块串联、车辆重置
    ├── core/input_setup.gd     # Autoload：运行时注册输入映射
    ├── core/game_state.gd      # Autoload：全局状态（车型/颜色/赛道/破坏开关）
    ├── core/bgm_player.gd      # Autoload：背景音乐（跨场景连续播放）
    ├── car/car_controller.gd   # 车辆物理：油门/刹车/倒车/转向
    ├── track/
    │   ├── track_builder.gd    # 程序化生成椭圆赛道、围墙、检查点、出生点
    │   ├── checkpoint.gd       # 检查点（Area3D，检测车辆通过）
    │   └── lap_manager.gd      # 计时与计圈：圈速、最快圈、完赛判定
    └── ui/
        ├── hud.gd              # HUD：速度/圈数/圈速显示
        ├── minimap.gd          # HUD 左下角：赛道缩略图（实时车点位与朝向）
        ├── speed_gauge.gd      # HUD 右下角：指针式速度表盘
        ├── ui_style.gd         # 全局 UI 样式库（荧光绿×黑主题）
        ├── car_select.gd       # 两步选车（车型 → 颜色）
        └── main_menu.gd        # 主菜单逻辑
```

## 设计要点

- **车辆物理**：基于内置 `VehicleBody3D`，前轮转向、后轮驱动。手感参数
  （动力、刹车、转角、转向灵敏度）都是 `@export`，选中 Car 节点即可在检查器中调节。
- **赛道**：`TrackBuilder` 在运行时程序化生成椭圆赛道，改 `@export` 的半径、
  路宽、检查点数量即可换一条赛道；围墙自动附带碰撞体。
- **计圈**：检查点按 `1 → N-1 → 0`（起点线）顺序通过才计一圈，防止抄近道刷圈。
- **相机**：第三人称追逐相机作为车辆子节点，固定跟随。

## 第三方组件

- **[Godot Road Generator](https://github.com/TheDuckCow/godot-road-generator)**（MIT 协议，见 `addons/road-generator/LICENSE`）：
  用于 GP 赛道的公路网格生成。`scripts/track/gp_road.gd` 在运行时沿赛道中心线
  放置 RoadPoint（朝向对齐切线，这是曲线不失控的关键）、闭环连接并触发生成，
  围墙/检查点/缩略图仍由本项目自研系统驱动，两者通过 `TrackShapes` 中心线对齐。

## 资源说明

车辆模型：
- **极速跑车** — [Quaternius](https://poly.pizza/m/Gzj704DXdr)（CC0），车头/刹车灯独立材质，前后轮独立节点
- 其余车型 — [Kenney Racing Kit / Car Kit](https://kenney.nl)（CC0），见 `assets/kenney_racing_kit/LICENSE.txt`

**车轮动画**：`car_controller.gd` 自动识别模型中名称含 "wheel" 的节点，
按包围盒计算轴心并包一层枢轴，行驶时车轮随速度滚动、前轮随方向盘偏转，
对所有车型自动生效（Quaternius 的共享后轮网格同样兼容）。

背景音乐：Hyper Ultra-Racing（CC0，OpenGameArt），见 `assets/audio/LICENSE.txt`。

调试技巧：`scripts/debug/screenshot_capture.gd` 可以无头截图当前场景 —
`Godot --path . -s res://scripts/debug/screenshot_capture.gd`，图片保存到 `/tmp/race_screenshot.png`；
`scripts/debug/drive_test.gd` 可验证车辆行驶/转向方向。

## 后续扩展方向

- [ ] 平滑跟随相机（弹簧臂 `SpringArm3D` + 插值）
- [ ] 漂移手感（侧向摩擦、手刹）
- [ ] AI 对手（沿检查点路径行驶）
- [ ] 自定义赛道模型（替换程序化赛道，保留检查点体系）
- [ ] 音效与背景音乐
- [ ] 圈速排行榜持久化
