"""Синтез звуков Wolf: из кода в WAV.

Звука в игре не было вообще. Сэмплов со свободной лицензией мы не берём —
как и с моделями, всё своё, поэтому звуки СИНТЕЗИРУЮТСЯ здесь и кладутся в
godot/assets/audio.

Всё детерминировано: свой генератор псевдослучайных чисел с фиксированным
зерном, так что пересборка даёт те же файлы и не шумит в диффе.

Формат: 22050 Гц, моно, 16 бит — на удар ножом больше не нужно, а весит
вчетверо меньше студийного.

Запуск:  python3 tools/audio/synth.py
"""

import math
import os
import struct
import wave

SR = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "..", "godot", "assets", "audio")


class Rng:
    """Свой ГПСЧ: random из стандартной библиотеки меняется между версиями,
    а файлы лежат в репозитории и не должны переписываться на пустом месте."""

    def __init__(self, seed: int):
        self.s = seed & 0xFFFFFFFF

    def next(self) -> float:
        self.s = (1664525 * self.s + 1013904223) & 0xFFFFFFFF
        return self.s / 2147483648.0 - 1.0     # [-1, 1)


def env(n: int, attack: float, decay: float, power: float = 1.0) -> list:
    """Огибающая: быстрый подъём, затем спад заданной крутизны."""
    a = max(1, int(attack * SR))
    out = []
    for i in range(n):
        if i < a:
            v = i / a
        else:
            t = (i - a) / max(1.0, decay * SR)
            v = math.exp(-t * 3.0)
        out.append(v ** power)
    return out


def noise(n: int, rng: Rng) -> list:
    return [rng.next() for _ in range(n)]


def tone(n: int, f0: float, f1: float, kind: str = "sin") -> list:
    """Тон с линейной разводкой частоты от f0 к f1."""
    out = []
    ph = 0.0
    for i in range(n):
        f = f0 + (f1 - f0) * (i / max(1, n - 1))
        ph += f / SR
        x = ph % 1.0
        if kind == "sin":
            out.append(math.sin(x * math.tau))
        elif kind == "saw":
            out.append(2.0 * x - 1.0)
        elif kind == "sqr":
            out.append(1.0 if x < 0.5 else -1.0)
        else:
            out.append(math.sin(x * math.tau))
    return out


def lowpass(sig: list, cutoff: float) -> list:
    """Однополюсный фильтр: убирает песок из шума и делает его «телом»."""
    a = math.exp(-2.0 * math.pi * cutoff / SR)
    out = []
    y = 0.0
    for x in sig:
        y = x * (1.0 - a) + y * a
        out.append(y)
    return out


def highpass(sig: list, cutoff: float) -> list:
    lp = lowpass(sig, cutoff)
    return [x - y for x, y in zip(sig, lp)]


def bandpass(sig: list, lo: float, hi: float) -> list:
    return lowpass(highpass(sig, lo), hi)


def resonator(sig: list, freq: float, q: float) -> list:
    """Резонанс: даёт металлу звон, а голосу — форманту."""
    w = 2.0 * math.pi * freq / SR
    r = math.exp(-w / max(0.5, q))
    a1 = 2.0 * r * math.cos(w)
    a2 = -r * r
    out = []
    y1 = 0.0
    y2 = 0.0
    for x in sig:
        y = x + a1 * y1 + a2 * y2
        out.append(y)
        y2 = y1
        y1 = y
    return out


def mix(*sigs) -> list:
    n = max(len(s) for s in sigs)
    out = [0.0] * n
    for s in sigs:
        for i, v in enumerate(s):
            out[i] += v
    return out


def apply(sig: list, e: list) -> list:
    return [s * e[i] for i, s in enumerate(sig)]


def drive(sig: list, amount: float) -> list:
    """Мягкое ограничение: добавляет грязи, не щёлкая."""
    return [math.tanh(x * amount) for x in sig]


def delay_tail(sig: list, ms: float, feedback: float, times: int = 3) -> list:
    """Простое эхо — намёк на бетонный коридор."""
    d = int(SR * ms / 1000.0)
    out = list(sig) + [0.0] * (d * times)
    for k in range(1, times + 1):
        g = feedback ** k
        for i, v in enumerate(sig):
            j = i + d * k
            if j < len(out):
                out[j] += v * g
    return out


def normalize(sig: list, peak: float = 0.85) -> list:
    m = max(1e-6, max(abs(x) for x in sig))
    return [x / m * peak for x in sig]


