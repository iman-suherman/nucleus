import Foundation

public enum NucleusDarwinNotifications {
    public static func observe(_ name: String, handler: @escaping () -> Void) -> NSObjectProtocol {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = ObserverBox(handler: handler)
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(observer).toOpaque(),
            { _, pointer, _, _, _ in
                guard let pointer else { return }
                Unmanaged<ObserverBox>.fromOpaque(pointer).takeUnretainedValue().handler()
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
        return observer
    }

    public static func remove(_ token: NSObjectProtocol) {
        guard let observer = token as? ObserverBox else { return }
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(observer).toOpaque()
        )
    }

    private final class ObserverBox: NSObject {
        let handler: () -> Void
        init(handler: @escaping () -> Void) { self.handler = handler }
    }
}
