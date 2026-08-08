"""Композиции Wolf: по треку на фракцию, синтез из кода.

Ню-метал — наёмникам, блэк — психам, кор — гулям, эмбиент — гражданским.
Сэмплов и готовых лупов со свободной лицензией мы не берём (как и с
моделями), поэтому и инструменты, и партии собираются здесь.

Всё детерминировано: свой ГПСЧ с фиксированным зерном, так что пересборка
даёт те же файлы и не шумит в диффе.

Формат: 22050 Гц, моно, 16 бит. Треки зациклены — хвост последнего такта
заворачивается в начало, чтобы на стыке не было щелчка.

Запуск:  python3 tools/audio/music.py
"""

import math
import os
import struct
import wave

SR = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "..", "godot", "assets", "audio")


class Rng:
    def __init__(self, seed: int):
        self.s = seed & 0xFFFFFFFF

    def next(self) -> float:
        self.s = (1664525 * self.s + 1013904223) & 0xFFFFFFFF
        return self.s / 2147483648.0 - 1.0

    def uni(self) -> float:
        return (self.next() + 1.0) * 0.5


# --- Ноты -----------------------------------------------------------------
# Считаем от A4 = 440. Имена вида "E1", "C#2" — как на грифе.

_STEP = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6,
         "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def note(name: str) -> float:
    i = 1 if len(name) > 1 and name[1] in "#" else 1
    letter = name[:i + 1] if len(name) > 1 and name[1] == "#" else name[:1]
    octv = int(name[len(letter):])
    semi = _STEP[letter] + (octv + 1) * 12 - 69
    return 440.0 * (2.0 ** (semi / 12.0))


# --- Примитивы ------------------------------------------------------------

def saw(n: int, f: float, phase: float = 0.0) -> list:
    out = []
    ph = phase
    inc = f / SR
    for _ in range(n):
        ph = (ph + inc) % 1.0
        out.append(2.0 * ph - 1.0)
    return out


def sq(n: int, f: float, duty: float = 0.5) -> list:
    out = []
    ph = 0.0
    inc = f / SR
    for _ in range(n):
        ph = (ph + inc) % 1.0
        out.append(1.0 if ph < duty else -1.0)
    return out


def sine(n: int, f0: float, f1: float = None) -> list:
    if f1 is None:
        f1 = f0
    out = []
    ph = 0.0
    for i in range(n):
        f = f0 + (f1 - f0) * (i / max(1, n - 1))
        ph += f / SR
        out.append(math.sin(ph * math.tau))
    return out


def noise(n: int, rng: Rng) -> list:
    return [rng.next() for _ in range(n)]


def adsr(n: int, a: float, d: float, s: float, r: float) -> list:
    """Классическая огибающая в долях от длины ноты."""
    na = max(1, int(a * SR))
    nd = max(1, int(d * SR))
    nr = max(1, int(r * SR))
    ns = max(0, n - na - nd - nr)
    out = []
    for i in range(na):
        out.append(i / na)
    for i in range(nd):
        out.append(1.0 + (s - 1.0) * (i / nd))
    out.extend([s] * ns)
    for i in range(nr):
        out.append(s * (1.0 - i / nr))
    return (out + [0.0] * n)[:n]


def pluck_env(n: int, decay: float, hold: float = 0.0) -> list:
    nh = int(hold * SR)
    out = []
    for i in range(n):
        if i < nh:
            out.append(1.0)
        else:
            out.append(math.exp(-(i - nh) / max(1.0, decay * SR)))
    return out


def lp(sig: list, cutoff: float) -> list:
    a = math.exp(-2.0 * math.pi * cutoff / SR)
    out = []
    y = 0.0
    for x in sig:
        y = x * (1.0 - a) + y * a
        out.append(y)
    return out


def hp(sig: list, cutoff: float) -> list:
    return [x - y for x, y in zip(sig, lp(sig, cutoff))]


def dist(sig: list, amount: float) -> list:
    return [math.tanh(x * amount) for x in sig]


def mulenv(sig: list, e: list) -> list:
    return [s * e[i] for i, s in enumerate(sig)]