def write(name: str, sig: list) -> str:
    path = os.path.join(os.path.abspath(OUT_DIR), name + ".wav")
    data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, x)) * 32767)) for x in sig)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    return path


# --- Сами звуки -----------------------------------------------------------

def s_hit_flesh(rng: Rng) -> list:
    """Удар по телу: глухой шлепок и короткий влажный хвост."""
    n = int(0.30 * SR)
    body = apply(tone(n, 180, 60), env(n, 0.002, 0.06, 1.4))
    wet = apply(lowpass(noise(n, rng), 900), env(n, 0.001, 0.10, 2.0))
    return normalize(drive(mix(body, [w * 0.7 for w in wet]), 1.6), 0.8)


def s_hit_block(rng: Rng) -> list:
    """Удар в блок: металлический лязг с звоном."""
    n = int(0.45 * SR)
    hit = apply(noise(n, rng), env(n, 0.001, 0.03, 1.0))
    ring = mix(resonator(hit, 1850, 26.0), resonator(hit, 2790, 20.0),
               resonator(hit, 4100, 14.0))
    low = apply(tone(n, 260, 120), env(n, 0.002, 0.05))
    return normalize(mix([r * 0.5 for r in ring], low), 0.75)


def s_swing(rng: Rng) -> list:
    """Замах: шорох воздуха с подъёмом и спадом."""
    n = int(0.26 * SR)
    sweep = []
    for i in range(n):
        t = i / n
        sweep.append(600 + 2200 * math.sin(t * math.pi))
    src = noise(n, rng)
    out = []
    y = 0.0
    for i, x in enumerate(src):
        a = math.exp(-2.0 * math.pi * sweep[i] / SR)
        y = x * (1.0 - a) + y * a
        out.append(y)
    return normalize(apply(out, env(n, 0.05, 0.09, 1.2)), 0.55)


def s_step(rng: Rng) -> list:
    """Шаг: короткий щелчок подошвы и тихое тело."""
    n = int(0.14 * SR)
    click = apply(bandpass(noise(n, rng), 700, 5200), env(n, 0.001, 0.02, 1.6))
    body = apply(tone(n, 120, 70), env(n, 0.002, 0.03))
    return normalize(mix(click, [b * 0.6 for b in body]), 0.4)


def s_death(rng: Rng) -> list:
    """Смерть: оседающий хрип."""
    n = int(1.1 * SR)
    voice = apply(tone(n, 210, 70, "saw"), env(n, 0.03, 0.5, 1.2))
    voice = resonator(voice, 700, 8.0)
    breath = apply(bandpass(noise(n, rng), 300, 2600), env(n, 0.05, 0.6, 1.5))
    return normalize(mix([v * 0.8 for v in voice], [b * 0.5 for b in breath]), 0.7)


def s_scream(rng: Rng) -> list:
    """Крик гражданского: высокий, с дрожью."""
    n = int(0.9 * SR)
    ph = 0.0
    raw = []
    for i in range(n):
        t = i / n
        f = 620 + 180 * math.sin(t * 34.0) - 220 * t
        ph += f / SR
        raw.append(2.0 * (ph % 1.0) - 1.0)
    v = resonator(raw, 900, 9.0)
    v = mix(v, [x * 0.5 for x in resonator(raw, 2400, 7.0)])
    return normalize(apply(v, env(n, 0.02, 0.45, 1.1)), 0.7)


def s_bomb(rng: Rng) -> list:
    """Подрыв: удар, рёв и эхо по коридору."""
    n = int(1.4 * SR)
    boom = apply(tone(n, 90, 28), env(n, 0.002, 0.5, 1.1))
    roar = apply(lowpass(noise(n, rng), 1400), env(n, 0.004, 0.45, 1.3))
    sig = drive(mix(boom, [r * 0.9 for r in roar]), 2.2)
    return normalize(delay_tail(sig, 120, 0.32), 0.95)


def s_cryo(rng: Rng) -> list:
    """Крио: резкий выхлоп и потрескивание намерзающего льда."""
    n = int(1.0 * SR)
    hiss = apply(bandpass(noise(n, rng), 1800, 8000), env(n, 0.006, 0.4, 1.2))
    crack = [0.0] * n
    for k in range(70):
        pos = int(abs(rng.next()) * (n - 400))
        for i in range(220):
            crack[pos + i] += math.sin(i * 0.9) * math.exp(-i / 40.0) * 0.5
    low = apply(tone(n, 160, 60), env(n, 0.003, 0.2))
    return normalize(mix(hiss, crack, [x * 0.6 for x in low]), 0.8)


