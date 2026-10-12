#!/usr/bin/env python3
"""
make_sounds.py — 生成棋钟用的三个提示音（16bit 单声道 WAV，无第三方依赖）

    python tools/make_sounds.py

产出（与网页版 Web Audio 现场合成的音色对应）：
    assets/sounds/click.wav   走子按键：40ms 方波滴答
    assets/sounds/tick.wav    读秒最后 10 秒：每秒一下
    assets/sounds/alarm.wav   超时警报：880Hz 五连响

想改音色直接调下面的参数即可，改完重跑本脚本。
"""
import math
import os
import struct
import wave

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")


def tone(freq, dur, vol, kind="square", decay=18.0):
    """一段带指数衰减包络的单音。kind: square / sine"""
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-decay * t)
        if t < 0.002:                      # 2ms 淡入，避免起音爆音
            env *= t / 0.002
        if kind == "square":
            s = 1.0 if math.sin(2.0 * math.pi * freq * t) >= 0.0 else -1.0
        else:
            s = math.sin(2.0 * math.pi * freq * t)
        out.append(s * env * vol)
    return out


def silence(dur):
    return [0.0] * int(SR * dur)


def write_wav(path, samples):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s)) * 32000)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))
    print("OK   %s  %d bytes  (%.2f s)" % (
        os.path.relpath(path).replace("\\", "/"),
        os.path.getsize(path),
        len(samples) / SR,
    ))


def main():
    # 走子按键：很短的方波滴答（对应网页版 1500Hz / 30ms）
    write_wav(os.path.join(OUT_DIR, "click.wav"), tone(1500.0, 0.040, 0.55, "square", 60.0))

    # 读秒每秒提示（对应网页版 1320Hz / 50ms）
    write_wav(os.path.join(OUT_DIR, "tick.wav"), tone(1320.0, 0.055, 0.60, "square", 45.0))

    # 超时警报：五连响（对应网页版 alarm：880Hz × 5，间隔 240ms）
    beep = tone(880.0, 0.160, 0.75, "sine", 9.0)
    alarm = []
    for i in range(5):
        alarm += beep
        if i < 4:
            alarm += silence(0.080)
    write_wav(os.path.join(OUT_DIR, "alarm.wav"), alarm)


if __name__ == "__main__":
    main()
