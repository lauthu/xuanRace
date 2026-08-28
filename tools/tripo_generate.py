#!/usr/bin/env python3
"""Tripo API 车模生成管线：文生 3D → 轮询 → 下载 GLB → 拆分轮子。

用法:
  TRIPO_API_KEY=tsk_xxx python3 tools/tripo_generate.py "prompt 文本" 输出名

示例:
  TRIPO_API_KEY=tsk_xxx python3 tools/tripo_generate.py "A 1970 Dodge Charger..." charger_pro
产物: assets/vehicles/<输出名>.glb + <输出名>_split.glb（拆轮子后）
"""
import json, os, sys, time, urllib.request, urllib.error

API = "https://api.tripo3d.ai/v2/openapi"


def req(method, path, key, payload=None):
    data = json.dumps(payload).encode() if payload else None
    r = urllib.request.Request(
        API + path, data=data, method=method,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    with urllib.request.urlopen(r, timeout=60) as resp:
        return json.loads(resp.read())


def main():
    key = os.environ.get("TRIPO_API_KEY")
    if not key:
        sys.exit("缺少 TRIPO_API_KEY 环境变量")
    prompt, name = sys.argv[1], sys.argv[2]
    out_dir = os.path.join(os.path.dirname(__file__), "..", "assets", "vehicles")

    print("创建任务: text_to_model ...")
    resp = req("POST", "/task", key, {
        "type": "text_to_model",
        "prompt": prompt,
        "model_version": "v3.1-20250813",
        "texture": True,
        "pbr": True,
    })
    task_id = resp["data"]["task_id"]
    print("任务 ID:", task_id)

    while True:
        time.sleep(8)
        task = req("GET", f"/task/{task_id}", key)["data"]
        status = task.get("status")
        print(f"  状态: {status} {task.get('progress', 0)}%")
        if status == "success":
            break
        if status in ("failed", "cancelled"):
            sys.exit("任务失败: " + json.dumps(task)[:500])

    result = task.get("result", {})
    print("result keys:", list(result.keys()))
    url = None
    for k in ("pbr_model", "model", "base_model"):
        if k in result and result[k].get("url"):
            url = result[k]["url"]
            print(f"下载地址 ({k}):", url[:80], "...")
            break
    if not url:
        print(json.dumps(result, indent=1)[:1500])
        sys.exit("没找到模型下载地址")

    out = os.path.join(out_dir, f"{name}.glb")
    urllib.request.urlretrieve(url, out)
    size = os.path.getsize(out) / 1e6
    print(f"已下载 {out} ({size:.1f} MB)")

    # 拆轮子
    split = out.replace(".glb", "_split.glb")
    import subprocess
    r = subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "split_wheels.py"), out, split])
    if r.returncode == 0:
        print("拆轮子完成:", split)


if __name__ == "__main__":
    main()