def s_emp(rng: Rng) -> list:
    """ЭМИ: разряд и гаснущий гул отключающейся электроники."""
    n = int(1.1 * SR)
    zap = apply(tone(n, 2600, 120, "sqr"), env(n, 0.001, 0.08, 1.0))
    arc = apply(highpass(noise(n, rng), 2500), env(n, 0.001, 0.12, 1.4))
    hum = apply(tone(n, 120, 40, "saw"), env(n, 0.02, 0.5, 1.0))
    return normalize(drive(mix([z * 0.7 for z in zap], arc, [h * 0.5 for h in hum]), 1.8), 0.85)


def s_flare(rng: Rng) -> list:
    """Факел: вспышка и ровный рёв горения."""
    n = int(1.5 * SR)
    whoosh = apply(bandpass(noise(n, rng), 200, 3000), env(n, 0.02, 0.7, 0.9))
    pop = apply(tone(n, 400, 90), env(n, 0.001, 0.05))
    return normalize(mix(whoosh, [p * 0.7 for p in pop]), 0.8)


def s_singularity(rng: Rng) -> list:
    """Грав-коллапс: всасывающий гул и хлопок в конце."""
    n = int(1.8 * SR)
    suck = []
    ph = 0.0
    for i in range(n):
        t = i / n
        f = 60 + 340 * (t ** 2)
        ph += f / SR
        suck.append(math.sin(ph * math.tau))
    e = [min(1.0, (i / n) * 1.6) for i in range(n)]
    body = apply(suck, e)
    tail = int(0.35 * SR)
    clap = apply(lowpass(noise(tail, rng), 900), env(tail, 0.001, 0.12, 1.2))
    out = list(body)
    for i, v in enumerate(clap):
        j = n - tail + i
        if 0 <= j < n:
            out[j] += v * 1.4
    return normalize(out, 0.85)


def s_holo(rng: Rng) -> list:
    """Голо-проектор: переливающийся звон."""
    n = int(1.0 * SR)
    parts = []
    for f in (880, 1320, 1760, 2640):
        parts.append(apply(tone(n, f, f * 1.02), env(n, 0.05, 0.45, 1.0)))
    sig = mix(*parts)
    shimmer = [math.sin(i / SR * math.tau * 6.0) * 0.35 + 0.65 for i in range(n)]
    return normalize([s * shimmer[i] for i, s in enumerate(sig)], 0.6)


def s_brood(rng: Rng) -> list:
    """Выводок: влажный разрыв и возня."""
    n = int(1.1 * SR)
    burst = apply(lowpass(noise(n, rng), 1600), env(n, 0.002, 0.18, 1.4))
    squelch = apply(bandpass(noise(n, rng), 300, 1800), env(n, 0.08, 0.5, 0.9))
    low = apply(tone(n, 130, 55), env(n, 0.003, 0.15))
    return normalize(drive(mix(burst, [s * 0.8 for s in squelch], low), 1.5), 0.85)


def s_puppet(rng: Rng) -> list:
    """Кукловод: чавканье и щелчок захвата."""
    n = int(0.9 * SR)
    wet = apply(bandpass(noise(n, rng), 200, 1400), env(n, 0.02, 0.35, 1.0))
    click = apply(tone(n, 900, 300, "sqr"), env(n, 0.001, 0.04))
    return normalize(mix(wet, [c * 0.5 for c in click]), 0.75)


def s_slime(rng: Rng) -> list:
    """Слизь: пузыри."""
    n = int(0.8 * SR)
    out = [0.0] * n
    for k in range(14):
        pos = int(abs(rng.next()) * (n - 3000))
        f0 = 180 + abs(rng.next()) * 500
        ln = int(0.10 * SR)
        b = apply(tone(ln, f0, f0 * 2.4), env(ln, 0.004, 0.05))
        for i, v in enumerate(b):
            out[pos + i] += v * 0.6
    return normalize(lowpass(out, 2200), 0.6)


