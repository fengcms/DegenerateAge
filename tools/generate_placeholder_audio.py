"""生成第一章可替换的原创占位音频，无外部素材或许可依赖。"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path


RATE = 22_050
OUT = Path(__file__).resolve().parents[1] / "assets/audio"
RNG = random.Random(3172)


def write(name: str, samples: list[float]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as target:
        target.setnchannels(1)
        target.setsampwidth(2)
        target.setframerate(RATE)
        target.writeframes(b"".join(struct.pack("<h", max(-32767, min(32767, int(x * 32767)))) for x in samples))


def tone(duration: float, start: float, end: float, volume: float = 0.35, noise: float = 0.0) -> list[float]:
    count = int(RATE * duration)
    result = []
    phase = 0.0
    for i in range(count):
        t = i / count
        freq = start + (end - start) * t
        phase += 2 * math.pi * freq / RATE
        attack = min(1.0, t * 85.0)
        release = (1.0 - t) ** 2.2
        result.append((math.sin(phase) * 0.8 + math.sin(phase * 2) * 0.2
                       + (RNG.random() * 2 - 1) * noise) * attack * release * volume)
    return result


def melody(notes: list[tuple[float, float, float]], duration: float, volume: float) -> list[float]:
    result = [0.0] * int(RATE * duration)
    for start, frequency, length in notes:
        wavelet = tone(length, frequency, frequency, volume)
        offset = int(start * RATE)
        for i, sample in enumerate(wavelet):
            if offset + i < len(result):
                result[offset + i] += sample
    return result


def ambience() -> list[float]:
    duration = 12.0
    chord = [130.81, 155.56, 196.0]
    notes = melody([(0.4, 261.63, 1.2), (3.4, 233.08, 1.1),
                    (6.4, 196.0, 1.3), (9.4, 233.08, 1.1)], duration, 0.035)
    result = []
    for i, pluck in enumerate(notes):
        t = i / RATE
        pad = sum(math.sin(2 * math.pi * f * t) for f in chord) / len(chord)
        breath = 0.65 + 0.35 * math.sin(2 * math.pi * t / duration) ** 2
        # 循环首尾落在同一相位；轻微渐入渐出压住量化接缝。
        edge = min(1.0, t / 0.12, (duration - t) / 0.12)
        result.append((pad * 0.075 * breath + pluck) * edge)
    return result


def main() -> None:
    write("hit.wav", tone(0.12, 230, 120, noise=0.2))
    write("hurt.wav", tone(0.25, 160, 72, noise=0.15))
    write("death.wav", tone(0.7, 190, 45, volume=0.3, noise=0.08))
    write("pickup.wav", melody([(0.0, 523.25, 0.14), (0.08, 783.99, 0.19)], 0.3, 0.3))
    write("level.wav", melody([(0.0, 392.0, 0.28), (0.18, 523.25, 0.28),
                               (0.36, 659.25, 0.48)], 0.9, 0.25))
    write("equip.wav", melody([(0.0, 440.0, 0.17), (0.1, 659.25, 0.22)], 0.35, 0.22))
    write("boss.wav", tone(0.85, 110, 78, volume=0.4, noise=0.1))
    write("ambient_loop.wav", ambience())


if __name__ == "__main__":
    main()
