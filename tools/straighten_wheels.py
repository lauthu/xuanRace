#!/usr/bin/env python3
"""矫正 GLB 中指定部件的烘焙偏航角（如 AI 生成模型的前轮外八/内八）。

原理：对部件顶点做 PCA，最小特征值方向即圆柱形部件（轮子）的轴向；
若轴向在 X-Z 平面内偏离 X 轴，则绕部件 AABB 中心反向旋转顶点和法线，
使轮轴与 X 轴对齐。节点变换必须为单位阵，accessor 不得共享（Tripo 导出均满足）。

用法: python3 tools/straighten_wheels.py <file.glb> <part_name> [part_name ...]
"""
import json
import struct
import sys

import numpy as np

CTYPE_DT = {5120: np.int8, 5121: np.uint8, 5122: np.int16,
            5123: np.uint16, 5125: np.uint32, 5126: np.float32}
TYPE_N = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def load_glb(path):
    with open(path, "rb") as f:
        magic, ver, total = struct.unpack("<III", f.read(12))
        assert magic == 0x46546C67, "not a GLB"
        clen, ctype = struct.unpack("<II", f.read(8))
        js = json.loads(f.read(clen))
        blen, btype = struct.unpack("<II", f.read(8))
        assert btype == 0x004E4942, "missing BIN chunk"
        buf = bytearray(f.read(blen))
    return js, buf


def save_glb(path, js, bin_chunk):
    payload = json.dumps(js, separators=(",", ":")).encode()
    payload += b" " * (-len(payload) % 4)
    bin_chunk += b"\x00" * (-len(bin_chunk) % 4)
    total = 12 + 8 + len(payload) + 8 + len(bin_chunk)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(payload), 0x4E4F534A))
        f.write(payload)
        f.write(struct.pack("<II", len(bin_chunk), 0x004E4942))
        f.write(bin_chunk)


def acc_view(js, ai):
    """返回 (dtype, n_comp, count, base_offset, stride)。"""
    acc = js["accessors"][ai]
    bv = js["bufferViews"][acc["bufferView"]]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    n = TYPE_N[acc["type"]]
    dt = CTYPE_DT[acc["componentType"]]
    stride = bv.get("byteStride", np.dtype(dt).itemsize * n)
    return dt, n, acc["count"], off, stride


def read_vec3(js, buf, ai):
    dt, n, count, off, stride = acc_view(js, ai)
    out = np.zeros((count, n), dtype=np.float64)
    for i in range(count):
        out[i] = np.frombuffer(bytes(buf[off + i * stride: off + i * stride + n * 8]),
                               dtype=dt, count=n)
    return out


def write_vec3(js, buf, ai, values):
    dt, n, count, off, stride = acc_view(js, ai)
    for i in range(count):
        struct.pack_into("<3f", buf, off + i * stride, *values[i].astype(np.float32))


def pca_yaw(pos):
    c = pos.mean(axis=0)
    w, V = np.linalg.eigh(np.cov((pos - c).T))
    axle = V[:, 0]
    return np.arctan2(axle[2], axle[0])


def straighten(js, buf, part_name, node):
    mesh = js["meshes"][node["mesh"]]
    for prim in mesh["primitives"]:
        pa = prim["attributes"]["POSITION"]
        pos = read_vec3(js, buf, pa)
        yaw = pca_yaw(pos)
        deg = np.degrees(yaw)
        if abs(deg) < 2.0:
            print(f"{part_name}: 偏航 {deg:.2f}°，无需矫正")
            continue
        if abs(deg) > 45.0:
            print(f"{part_name}: 偏航 {deg:.2f}° 超过 45°，疑似主轴误判，跳过")
            continue
        mn, mx = pos.min(axis=0), pos.max(axis=0)
        center = (mn + mx) / 2.0
        # R_y(yaw) 把 atan2(z,x) 角度旋转 -yaw，使轮轴与 X 轴对齐（绕 Y 过 AABB 中心）
        c, s = np.cos(yaw), np.sin(yaw)
        R = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
        pos_new = (pos - center) @ R.T + center
        write_vec3(js, buf, pa, pos_new)
        if "NORMAL" in prim["attributes"]:
            na = prim["attributes"]["NORMAL"]
            nrm = read_vec3(js, buf, na)
            write_vec3(js, buf, na, nrm @ R.T)
        print(f"{part_name}: 矫正 {deg:.2f}° -> 0°（绕中心 {np.round(center, 3)}）")


def main():
    path = sys.argv[1]
    targets = set(sys.argv[2:])
    js, buf = load_glb(path)
    for node in js["nodes"]:
        if "mesh" in node and node.get("name") in targets:
            assert "rotation" not in node and "matrix" not in node, \
                f"{node['name']} 节点带变换，需先处理节点变换"
            straighten(js, buf, node["name"], node)
    save_glb(path, js, buf)
    print("已写回", path)


if __name__ == "__main__":
    main()
