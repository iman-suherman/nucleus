import Foundation

@MainActor
final class HourlyBeepService {
    static let shared = HourlyBeepService()

    private var timer: Timer?
    private var lastPlayedHour: Int?

    private init() {}

    func start() {
        stop()
        checkAndPlayIfNeeded()
        timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndPlayIfNeeded()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkAndPlayIfNeeded() {
        let settings = AppSettings.shared
        guard settings.hourlyBeepEnabled else { return }

        let now = Date()
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: now)
        guard minute == 59 else { return }

        let hour = calendar.component(.hour, from: now)
        guard lastPlayedHour != hour else { return }

        lastPlayedHour = hour
        settings.hourlyBeepSound.playAlert()
    }
}
