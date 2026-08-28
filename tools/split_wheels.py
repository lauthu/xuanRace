#!/usr/bin/env python3
"""把 AI 生成的单网格车模拆分为 车身 + 4 个独立轮子（带轴心）。

用法: python3 split_wheels.py 输入.glb 输出.glb
轮子命名 wheel_fl/fr/rl/rr，可被游戏内车轮动画系统自动识别。
"""
import json, struct, sys
import numpy as np

COMP = {5120:'b',5121:'B',5122:'h',5123:'H',5125:'I',5126:'f'}
NCOMP = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}

def load_glb(path):
    data = open(path, 'rb').read()
    ln, _ = struct.unpack_from('<II', data, 12)
    js = json.loads(data[20:20+ln])
    off = 20 + ln
    bln, _ = struct.unpack_from('<II', data, off)
    return js, data[off+8:off+8+bln]

def get_acc(js, bin_data, idx):
    acc = js['accessors'][idx]
    bv = js['bufferViews'][acc['bufferView']]
    start = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
    n = acc['count'] * NCOMP[acc['type']]
    arr = np.frombuffer(bin_data, dtype=COMP[acc['componentType']], count=n, offset=start)
    return arr.reshape(-1, NCOMP[acc['type']]) if NCOMP[acc['type']] > 1 else arr

def kmeans4(pts, iters=30):
    # 用四个角落的极值点初始化
    cx = np.array([
        [pts[:,0].min(), pts[:,1].min()], [pts[:,0].min(), pts[:,1].max()],
        [pts[:,0].max(), pts[:,1].min()], [pts[:,0].max(), pts[:,1].max()],
    ], dtype=np.float64)
    for _ in range(iters):
        d = ((pts[:,None,:] - cx[None,:,:])**2).sum(axis=2)
        lab = d.argmin(axis=1)
        for k in range(4):
            if (lab==k).any():
                cx[k] = pts[lab==k].mean(axis=0)
    return cx, lab

