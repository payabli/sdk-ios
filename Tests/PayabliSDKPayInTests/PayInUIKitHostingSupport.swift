import SwiftUI
import UIKit

/// The machinery for hosting a wrapped UIKit control in a test: a representable's `Context`
/// cannot be built outside SwiftUI, so the wrapped view is driven through a hosting controller.
@MainActor
enum PayInUIKitHostingSupport {
    /// The hosting windows outlive the tests that make them, or UIKit tears them down first.
    enum CoverageWindowStore {
        static var windows: [UIWindow] = []
    }

    static func host<Content: View>(_ view: Content) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        CoverageWindowStore.windows.append(window)
        return host
    }

    static func waitForRenderedSubviews(
        in view: UIView,
        timeout: TimeInterval = 1
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            view.setNeedsLayout()
            view.layoutIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        } while view.payabliCoverageAllSubviews.compactMap({ $0 as? UITextField }).isEmpty && Date() < deadline
    }

    static func waitForPresentedViewController(
        from host: UIViewController,
        timeout: TimeInterval = 1
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while host.presentedViewController == nil, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }
}

extension UIView {
    var payabliCoverageAllSubviews: [UIView] {
        subviews + subviews.flatMap(\.payabliCoverageAllSubviews)
    }
}