def reverb(sig: list, mix_amt: float, size: float = 1.0) -> list:
    """Дешёвая реверберация Шрёдера: гребёнки плюс всепропускающий.

    Нужна всем четырём трекам, но по-разному: блэку — холодный зал, эмбиенту —
    бесконечный хвост, ню-металу — чуть-чуть, иначе гроув мажется.
    """
    combs = [(int(0.0297 * SR * size), 0.78), (int(0.0371 * SR * size), 0.76),
             (int(0.0411 * SR * size), 0.74), (int(0.0437 * SR * size), 0.72)]
    n = len(sig)
    wet = [0.0] * n
    for delay, fb in combs:
        buf = [0.0] * max(1, delay)
        idx = 0
        for i in range(n):
            v = buf[idx]
            wet[i] += v * 0.25
            buf[idx] = sig[i] + v * fb
            idx = (idx + 1) % len(buf)
    # Всепропускающий размывает эхо в хвост.
    d = max(1, int(0.0089 * SR * size))
    buf = [0.0] * d
    idx = 0
    out = []
    for i in range(n):
        v = buf[idx]
        y = -wet[i] + v
        buf[idx] = wet[i] + v * 0.6
        idx = (idx + 1) % d
        out.append(sig[i] * (1.0 - mix_amt) + y * mix_amt)
    return out


class Track:
    """Дорожка: буфер нужной длины, куда подмешиваются ноты."""

    def __init__(self, seconds: float):
        self.n = int(seconds * SR)
        self.buf = [0.0] * self.n

    def add(self, sig: list, at: float, gain: float = 1.0) -> None:
        """at — время в секундах. Хвост за концом ЗАВОРАЧИВАЕТСЯ в начало:
        так луп смыкается без щелчка и без обрубленного затухания."""
        start = int(at * SR)
        for i, v in enumerate(sig):
            self.buf[(start + i) % self.n] += v * gain

    def mix(self, other: "Track", gain: float = 1.0) -> None:
        for i in range(min(self.n, other.n)):
            self.buf[i] += other.buf[i] * gain

    def apply(self, fn) -> None:
        self.buf = fn(self.buf)

    def normalize(self, peak: float = 0.82) -> None:
        m = max(1e-6, max(abs(x) for x in self.buf))
        self.buf = [x / m * peak for x in self.buf]


# --- Инструменты ----------------------------------------------------------

def gtr_chug(f: float, dur: float, rng: Rng, gain_drive: float = 9.0) -> list:
    """Заглушенный аккорд: короткий, плотный, с призвуком медиатора."""
    n = int(dur * SR)
    body = [a * 0.6 + b * 0.4 for a, b in zip(saw(n, f), sq(n, f * 0.999, 0.42))]
    fifth = saw(n, f * 1.4983)          # квинта — «power chord»
    octv = saw(n, f * 2.0)
    mixv = [a + 0.75 * b + 0.45 * c for a, b, c in zip(body, fifth, octv)]
    pick = mulenv(noise(n, rng), pluck_env(n, 0.004))
    sig = [m + p * 0.5 for m, p in zip(mixv, pick)]
    sig = dist(lp(sig, 3200), gain_drive)
    sig = lp(sig, 2600)
    return mulenv(sig, pluck_env(n, 0.055, 0.012))


def gtr_tremolo(f: float, dur: float, rng: Rng, rate: float = 16.0) -> list:
    """Тремоло: та самая стена из блэка — нота дробится частым медиатором."""
    n = int(dur * SR)
    core = [a * 0.7 + b * 0.3 for a, b in zip(saw(n, f), saw(n, f * 1.005))]
    fifth = saw(n, f * 1.4983)
    sig = [a + b * 0.6 for a, b in zip(core, fifth)]
    sig = dist(sig, 14.0)
    sig = hp(lp(sig, 5200), 260)        # тонко и холодно, без низа
    trem = []
    for i in range(n):
        ph = (i / SR) * rate
        trem.append(0.35 + 0.65 * (0.5 + 0.5 * math.cos(ph * math.tau)) ** 0.4)
    return mulenv(sig, [t * e for t, e in zip(trem, adsr(n, 0.004, 0.02, 0.85, 0.05))])


