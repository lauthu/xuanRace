#!/usr/bin/env python3
"""合成 XuanRace 主菜单背景图（"轩"字设计）。

构图：中轴线（竖直赛道笔画）右侧为半显的"干"（形似 F），笔画以赛道填充；
左侧"车"字旁替换为一辆车头朝上、车轮压在中轴线上的斯巴鲁 GC8 侧视图
（用 Godot 渲染游戏内真实模型，见 scripts/debug/render_subaru_side.gd），
车身做双色调（黑→荧光绿→白）处理以匹配海报风格。

用法：python3 tools/compose_menu_bg.py  # 输出 assets/ui/menu_bg.png
"""

from PIL import Image, ImageDraw, ImageFilter

W, H = 1920, 1080
LIME = (199, 245, 5)
ASPHALT = (40, 42, 47)
WHITE = (232, 235, 228)
TRACK_W = 120          # 赛道笔画宽
AXIS_X = 1290          # 中轴线 x
TOP_Y, MID_Y, BOT_Y = 170, 545, 940   # 干的三笔
BAR_TOP_X, BAR_MID_X = 1620, 1705     # 两横右端（干的第二横更长）

OUT = "assets/ui/menu_bg.png"
CAR = "/tmp/subaru_side_crop.png"


def segments():
    return [
        ((AXIS_X, TOP_Y), (BAR_TOP_X, TOP_Y)),   # 干 顶横
        ((AXIS_X, MID_Y), (BAR_MID_X, MID_Y)),   # 干 中横
        ((AXIS_X, TOP_Y), (AXIS_X, BOT_Y)),      # 干 竖（中轴线）
    ]


