import Foundation

var fails = 0
func check(_ c: Bool, _ m: String) { if !c { print("FAIL:", m); fails += 1 } else { print("ok:", m) } }

let t0 = Date()
var s = Scheduler(interval: 1200, idleReset: 300)
var fired = false
for i in 1...239 { fired = s.tick(dt: 5, idle: 1, now: t0 + Double(i*5)) || fired }
check(!fired, "нет перерыва до 20 мин")
check(s.tick(dt: 5, idle: 1, now: t0 + 1200), "перерыв ровно в 20 мин")
s.reset(); check(s.active == 0, "сброс после перерыва")

for _ in 0..<100 { _ = s.tick(dt: 5, idle: 1, now: t0) }
_ = s.tick(dt: 5, idle: 301, now: t0)
check(s.active == 0, "простой >5 мин обнуляет")

for _ in 0..<100 { _ = s.tick(dt: 5, idle: 1, now: t0) }
_ = s.tick(dt: 3600, idle: 1, now: t0)
check(s.active == 0, "сон Mac (большой dt) обнуляет")

s.snooze(300); check(s.remaining == 300, "отложить на 5 мин")

s.pausedUntil = t0 + 3600
check(!s.tick(dt: 5, idle: 1, now: t0 + 10), "пауза не стреляет")
check(s.isPaused(t0 + 10), "пауза активна")
_ = s.tick(dt: 5, idle: 1, now: t0 + 3601)
check(s.pausedUntil == nil && s.active == 5, "пауза кончилась — счёт заново")

print(fails == 0 ? "ALL PASS" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
