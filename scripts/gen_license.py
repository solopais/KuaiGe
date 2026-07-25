#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MV Extractor 离线激活码签发工具
================================
用 Ed25519 私钥对激活载荷签名，生成离线激活码（无需联网）。
激活码格式： base64(payload) + "." + base64(ed25519签名)
  payload = {"v":1,"plan":"pro","exp":0,"dev":"","nonce":"..."}
    - exp=0  → 永久有效
    - exp>0  → Unix 到期时间戳（秒）
    - dev="" → 首次激活时绑定设备（一张码单设备）
    - dev=xxx→ 仅允许指定设备激活（需客户提供其设备ID，一般不填）

用法：
  python gen_license.py                       # 生成一张永久专业版码
  python gen_license.py --days 30             # 30 天专业版
  python gen_license.py --dev <设备ID>         # 绑定指定设备
  python gen_license.py --count 5 --days 365  # 批量生成 5 张一年期

注意：此文件含私钥，务必妥善保管，切勿泄露或提交到公开仓库。
"""
import argparse
import base64
import json
import os
import secrets
import time

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

# ⚠️ 私钥（原始 32 字节 base64）。与 App 内公钥配对。切勿泄露。
PRIVATE_KEY_B64 = "m3uxkbi5VJtm/bWfuzoYB4H8NUD/uq64jh/Jwxu+VHU="


def _priv_from_b64(b64str: str) -> Ed25519PrivateKey:
    return Ed25519PrivateKey.from_private_bytes(base64.b64decode(b64str))


def make_code(plan: str = "pro", exp: int = 0, dev: str = "",
              nonce: str = None) -> str:
    priv = _priv_from_b64(PRIVATE_KEY_B64)
    if nonce is None:
        nonce = base64.b64encode(secrets.token_bytes(6)).decode()
    payload = json.dumps(
        {"v": 1, "plan": plan, "exp": exp, "dev": dev, "nonce": nonce},
        separators=(",", ":"), sort_keys=True
    ).encode("utf-8")
    sig = priv.sign(payload)
    return base64.b64encode(payload).decode() + "." + base64.b64encode(sig).decode()


def main():
    ap = argparse.ArgumentParser(description="MV Extractor 离线激活码签发")
    ap.add_argument("--plan", default="pro", help="版本计划（默认 pro）")
    ap.add_argument("--days", type=int, default=0,
                    help="有效天数，0=永久（默认）")
    ap.add_argument("--dev", default="", help="绑定设备ID（留空=首次激活绑定）")
    ap.add_argument("--count", type=int, default=1, help="生成数量（默认 1）")
    ap.add_argument("--out", default="", help="可选：导出到文件（每行一个码）")
    args = ap.parse_args()

    exp = 0 if args.days <= 0 else int(time.time()) + args.days * 86400

    codes = []
    for _ in range(max(1, args.count)):
        codes.append(make_code(plan=args.plan, exp=exp, dev=args.dev))

    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write("\n".join(codes) + "\n")
        print(f"已生成 {len(codes)} 张激活码 → {os.path.abspath(args.out)}")
    else:
        print(f"生成 {len(codes)} 张激活码（{'永久' if exp == 0 else '到期 ' + time.strftime('%Y-%m-%d', time.localtime(exp))}）：")
        for c in codes:
            print("  " + c)


if __name__ == "__main__":
    main()
