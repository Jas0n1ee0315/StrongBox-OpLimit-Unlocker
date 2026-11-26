#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
就地 patch TEESimulator-RS classes.dex：解除 KeyMintSecurityLevelInterceptor
的 StrongBox 同時操作上限（原本 if total < 4 才放行）。

作法：把限制判斷的比較指令
    146836: 34 17 3f00   if-lt v7, v1, 00ba   （total < 4 → 放行，否則 reject）
改成一個「永遠成立」的比較
    146836: 37 77 3f00   if-le v7, v7, 00ba   （v7 <= v7 恆真 → 永遠放行）
只動 2 個 byte（34 17 → 37 77），分支 offset 3f00 不變，指令長度不變，
其餘 bytecode / 跳轉 / 方法大小完全不受影響。

接著重算 dex header 的 SHA-1 簽章與 Adler-32 校驗碼。
"""
import hashlib, zlib, struct, sys, shutil, pathlib

SRC = pathlib.Path(sys.argv[1])          # classes.dex.orig
DST = pathlib.Path(sys.argv[2])          # classes.dex.patched

# 由 dexdump 得到的檔案絕對 offset
OFF_CONST = 0x146834   # const/4 v1, #int 4  → 期望 bytes 12 41
OFF_IF    = 0x146836   # if-lt  v7, v1, +3f  → 期望 bytes 34 17 3f 00

data = bytearray(SRC.read_bytes())

# --- 1. 嚴格斷言原始 bytes，位置或版本不符就中止、不寫出 ---
assert data[OFF_CONST:OFF_CONST+2] == bytes([0x12, 0x41]), \
    f"const 位置 bytes 不符: {data[OFF_CONST:OFF_CONST+2].hex()}"
assert data[OFF_IF:OFF_IF+4] == bytes([0x34, 0x17, 0x3f, 0x00]), \
    f"if-lt 位置 bytes 不符: {data[OFF_IF:OFF_IF+4].hex()}"
print(f"[OK] 原始指令確認：const/4 v1,#4 @0x{OFF_CONST:x} ; if-lt v7,v1,+3f @0x{OFF_IF:x}")

# --- 2. 只改比較指令：34 17 → 37 77（if-lt v7,v1 → if-le v7,v7，恆真）---
data[OFF_IF+0] = 0x37   # opcode if-le
data[OFF_IF+1] = 0x77   # vA=v7, vB=v7
# data[OFF_IF+2:OFF_IF+4] (3f 00) 不動
print(f"[OK] 已改為：if-le v7,v7,+3f（恆真，永遠放行）")

# --- 3. 重算 dex header：先 SHA-1 簽章(12..32 覆蓋 32..end)，再 Adler-32(8..12 覆蓋 12..end) ---
sig = hashlib.sha1(data[32:]).digest()          # 20 bytes → header[12:32]
data[12:32] = sig
adler = zlib.adler32(bytes(data[12:])) & 0xffffffff
struct.pack_into('<I', data, 8, adler)           # header[8:12]
print(f"[OK] 重算 signature(SHA-1)={sig.hex()[:16]}… checksum(Adler32)=0x{adler:08x}")

DST.write_bytes(data)
print(f"[OK] 已寫出 {DST}  ({len(data)} bytes，與原檔同大小={len(data)==SRC.stat().st_size})")