def gtr_open(f: float, dur: float, rng: Rng) -> list:
    """Открытый аккорд: звенит и тянется — для брейкдауна и стоек."""
    n = int(dur * SR)
    sig = [a + 0.7 * b + 0.5 * c for a, b, c in
           zip(saw(n, f), saw(n, f * 1.4983), saw(n, f * 2.004))]
    sig = dist(lp(sig, 3600), 7.0)
    return mulenv(sig, pluck_env(n, 0.45, 0.02))


def bass(f: float, dur: float) -> list:
    n = int(dur * SR)
    sig = [a * 0.7 + b * 0.3 for a, b in zip(saw(n, f), sine(n, f))]
    sig = lp(dist(sig, 3.0), 900)
    return mulenv(sig, pluck_env(n, 0.12, 0.01))


def kick() -> list:
    n = int(0.28 * SR)
    body = sine(n, 130, 42)
    click = mulenv(noise(n, Rng(7)), pluck_env(n, 0.006))
    sig = [b + c * 0.35 for b, c in zip(body, click)]
    return mulenv(dist(sig, 2.2), pluck_env(n, 0.10))


def snare(rng: Rng) -> list:
    n = int(0.24 * SR)
    tone = sine(n, 210, 160)
    rattle = hp(noise(n, rng), 1400)
    sig = [t * 0.45 + r * 0.9 for t, r in zip(tone, rattle)]
    return mulenv(dist(sig, 1.8), pluck_env(n, 0.075))


def hat(rng: Rng, open_hat: bool = False) -> list:
    n = int((0.22 if open_hat else 0.06) * SR)
    sig = hp(noise(n, rng), 6000)
    return mulenv(sig, pluck_env(n, 0.10 if open_hat else 0.014))


def crash(rng: Rng) -> list:
    n = int(1.1 * SR)
    sig = hp(noise(n, rng), 3500)
    return mulenv(sig, pluck_env(n, 0.42))


def pad(f: float, dur: float) -> list:
    """Тёплый тянущийся слой: несколько расстроенных пил под фильтром."""
    n = int(dur * SR)
    sig = [0.0] * n
    for det in (0.997, 1.0, 1.003, 1.006):
        for i, v in enumerate(saw(n, f * det)):
            sig[i] += v * 0.25
    # Фильтр медленно открывается — слой «дышит».
    out = []
    y = 0.0
    for i, x in enumerate(sig):
        t = i / n
        cut = 340 + 520 * math.sin(t * math.pi)
        a = math.exp(-2.0 * math.pi * cut / SR)
        y = x * (1.0 - a) + y * a
        out.append(y)
    return mulenv(out, adsr(n, dur * 0.35, dur * 0.1, 0.75, dur * 0.45))


def bell(f: float, dur: float) -> list:
    """Колокольчик через ЧМ: редкие ноты поверх эмбиента."""
    n = int(dur * SR)
    out = []
    ph = 0.0
    mph = 0.0
    for i in range(n):
        e = math.exp(-i / (0.5 * SR))
        mph += (f * 2.01) / SR
        m = math.sin(mph * math.tau) * 2.6 * e
        ph += f / SR
        out.append(math.sin((ph + m) * math.tau))
    return mulenv(out, pluck_env(n, dur * 0.35))


def drone(f: float, dur: float) -> list:
    n = int(dur * SR)
    sig = [0.0] * n
    for k, det in enumerate((1.0, 1.5, 2.0)):
        for i, v in enumerate(sine(n, f * det)):
            sig[i] += v * (0.5 / (k + 1))
    lfo = [0.72 + 0.28 * math.sin((i / SR) * 0.08 * math.tau) for i in range(n)]
    return [s * l for s, l in zip(sig, lfo)]


# --- Композиции -----------------------------------------------------------