def dash_line(draw, p0, p1, width, color, dash=26, gap=20):
    """沿线段画虚线。"""
    x0, y0 = p0
    x1, y1 = p1
    length = ((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5
    if length == 0:
        return
    ux, uy = (x1 - x0) / length, (y1 - y0) / length
    d = 0.0
    while d < length:
        e = min(d + dash, length)
        draw.line([(x0 + ux * d, y0 + uy * d), (x0 + ux * e, y0 + uy * e)],
                  fill=color, width=width)
        d = e + gap


def draw_track(base, segs):
    """把一组线段画成赛道：荧光描边 + 沥青填充 + 白边线 + 中央虚线。"""
    # 荧光泛光层
    glow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    for p0, p1 in segs:
        g.line([p0, p1], fill=LIME + (150,), width=TRACK_W + 46)
    glow = glow.filter(ImageFilter.GaussianBlur(30))
    base.alpha_composite(glow)

    d = ImageDraw.Draw(base)
    for p0, p1 in segs:  # 荧光描边
        d.line([p0, p1], fill=LIME + (255,), width=TRACK_W + 14)
    for p0, p1 in segs:  # 沥青路面
        d.line([p0, p1], fill=ASPHALT + (255,), width=TRACK_W)

    # 白边线（直笔画直接偏移）
    edge = (TRACK_W // 2) - 8
    for p0, p1 in segs:
        if p0[1] == p1[1]:  # 横
            for s in (-1, 1):
                d.line([(p0[0], p0[1] + s * edge), (p1[0], p1[1] + s * edge)],
                       fill=WHITE + (255,), width=4)
        else:               # 竖
            for s in (-1, 1):
                d.line([(p0[0] + s * edge, p0[1]), (p1[0] + s * edge, p1[1])],
                       fill=WHITE + (255,), width=4)
    # 中央虚线
    for p0, p1 in segs:
        dash_line(d, p0, p1, 6, WHITE + (220,))


def duotone(img):
    """海军蓝 → 斯巴鲁拉力蓝（WR Blue）→ 白 的三色调映射。

    车身漆面在原渲染中亮度约 150，把该亮度精确映射到真车拉力蓝 (38,74,186)，
    避免高光洗白或偏紫。"""
    gray = img.convert("L")
    mid = (38, 74, 186)
    split = 150
    channels = []
    for c in range(3):
        dark, midc, high = (8, 12, 34)[c], mid[c], (222, 230, 252)[c]
        lut = []
        for i in range(256):
            if i < split:
                lut.append(int(dark + (midc - dark) * (i / split)))
            else:
                lut.append(int(midc + (high - midc) * ((i - split) / (255 - split))))
        channels.append(gray.point(lut))
    toned = Image.merge("RGB", channels)
    toned.putalpha(img.getchannel("A"))
    return toned


def _bezier(p0, p1, p2, n=24):
    pts = []
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
        pts.append((x, y))
    return pts


def draw_wind(canvas, box, rng):
    """破风气流：从鼻尖分叉、绕车身最宽处外抛、向车尾拖尾的速度线 + 飞沫。"""
    import math
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0, y0, w, h = box
    nose_y, tail_y = y0 + 8, y0 + h - 8
    mid_y = (nose_y + tail_y) / 2
    nose_x = x0 + w / 2

    lanes = []  # (x 偏移, side)
    for i in range(9):    # 左侧开阔区
        lanes.append((-(60 + i * 28 + rng.randint(0, 16)), -1))
    for i in range(3):    # 车身与中轴线之间
        lanes.append((46 + i * 22 + rng.randint(0, 8), 1))
    for off, side in lanes:
        # 起点收在鼻尖附近 → 中段外抛到气流线位置 → 尾部平行拖远
        p0 = (nose_x + side * rng.randint(4, 24), nose_y - rng.randint(20, 90))
        p1 = (nose_x + off, mid_y + rng.randint(-30, 30))
        p2 = (nose_x + off + side * rng.randint(0, 30), tail_y + rng.randint(80, 260))
        pts = _bezier(p0, p1, p2)
        color = LIME if rng.random() < 0.3 else (228, 236, 240)
        for i in range(len(pts) - 1):
            t = i / (len(pts) - 1)
            # 头部快速淡入后向车尾渐隐，最亮处贴近车头
            alpha = int(200 * min(t / 0.15, 1.0) * (1 - t) ** 0.7)
            width = max(1, int(1 + 4.5 * (1 - t)))
            d.line([pts[i], pts[i + 1]], fill=color + (alpha,), width=width)

    # 飞沫短划
    for _ in range(26):
        lx = x0 - rng.randint(20, 260)
        ly = rng.randint(int(nose_y) - 40, int(tail_y) + 120)
        ln = rng.randint(8, 34)
        d.line([(lx, ly), (lx + rng.randint(-4, 4), ly + ln)],
               fill=(228, 236, 240, rng.randint(50, 140)), width=rng.randint(1, 3))

    layer = layer.filter(ImageFilter.GaussianBlur(1.2))
    canvas.alpha_composite(layer)


def main():
    import random
    canvas = Image.new("RGBA", (W, H), (4, 5, 3, 255))
    draw_track(canvas, segments())

    # 斯巴鲁侧视图：车头朝上（原图车头朝左，顺时针转 90°），
    # 再水平镜像使车轮一侧朝右压在中轴线上，拉力蓝三色调化
    car = Image.open(CAR).convert("RGBA").rotate(-90, expand=True)
    car = car.transpose(Image.FLIP_LEFT_RIGHT)
    car = duotone(car)
    # 车旁高度与"干"字纵向范围对齐（TOP_Y..BOT_Y），比例接近真实字形
    car_h = BOT_Y - TOP_Y + 10
    scale = car_h / car.height
    car = car.resize((int(car.width * scale), car_h), Image.LANCZOS)

    # 车轮（镜像后车身右侧）压在中轴线上，与"干"字顶/底对齐
    x = AXIS_X - car.width + 26
    y = TOP_Y - 5

    # 尾迹拖影（车尾方向的多层模糊残影，增强速度感）
    rng = random.Random(7)
    ghost = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sil = Image.new("RGBA", car.size, (150, 180, 235, 0))
    sil.putalpha(car.getchannel("A").point(lambda a: int(a * 0.15)))
    for k in range(1, 4):
        ghost.alpha_composite(sil, (x, y + k * 26))
    canvas.alpha_composite(ghost.filter(ImageFilter.GaussianBlur(12)))

    canvas.alpha_composite(car, (x, y))
    draw_wind(canvas, (x, y, car.width, car.height), rng)

    canvas.convert("RGB").save(OUT)
    print("saved", OUT)


if __name__ == "__main__":
    main()
