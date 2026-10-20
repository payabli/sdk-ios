import UIKit

/// The app's movement to the background, as telemetry delivery needs it.
package protocol AppLifecycle: Sendable {
    /// One window per move to the background, opened as the app leaves, until the stream is dropped.
    ///
    /// - Returns: the windows; the receiver closes each one when the sends it started have ended.
    func backgroundings() -> AsyncStream<BackgroundWindow>
}

/// Time the system gives the app to finish its sends after it leaves the foreground. Closed exactly once.
package final class BackgroundWindow: @unchecked Sendable {
    private let lock = NSLock()
    private var onClose: (@Sendable () -> Void)?

    /// - Parameter onClose: hands the time back to the system.
    package init(onClose: @escaping @Sendable () -> Void) {
        self.onClose = onClose
    }

    /// Hands the time back. Later calls do nothing.
    package func close() {
        let action = lock.withLock {
            defer { onClose = nil }
            return onClose
        }
        action?()
    }
}

/// The shipping lifecycle, read from UIKit's notifications.
///
/// Background is `didEnterBackground`, not `willResignActive`: a system alert or the app switcher resigns
/// active without the app going anywhere.
package struct UIKitAppLifecycle: AppLifecycle, @unchecked Sendable {
    package static let backgroundNotification = UIApplication.didEnterBackgroundNotification

    private let center: NotificationCenter
    private let openWindow: @Sendable () -> BackgroundWindow

    /// - Parameter center: where UIKit posts the app's lifecycle notifications.
    /// - Parameter openWindow: asks the system for background time; called inside the notification's handler.
    package init(
        center: NotificationCenter = .default,
        openWindow: @escaping @Sendable () -> BackgroundWindow = UIKitAppLifecycle.applicationWindow
    ) {
        self.center = center
        self.openWindow = openWindow
    }

    package func backgroundings() -> AsyncStream<BackgroundWindow> {
        let center = center
        let openWindow = openWindow
        return AsyncStream { continuation in
            // Background time has to be asked for before this handler returns, or the app can be
            // suspended before the request is made.
            let observer = center.addObserver(forName: Self.backgroundNotification, object: nil, queue: nil) { _ in
                continuation.yield(openWindow())
            }
            continuation.onTermination = { _ in
                center.removeObserver(observer)
            }
        }
    }

    /// A window backed by `UIApplication`'s background task, ended by its close or by the system's expiry.
    ///
    /// - Returns: the open window. UIKit posts the notification on the main thread, so this runs there.
    package static func applicationWindow() -> BackgroundWindow {
        MainActor.assumeIsolated {
            let task = ApplicationBackgroundTask()
            let window = BackgroundWindow { Task { @MainActor in task.end() } }
            task.begin { window.close() }
            return window
        }
    }
}

@MainActor
private final class ApplicationBackgroundTask {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    func begin(expiring: @escaping @MainActor () -> Void) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "PayabliTelemetry") { expiring() }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
