import Foundation

/// Чистая логика: считает активное время работы и решает, когда пора на перерыв.
struct Scheduler {
    var interval: TimeInterval        // сколько активной работы до перерыва
    var idleReset: TimeInterval       // простой, после которого глаза считаются отдохнувшими
    private(set) var active: TimeInterval = 0
    var pausedUntil: Date?

    init(interval: TimeInterval, idleReset: TimeInterval) {
        self.interval = interval
        self.idleReset = idleReset
    }

    var remaining: TimeInterval { max(0, interval - active) }

    func isPaused(_ now: Date) -> Bool {
        if let p = pausedUntil { return now < p }
        return false
    }

    /// dt — сколько прошло с прошлого тика, idle — секунд без ввода.
    /// Возвращает true, если пора показать перерыв.
    mutating func tick(dt: TimeInterval, idle: TimeInterval, now: Date) -> Bool {
        if let p = pausedUntil {
            if now < p { return false }
            pausedUntil = nil
            active = 0
        }
        if idle >= idleReset { active = 0; return false }
        // Длинный разрыв между тиками = сон/заморозка процесса — не засчитываем.
        if dt > 60 { active = 0; return false }
        active += dt
        return active >= interval
    }

    mutating func reset() { active = 0 }
    mutating func snooze(_ s: TimeInterval) { active = max(0, interval - s) }
}
