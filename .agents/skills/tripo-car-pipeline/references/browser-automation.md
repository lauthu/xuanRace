# Tripo Studio 浏览器自动化细节

用 Browser Use（node_repl）操作 https://studio.tripo3d.ai 时的经验。每次会话内核是全新的，bootstrap 要重新做；模块缓存不保留。

## 登录与环境

- 需要用户已登录且**开 VPN**（国内网络直连不通）。发现页面打不开/超时，先让用户确认 VPN。
- 页面 `goto` 经常超时但**实际已加载**：超时后别放弃，直接 `page.content()` 或截图看状态。

## generate-image 页

- prompt 输入框 fill 后要**按字符数校验**是否真的填进去（React 受控组件有时只填了一半）。
- 4 张候选图出来后点击选中，再点生成 3D 的按钮。按钮文案随版本变，用 role+部分文案模糊匹配，匹配不到就截图看。

## 生成参数面板

- **Generate in Parts 与 Texture 互斥**：开 Texture 会自动关 Parts。顺序：先关 Texture，再开 Parts，最后截图确认两个开关状态再点生成。
- 生成耗时几分钟，轮询用"工作区页出现顶点数/部件列表"作为完成信号，别用固定 sleep。

## Export 面板

- Export 按钮在模型 workspace 页左下区域。面板里 **Send To 子菜单对合成 hover/click 不响应**（DOM 里根本没有 godot/blender/unity 条目，图标在 hover 时转圈但菜单不展开）——用户手动操作可以打开。自动化策略：把面板开好，请用户点 Send To → Send to Godot。
- 走 GLB 下载时：点黄色 Export 确认按钮要用 **dialog 作用域的 locator 精确定位**（页面上有多个 Export 字样按钮）。下载事件经常不发，对话框空关；失败就重试，Charger 那次是重试多轮后在 22:23 成功的。Camaro 贴图版自动化下载始终没成功，最后靠 Bridge。
- IAB（内置浏览器）**不能上传文件**，所有需要上传参考图的操作做不了。

## DCC Bridge 确认接收

推送成功后：

```bash
ls -lt /Users/liuxinyu/Projects/xuanRace/TripoModels/   # 最新目录在最上
tail -5 /tmp/godot_editor.log                          # [Tripo Bridge] Client connected / 接收日志
```

收到的目录里是 `<name>.fbx` + `<name>.fbm/`（贴图文件夹）。Godot 直接能导入 FBX，但如果要跑 `tools/split_wheels.py`（它只认 GLB），先在编辑器里转存或改用 FBX 路径直接配进 CAR_MODELS。

## 通用

- 截图（`include_screenshot=true`）只用于确实需要视觉确认时，费 token。
- 任何点击前先 `get_app_state` 拿 state_id，用 element target；坐标点击是最后手段。
- 页面结构随 Tripo 改版会变，文案匹配失败时截图 + 打印 `document.body.innerText` 前几千字符找线索。
