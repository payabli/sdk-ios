import Foundation

/// Transport abstraction — production uses `URLSession` to POST to the Payabli
/// telemetry endpoint; tests inject an in-memory sink.
package protocol TelemetryTransport: Sendable {
    /// Sends one batch, once. A batch that does not arrive is dropped, never retried.
    ///
    /// - Parameter batch: the events, oldest first.
    /// - Parameter droppedSinceLastSend: how many events the queue evicted since the last batch arrived.
    /// - Returns: whether the route accepted the batch.
    @discardableResult
    func send(_ batch: [TelemetryEvent], droppedSinceLastSend: Int) async -> Bool
}

/// Batched, best-effort telemetry client. The caller never passes a PAN, CVV or token.
///
/// Sends on a full batch, a timer, backgrounding, and at once for a failure; never retries a send.
package actor TelemetryClient {
    package struct Configuration: Sendable {
        package let flushInterval: TimeInterval
        package let batchSize: Int
        package let queueCapacity: Int
        package let maxEventsPerRequest: Int
        package let maxRequestsPerDrain: Int
        package let sdkVersion: String
        package let entry: String
        package let environment: String

        package init(
            flushInterval: TimeInterval = 30,
            batchSize: Int = 20,
            queueCapacity: Int = 500,
            maxEventsPerRequest: Int = 100,
            maxRequestsPerDrain: Int = 16,
            sdkVersion: String = PayabliCore.version,
            entry: String,
            environment: String
        ) {
            self.flushInterval = flushInterval
            self.batchSize = batchSize
            self.queueCapacity = queueCapacity
            self.maxEventsPerRequest = maxEventsPerRequest
            self.maxRequestsPerDrain = maxRequestsPerDrain
            self.sdkVersion = sdkVersion
            self.entry = entry
            self.environment = environment
        }
    }

    /// Waits the given number of seconds, throwing when the wait is cancelled.
    package typealias Sleep = @Sendable (TimeInterval) async throws -> Void

    package let configuration: Configuration
    package nonisolated let sessionId: String

    private let transport: TelemetryTransport
    private let sleep: Sleep
    private let lifecycle: any AppLifecycle
    private let logger = PayabliLogger(category: .telemetry)
    private let deviceId: @Sendable () -> String?
    private var queue: TelemetryQueue

    /// The last drain scheduled. Drains run one after another, so this is also the one that finishes last.
    private var tail: Task<Void, Never>?
    /// A drain scheduled and not yet started. A request made while one waits joins it.
    private var waiting: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    private var stopped = false

    /// - Parameter configuration: the batch and queue sizes and the identifiers every event carries.
    /// - Parameter transport: where batches are sent.
    /// - Parameter sleep: the timer's wait.
    /// - Parameter lifecycle: the app's movement to the background.
    /// - Parameter deviceId: the device's identity, read as each batch leaves; `nil` while it cannot be read.
    /// - Parameter queued: events queued before anything else can record, oldest first.
    /// - Parameter sessionId: the identifier every event from this client carries.
    package init(
        configuration: Configuration,
        transport: TelemetryTransport,
        sleep: @escaping Sleep,
        lifecycle: any AppLifecycle,
        deviceId: @escaping @Sendable () -> String?,
        queued: [(name: String, properties: [String: String])],
        sessionId: String = UUID().uuidString
    ) {
        self.configuration = configuration
        self.transport = transport
        self.sleep = sleep
        self.lifecycle = lifecycle
        self.deviceId = deviceId
        self.sessionId = sessionId
        var queue = TelemetryQueue(capacity: configuration.queueCapacity)
        let now = Date()
        for (name, properties) in queued {
            _ = queue.offer(TelemetryEvent(
                sdkVersion: configuration.sdkVersion,
                sessionId: sessionId,
                deviceIdHash: nil,
                entry: configuration.entry,
                environment: configuration.environment,
                event: name,
                properties: properties,
                timestamp: now
            ))
        }
        self.queue = queue
        if !queued.isEmpty {
            Task { [weak self] in await self?.startIfNeeded() }
        }
    }

    deinit {
        timer?.cancel()
        watcher?.cancel()
    }

    /// Stops this client scheduling sends of its own: its timer and its background watcher end, and nothing starts
    /// them again. Called once, when the session it reports for is replaced.
    package func stop() {
        stopped = true
        timer?.cancel()
        watcher?.cancel()
    }

    /// Enqueue an event.
    ///
    /// - Parameter name: the event's catalog name.
    /// - Parameter properties: the string values the event carries, sent on as given.
    package func emit(_ name: String, properties: [String: String] = [:]) async {
        await emit(name, properties: properties, occurredAt: Date())
    }

    /// Enqueue an event stamped with when it happened.
    ///
    /// - Parameter name: the event's catalog name.
    /// - Parameter properties: the string values the event carries, sent on as given.
    /// - Parameter occurredAt: when the reported thing happened.
    /// - Parameter waitsForBatch: holds even a failure for its batch, for a report the send-at-once rule must not move.
    package func emit(
        _ name: String,
        properties: [String: String] = [:],
        occurredAt: Date,
        waitsForBatch: Bool = false
    ) async {
        enqueue(name, properties: properties, occurredAt: occurredAt, waitsForBatch: waitsForBatch)
    }

    /// Enqueue events in order, with nothing another caller records between them.
    ///
    /// - Parameter records: each event's catalog name and properties, in the order they happened.
    package func emit(_ records: [(name: String, properties: [String: String])]) async {
        let now = Date()
        for record in records {
            enqueue(record.name, properties: record.properties, occurredAt: now, waitsForBatch: false)
        }
    }

    private func enqueue(_ name: String, properties: [String: String], occurredAt: Date, waitsForBatch: Bool) {
        startIfNeeded()
        let event = TelemetryEvent(
            sdkVersion: configuration.sdkVersion,
            sessionId: sessionId,
            deviceIdHash: nil,
            entry: configuration.entry,
            environment: configuration.environment,
            event: name,
            properties: properties,
            timestamp: occurredAt
        )
        let queued = queue.offer(event)
        if queued >= configuration.batchSize || (!waitsForBatch && Self.sendsAtOnce(name, properties)) {
            requestFlush()
        }
    }

    /// Sends everything queued, and returns once it has been sent or dropped.
    package func flush() async {
        await requestFlush().value
    }

    /// Returns once every flush requested so far has finished.
    package func settled() async {
        while let current = tail {
            await current.value
            if tail == current {
                return
            }
        }
    }

    package var bufferedCount: Int {
        queue.count
    }

    /// The catalog's send-at-once rule: an event whose name means failure, or whose outcome is not a
    /// success, including an outcome nobody classified.
    ///
    /// - Parameter name: the event's name.
    /// - Parameter properties: the event's properties.
    /// - Returns: whether the event leaves without waiting for its batch.
    static func sendsAtOnce(_ name: String, _ properties: [String: String]) -> Bool {
        if sentAtOnce.contains(name) {
            return true
        }
        guard let outcome = properties["outcome"] else { return false }
        return !successfulOutcomes.contains(outcome)
    }

    private static let sentAtOnce: Set<String> = [
        TelemetryEventName.formValidationError,
        TelemetryEventName.ttpInitializeFailed,
        TelemetryEventName.ttpAttestationFailed,
        TelemetryEventName.ttpChargeFailed,
        TelemetryEventName.ttpCloseFailed,
        TelemetryEventName.ttpNfcFailed,
        TelemetryEventName.ttpAttestationQuotaExhausted,
        TelemetryEventName.authTokenFailed,
        TelemetryEventName.sdkInitializeFailed
    ]

    private static let successfulOutcomes: Set<String> = ["succeeded", "approved"]

    /// Starts the timer and the background watcher, once. Neither holds the client alive.
    private func startIfNeeded() {
        guard timer == nil, !stopped else { return }
        let sleep = sleep
        let interval = configuration.flushInterval
        // The timer asks for a flush rather than sending on its own task, so cancelling it never cancels
        // a send whose batch has already left the queue.
        timer = Task { [weak self] in
            while true {
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard let self else { return }
                await self.requestFlush()
            }
        }
        // Subscribed here rather than in the task, so a backgrounding before the task runs is not missed.
        let backgroundings = lifecycle.backgroundings()
        watcher = Task { [weak self] in
            for await window in backgroundings {
                guard let drain = await self?.requestFlush() else {
                    window.close()
                    return
                }
                await drain.value
                window.close()
            }
        }
    }

    /// Schedules a drain after the last one, or joins the one already waiting.
    ///
    /// - Returns: the drain that will send what is queued now.
    @discardableResult
    private func requestFlush() -> Task<Void, Never> {
        if let waiting {
            return waiting
        }
        let previous = tail
        let drain = Task {
            await previous?.value
            self.waiting = nil
            await self.drainWhatWasWaiting()
        }
        waiting = drain
        tail = drain
        return drain
    }

    /// Sends as many requests as what was queued when the drain started needs, up to a bound.
    /// Each request takes what is queued when it leaves.
    private func drainWhatWasWaiting() async {
        let perRequest = configuration.maxEventsPerRequest
        let needed = (queue.count + perRequest - 1) / perRequest
        var requests = min(max(needed, 1), configuration.maxRequestsPerDrain)
        while requests > 0, await sendOneRequest() {
            requests -= 1
        }
    }

    /// Sends one request's worth.
    ///
    /// - Returns: whether anything was sent, accepted or not.
    private func sendOneRequest() async -> Bool {
        let batch = queue.drain(configuration.maxEventsPerRequest)
        guard !batch.isEmpty else { return false }
        // Taken only when a batch leaves: the count resets as it is read.
        let dropped = queue.takeDropCount()
        if dropped > 0 {
            logger.warning("telemetry_queue_overflow dropped=\(dropped)")
        }
        // The session's identifier as it is, already a digest; the route compares it with the one registration sent.
        let device = deviceId().flatMap { $0.isEmpty ? nil : $0 }
        let stamped = batch.map { $0.carrying(deviceIdHash: device) }
        if await !transport.send(stamped, droppedSinceLastSend: dropped) {
            queue.restoreDropCount(dropped)
        }
        return true
    }
}