def s_softener(rng: Rng) -> list:
    """Размягчитель: электрошок и вопль."""
    n = int(1.0 * SR)
    buzz = apply(tone(n, 90, 90, "sqr"), env(n, 0.005, 0.4, 1.0))
    buzz = [b * (1.0 if (i // 220) % 2 == 0 else 0.25) for i, b in enumerate(buzz)]
    arc = apply(highpass(noise(n, rng), 3000), env(n, 0.002, 0.3, 1.2))
    return normalize(drive(mix([b * 0.7 for b in buzz], [a * 0.6 for a in arc]), 2.0), 0.8)


def s_implant_in(rng: Rng) -> list:
    """Вживление: хруст, влажный ход и щелчок фиксации."""
    n = int(1.2 * SR)
    wet = apply(bandpass(noise(n, rng), 200, 1500), env(n, 0.05, 0.5, 0.9))
    crunch = [0.0] * n
    for k in range(9):
        pos = int(abs(rng.next()) * (n - 2000))
        ln = 900
        c = apply(bandpass(noise(ln, rng), 800, 4000), env(ln, 0.001, 0.03, 1.5))
        for i, v in enumerate(c):
            crunch[pos + i] += v * 0.8
    lock = apply(tone(n, 1500, 700, "sqr"), env(n, 0.001, 0.02))
    return normalize(mix(wet, crunch, [x * 0.4 for x in lock]), 0.7)


def s_arm(rng: Rng) -> list:
    """Взвод: два коротких сигнала вверх."""
    n = int(0.35 * SR)
    a = apply(tone(int(0.08 * SR), 880, 880), env(int(0.08 * SR), 0.002, 0.03))
    b = apply(tone(int(0.08 * SR), 1320, 1320), env(int(0.08 * SR), 0.002, 0.04))
    out = [0.0] * n
    for i, v in enumerate(a):
        out[i] += v
    for i, v in enumerate(b):
        j = i + int(0.13 * SR)
        if j < n:
            out[j] += v
    return normalize(out, 0.5)


def s_ui(rng: Rng) -> list:
    """Клик интерфейса."""
    n = int(0.09 * SR)
    return normalize(apply(tone(n, 1600, 1100), env(n, 0.001, 0.02)), 0.35)


def s_alert(rng: Rng) -> list:
    """Тревога: полиция вызвана."""
    n = int(0.9 * SR)
    out = [0.0] * n
    ln = int(0.18 * SR)
    for k in range(3):
        b = apply(tone(ln, 700 if k % 2 == 0 else 520, 700 if k % 2 == 0 else 520, "sqr"),
                  env(ln, 0.004, 0.06))
        for i, v in enumerate(b):
            j = i + k * int(0.26 * SR)
            if j < n:
                out[j] += v * 0.5
    return normalize(out, 0.5)


def s_door(rng: Rng) -> list:
    """Дверь: скрип и удар створки."""
    n = int(0.7 * SR)
    creak = apply(resonator(noise(n, rng), 420, 12.0), env(n, 0.06, 0.28, 1.0))
    thud = apply(tone(n, 130, 60), env(n, 0.002, 0.08))
    out = mix([c * 0.5 for c in creak], thud)
    return normalize(out, 0.55)


SOUNDS = {
    "hit_flesh": s_hit_flesh,
    "hit_block": s_hit_block,
    "swing": s_swing,
    "step": s_step,
    "death": s_death,
    "scream": s_scream,
    "imp_bomb": s_bomb,
    "imp_cryo": s_cryo,
    "imp_emp": s_emp,
    "imp_flare": s_flare,
    "imp_singularity": s_singularity,
    "imp_holo": s_holo,
    "imp_brood": s_brood,
    "imp_puppet": s_puppet,
    "imp_slime": s_slime,
    "imp_softener": s_softener,
    "implant_in": s_implant_in,
    "arm": s_arm,
    "ui": s_ui,
    "alert": s_alert,
    "door": s_door,
}


def main() -> None:
    os.makedirs(os.path.abspath(OUT_DIR), exist_ok=True)
    total = 0
    for i, (name, fn) in enumerate(sorted(SOUNDS.items())):
        sig = fn(Rng(1000 + i * 37))
        path = write(name, sig)
        total += os.path.getsize(path)
        print("СИНТЕЗ %-16s %5.2f с  %4d КБ" % (
            name, len(sig) / SR, os.path.getsize(path) // 1024))
    print("ВСЕГО: %d звуков, %d КБ" % (len(SOUNDS), total // 1024))


if __name__ == "__main__":
    main()
