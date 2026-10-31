#!/usr/bin/env python3
"""解压 TBHHelper zip：修复 Windows GBK 文件名（PowerShell Compress-Archive 无 UTF-8 标志）。"""
import os
import sys
import zipfile


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: unpack-helper.py <zip> <dest>", file=sys.stderr)
        return 2
    src, dest = sys.argv[1], sys.argv[2]
    os.makedirs(dest, exist_ok=True)
    with zipfile.ZipFile(src) as z:
        for info in z.infolist():
            name = info.filename
            # 非 UTF-8 标志的 zip 名按 cp437 读取，还原为 GBK
            if not (info.flag_bits & 0x800):
                try:
                    fixed = name.encode("cp437").decode("gbk")
                    if any(ch in fixed for ch in "??"):
                        raise ValueError("suspicious char")
                    name = fixed
                except Exception:
                    name = name.encode("cp437", "replace").decode("gbk", "replace")
            name = name.replace("\\", "/")
            target = os.path.normpath(os.path.join(dest, name))
            if not target.startswith(os.path.abspath(dest)):
                print(f"skip unsafe path: {name}", file=sys.stderr)
                continue
            if info.is_dir() or name.endswith("/"):
                os.makedirs(target, exist_ok=True)
                continue
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with z.open(info) as f, open(target, "wb") as out:
                while True:
                    chunk = f.read(1 << 20)
                    if not chunk:
                        break
                    out.write(chunk)
            if info.external_attr >> 16 & 0o111:
                os.chmod(target, 0o755)
    print("unpacked →", dest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