def main(src, dst):
    js, bin_data = load_glb(src)
    prim = js['meshes'][0]['primitives'][0]
    pos = get_acc(js, bin_data, prim['attributes']['POSITION']).astype(np.float32)
    nrm = get_acc(js, bin_data, prim['attributes']['NORMAL']).astype(np.float32) if 'NORMAL' in prim['attributes'] else None
    uv  = get_acc(js, bin_data, prim['attributes']['TEXCOORD_0']).astype(np.float32) if 'TEXCOORD_0' in prim['attributes'] else None
    idx = get_acc(js, bin_data, prim['indices']).astype(np.int64)
    tris = idx.reshape(-1, 3)

    mn, mx = pos.min(axis=0), pos.max(axis=0)
    h = mx[1] - mn[1]
    print(f"包围盒 min={mn.round(3)} max={mx.round(3)}")

    # 底部 45% 高度的点做 4 聚类找轮轴
    band = pos[pos[:,1] < mn[1] + 0.45*h][:, [0,2]].astype(np.float64)
    centers, _ = kmeans4(band)
    # 轮轴 y：用每个聚类底部点带的中位 y
    # 真实轮径：近处点的 y 范围即轮胎直径，半径取其一半略放大
    band3 = pos[pos[:,1] < mn[1] + 0.45*h]
    wheel_r, axle_y = [], []
    for c in centers:
        d = np.linalg.norm(band3[:,[0,2]] - c, axis=1)
        near = band3[d < 0.06]
        yext = near[:,1].max() - near[:,1].min()
        wheel_r.append(yext / 2 * 1.12)
        axle_y.append((near[:,1].max() + near[:,1].min()) / 2)
    print("轮轴中心:", centers.round(3).tolist(), " 半径:", [round(float(r),3) for r in wheel_r])

    # 三角形归属：质心到轮轴的 xz 距离 < 半径 → 该轮子；否则归车身
    cent = pos[tris].mean(axis=1)
    assign = -np.ones(len(tris), dtype=np.int64)
    for wi, c in enumerate(centers):
        c3 = np.array([c[0], axle_y[wi], c[1]])
        # 三维球判定：只取轮轴附近的轮胎/轮毂，排除上方轮拱与侧裙
        d = np.linalg.norm(cent - c3, axis=1)
        assign[(d < wheel_r[wi] * 0.96) & (assign < 0)] = wi
    counts = [(assign==k).sum() for k in range(4)] + [(assign<0).sum()]
    print("各轮三角形数:", counts[:4], " 车身:", counts[4])
    if (assign < 0).sum() == 0:
        print("警告: 无车身三角形，半径过大")
        sys.exit(1)

    # 轮子按 x 排序命名（x 小=后, 大=前；z 小=左, 大=右）
    order = sorted(range(4), key=lambda k: centers[k][0])
    names = {}
    for k in order:
        side = 'l' if centers[k][1] < 0 else 'r'
        front = 'f' if centers[k][0] > np.median(centers[:,0]) else 'r'
        names[k] = f"wheel_{front}{side}"

    # 构建输出 GLB
    out = {
        "asset": {"version": "2.0", "generator": "xuanrace wheel splitter"},
        "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "RootNode", "children": []}],
        "meshes": [], "accessors": [], "bufferViews": [],
        "buffers": [],
        "materials": js.get('materials', []),
        "textures": js.get('textures', []),
        "images": js.get('images', []),
        "samplers": js.get('samplers', []),
    }
    blob = bytearray()
    def pad():
        while len(blob) % 4: blob.append(0)
    def add_acc(arr, target_type, comp_type):
        pad()
        raw = arr.tobytes() if isinstance(arr, np.ndarray) else arr
        bv_i = len(out['bufferViews'])
        out['bufferViews'].append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw)})
        blob.extend(raw)
        acc_i = len(out['accessors'])
        acc = {
            "bufferView": bv_i, "componentType": comp_type,
            "count": int(np.asarray(arr).size // NCOMP[target_type]),
            "type": target_type,
        }
        flat = np.asarray(arr).reshape(-1, NCOMP[target_type])
        acc["min"] = flat.min(axis=0).tolist() if target_type == 'VEC3' else None
        acc["max"] = flat.max(axis=0).tolist() if target_type == 'VEC3' else None
        if acc["min"] is None: del acc["min"], acc["max"]
        out['accessors'].append(acc)
        return acc_i

    def add_part(name, tri_sel, pivot=None):
        sel = tris[tri_sel]
        used = np.unique(sel)
        remap = np.full(len(pos), -1, dtype=np.int64)
        remap[used] = np.arange(len(used))
        p = pos[used].copy()
        if pivot is not None:
            p -= np.array(pivot, dtype=np.float32)
        attrs = {"POSITION": add_acc(p, 'VEC3', 5126)}
        if nrm is not None:
            attrs["NORMAL"] = add_acc(nrm[used], 'VEC3', 5126)
        if uv is not None:
            attrs["TEXCOORD_0"] = add_acc(uv[used], 'VEC2', 5126)
        new_idx = remap[sel].astype(np.uint32)
        mesh_i = len(out['meshes'])
        out['meshes'].append({
            "name": name,
            "primitives": [{"attributes": attrs, "indices": add_acc(new_idx, 'SCALAR', 5125), "material": 0}],
        })
        node = {"name": name, "mesh": mesh_i}
        if pivot is not None:
            node["translation"] = [float(v) for v in pivot]
        out['nodes'][0]['children'].append(len(out['nodes']))
        out['nodes'].append(node)

    for k, name in names.items():
        c3 = np.array([centers[k][0], axle_y[k], centers[k][1]], dtype=np.float64)
        add_part(name, assign==k, pivot=c3)
    add_part("body", assign<0)

    # 拷贝图片 bufferViews（原样复制图像二进制）
    for img in out['images']:
        bv = img.get('bufferView')
        if bv is None: continue
        src_bv = js['bufferViews'][bv]
        start = src_bv.get('byteOffset', 0)
        raw = bin_data[start:start+src_bv['byteLength']]
        pad()
        img['bufferView'] = len(out['bufferViews'])
        out['bufferViews'].append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw)})
        blob.extend(raw)

    pad()
    out['buffers'] = [{"byteLength": len(blob)}]
    js_out = json.dumps(out, separators=(',',':')).encode()
    while len(js_out) % 4: js_out += b' '
    total = 12 + 8 + len(js_out) + 8 + len(blob)
    with open(dst, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(js_out), 0x4E4F534A))
        f.write(js_out)
        f.write(struct.pack('<II', len(blob), 0x004E4942))
        f.write(blob)
    import os
    print(f"输出 {dst}: {os.path.getsize(dst)/1e6:.1f} MB, 节点: {[n.get('name') for n in out['nodes']]}")

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
