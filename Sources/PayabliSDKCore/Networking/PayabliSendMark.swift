import Foundation

/// Records that a send may have left the device: set when core hands the request to the HTTP layer.
///
/// One instance per payment request, bound as a task-local by the layer holding its key. A 401 lowers it, since the
/// service ran nothing for that send, and the replay raises it again at its own hand-off.
package final class PayabliSendMark: @unchecked Sendable {
    @TaskLocal package static var current: PayabliSendMark?

    private let lock = NSLock()
    private var isSet = false

    package init() {}

    /// Whether a send under this mark reached the HTTP layer, so the service may have seen it.
    package var mayHaveLeft: Bool {
        lock.withLock { isSet }
    }

    package func set() {
        lock.withLock { isSet = true }
    }

    package func lower() {
        lock.withLock { isSet = false }
    }
}