def nu_metal() -> Track:
    """НАЁМНИКИ. Ню-метал: медленный тяжёлый гроув, синкопы, много пауз.

    Суть жанра не в скорости, а в паузе между ударами — риф бьёт и молчит,
    и в этой тишине слышно, как барабан тащит. Строй пониженный.
    """
    rng = Rng(4001)
    bpm = 92.0
    beat = 60.0 / bpm
    bar = beat * 4
    bars = 16
    t = Track(bar * bars)
    root = note("C#1")                 # drop C# — низ, ради которого жанр и есть
    scale = [1.0, 1.1892, 1.3348, 1.4983]   # корень, м3, ч4, ч5

    # Синкопы в шестнадцатых: 1 — удар, 0 — тишина. Тишины больше, чем нот.
    riff = [1, 0, 0, 1, 0, 1, 0, 0,  1, 0, 0, 0, 1, 1, 0, 0]
    for b in range(bars):
        base = b * bar
        # Каждые 4 такта риф уходит на ступень выше — иначе он приедается.
        step = scale[(b // 4) % len(scale)]
        for i, on in enumerate(riff):
            if not on:
                continue
            at = base + i * (beat / 4.0)
            f = root * step
            # Последний удар такта — октавой выше, как «ответ».
            if i >= 12 and b % 2 == 1:
                f *= 2.0
            t.add(gtr_chug(f, 0.30, rng), at, 0.55)
            t.add(bass(f * 0.5, 0.26), at, 0.5)
        # Барабаны: бочка по синкопам, малый строго на 2 и 4 — он и держит гроув.
        for i, on in enumerate(riff):
            if on and i % 2 == 0:
                t.add(kick(), base + i * (beat / 4.0), 0.85)
        for k in (1, 3):
            t.add(snare(rng), base + k * beat, 0.62)
        for i in range(8):
            t.add(hat(rng, open_hat=(i == 7)), base + i * (beat / 2.0), 0.22)
        if b % 4 == 0:
            t.add(crash(rng), base, 0.3)
    t.apply(lambda s: reverb(s, 0.12, 0.7))
    t.normalize(0.85)
    return t


def black_metal() -> Track:
    """ПСИХИ. Блэк: стена тремоло, бласт-бит, холодный зал.

    Здесь наоборот — ни одной паузы. Сплошной поток на предельной скорости,
    мелодия высоко и в миноре, низ вырезан: должно звучать тонко и злобно,
    как радиопомеха, а не как тяжёлый рок.
    """
    rng = Rng(4002)
    bpm = 196.0
    beat = 60.0 / bpm
    bar = beat * 4
    bars = 24                          # на 196 BPM 16 тактов — всего 20 секунд
    t = Track(bar * bars)
    root = note("E2")
    # Гармонический минор с уменьшённой квинтой — «злые» ступени.
    mel = [0, 2, 3, 5, 6, 3, 2, 0, 7, 6, 5, 3, 2, 3, 5, 7]

    for b in range(bars):
        base = b * bar
        # Мелодия перекладывается на квинту в третьей четверти — дыхание.
        shift = 7 if (b // 4) % 2 == 1 else 0
        for i in range(8):
            semi = mel[(b * 8 + i) % len(mel)] + shift
            f = root * (2.0 ** (semi / 12.0))
            t.add(gtr_tremolo(f, beat * 0.52, rng, rate=17.0),
                  base + i * (beat / 2.0), 0.34)
        # Бласт-бит: бочка и малый чередуются шестнадцатыми.
        for i in range(16):
            at = base + i * (beat / 4.0)
            # Бласт громче, чем в других треках: под сплошной стеной тремоло
            # барабан иначе тонет и жанр перестаёт читаться.
            if i % 2 == 0:
                t.add(kick(), at, 0.75)
            else:
                t.add(snare(rng), at, 0.52)
        for i in range(8):
            t.add(hat(rng), base + i * (beat / 2.0), 0.13)
        if b % 8 == 0:
            t.add(crash(rng), base, 0.34)
    # Низ вырезаем и заливаем холодным залом — фирменный «сырой» звук.
    t.apply(lambda s: hp(s, 190))
    t.apply(lambda s: reverb(s, 0.34, 1.5))
    t.normalize(0.8)
    return t


def core() -> Track:
    """ГУЛИ. Кор: восемь тактов гонки и восемь брейкдауна.

    Жанр держится на переключении: сначала двойная бочка и рубка
    шестнадцатыми, потом всё обрушивается в half-time, и каждый удар звучит
    вдвое тяжелее просто потому, что вокруг стало пусто.
    """
    rng = Rng(4003)
    bpm = 150.0
    beat = 60.0 / bpm
    bar = beat * 4
    bars = 16
    t = Track(bar * bars)
    root = note("D1")

    for b in range(bars):
        base = b * bar
        breakdown = b >= 8
        if not breakdown:
            # Гонка: рубка шестнадцатыми с диссонансным «ответом».
            for i in range(16):
                at = base + i * (beat / 4.0)
                f = root if i % 8 < 6 else root * 1.0595   # малая секунда
                t.add(gtr_chug(f, 0.16, rng, 10.0), at, 0.42)
                t.add(kick(), at, 0.42)          # двойная бочка
            for k in (1, 3):
                t.add(snare(rng), base + k * beat, 0.6)
            for i in range(8):
                t.add(hat(rng), base + i * (beat / 2.0), 0.16)
        else:
            # Брейкдаун: половинный темп, редкие тяжёлые удары, между ними пусто.
            hits = [0, 3, 6, 7, 10, 14]
            for i in hits:
                at = base + i * (beat / 4.0)
                f = root * (1.3348 if i in (6, 7) else 1.0)   # уход на кварту
                t.add(gtr_chug(f, 0.42, rng, 12.0), at, 0.72)
                t.add(bass(f * 0.5, 0.4), at, 0.6)
                t.add(kick(), at, 0.9)
            t.add(snare(rng), base + 2 * beat, 0.75)
            if b % 2 == 1:
                t.add(gtr_open(root * 2.0, beat * 1.6, rng), base + 3 * beat, 0.3)
        if b in (0, 8):
            t.add(crash(rng), base, 0.42)
    t.apply(lambda s: reverb(s, 0.14, 0.8))
    t.normalize(0.85)
    return t


def ambient() -> Track:
    """ГРАЖДАНСКИЕ. Эмбиент: ни одного удара, только слои и редкие колокольчики.

    У гражданского нет оружия и нет права шуметь — его музыка не гонит, а
    ждёт. Барабанов нет вовсе, всё держится на медленной смене аккордов и
    длинном хвосте зала.
    """
    t = Track(52.0)
    base_f = note("A1")
    # Минорные аккорды с добавленной ноной: тревожно, но не агрессивно.
    chords = [
        [1.0, 1.1892, 1.4983, 2.2449],
        [1.1224, 1.3348, 1.6818, 2.5198],
        [0.8909, 1.0595, 1.3348, 2.0],
        [1.0, 1.1892, 1.4983, 1.7818],
    ]
    span = 13.0
    for k, ch in enumerate(chords):
        at = k * span
        for r in ch:
            t.add(pad(base_f * r * 2.0, span * 1.35), at, 0.30)
        t.add(drone(base_f * ch[0], span * 1.1), at, 0.18)

    # Колокольчики: редкие, по пентатонике, всё дальше друг от друга.
    rng = Rng(4004)
    penta = [1.0, 1.1892, 1.3348, 1.4983, 1.7818]
    at = 2.0
    while at < 50.0:
        r = penta[int(rng.uni() * len(penta)) % len(penta)]
        t.add(bell(base_f * r * 8.0, 2.2), at, 0.12 + rng.uni() * 0.06)
        at += 2.4 + rng.uni() * 3.4
    t.apply(lambda s: reverb(s, 0.55, 2.4))
    t.apply(lambda s: lp(s, 5200))
    t.normalize(0.62)
    return t


TRACKS = {
    "mus_killer": nu_metal,       # наёмники
    "mus_cannibal": black_metal,  # психи
    "mus_ghoul": core,            # гули
    "mus_survivor": ambient,      # гражданские
}


def write(name: str, buf: list) -> str:
    path = os.path.join(os.path.abspath(OUT_DIR), name + ".wav")
    data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, x)) * 32767)) for x in buf)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    return path


def main() -> None:
    os.makedirs(os.path.abspath(OUT_DIR), exist_ok=True)
    total = 0
    for name, fn in TRACKS.items():
        tr = fn()
        path = write(name, tr.buf)
        total += os.path.getsize(path)
        print("СВЕДЕНО %-14s %5.1f с  %5d КБ" % (
            name, tr.n / SR, os.path.getsize(path) // 1024))
    print("ВСЕГО: %d композиций, %d КБ" % (len(TRACKS), total // 1024))


if __name__ == "__main__":
    main()
