# Генерирует две спокойные мелодии: начало перерыва и конец.
import wave, math, struct, random, os
SR = 44100
def note(n):  # MIDI -> Hz
    return 440 * 2 ** ((n - 69) / 12)

def bell(buf, t0, midi, dur, amp, pan):
    f = note(midi); s0 = int(t0 * SR); n = int(dur * SR)
    parts = [(1, 1.0, 1.6), (2, 0.25, 3.0), (3, 0.08, 5.0), (4.2, 0.04, 7.0)]
    for i in range(n):
        t = i / SR
        att = min(1, t / 0.012)
        v = sum(a * math.exp(-t * d) * math.sin(2 * math.pi * f * h * t) for h, a, d in parts)
        v *= att * amp
        j = s0 + i
        if j < len(buf):
            buf[j][0] += v * (1 - pan); buf[j][1] += v * pan

def pad(buf, t0, midis, dur, amp):
    s0 = int(t0 * SR); n = int(dur * SR)
    for i in range(n):
        t = i / SR
        env = min(1, t / 1.5) * min(1, (dur - t) / 2.0)
        v = sum(math.sin(2 * math.pi * note(m) * t + k) * (1 + 0.15 * math.sin(2 * math.pi * 0.3 * t + k))
                for k, m in enumerate(midis)) / len(midis)
        v *= env * amp
        j = s0 + i
        if j < len(buf):
            buf[j][0] += v; buf[j][1] += v

def reverb(buf):
    out = [[l, r] for l, r in buf]
    for ch, delays in ((0, [1557, 1617, 1491, 1422]), (1, [1580, 1640, 1514, 1445])):
        for d in delays:
            fb = 0.72; line = [0.0] * d; k = 0
            for i in range(len(buf)):
                y = line[k]; line[k] = buf[i][ch] + y * fb; k = (k + 1) % d
                out[i][ch] += y * 0.09
    return out

def render(name, length, events, chord=None):
    buf = [[0.0, 0.0] for _ in range(int(length * SR))]
    if chord: pad(buf, 0, chord, length - 0.3, 0.05)
    for t, m, a, p in events: bell(buf, t, m, length - t, a, p)
    buf = reverb(buf)
    peak = max(max(abs(l), abs(r)) for l, r in buf)
    g = 0.45 / peak
    fade = int(0.4 * SR)
    with wave.open(name, 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        frames = bytearray()
        for i, (l, r) in enumerate(buf):
            e = min(1, (len(buf) - i) / fade)
            frames += struct.pack('<hh', int(l * g * e * 32767), int(r * g * e * 32767))
        w.writeframes(bytes(frames))

here = os.path.dirname(os.path.abspath(__file__))
# Начало: мягкое пентатоническое арпеджио над аккордом Fmaj7
render(os.path.join(here, 'start.wav'), 7.0, [
    (0.0, 72, 0.5, 0.4), (0.45, 76, 0.42, 0.6), (0.9, 79, 0.4, 0.35), (1.35, 84, 0.36, 0.65),
    (2.2, 81, 0.34, 0.5), (2.65, 79, 0.32, 0.4), (3.3, 76, 0.36, 0.55),
], chord=[53, 57, 60, 64])
# Конец: две восходящие ноты
render(os.path.join(here, 'end.wav'), 3.5, [
    (0.0, 79, 0.45, 0.4), (0.35, 84, 0.42, 0.6), (0.7, 88, 0.25, 0.5),
])
print('ok')
