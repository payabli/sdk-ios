import Foundation

/// What a send did with its batch: the route accepted it, kept it for a later flush, or discarded it.
package enum TelemetrySendOutcome: Sendable {
    /// The route accepted the batch.
    case delivered
    /// The batch was not accepted and is kept, so a later flush sends it again.
    case kept
    /// The batch was not accepted and is dropped, because the same body would be refused the same way again.
    case discarded
}

/// Transport abstraction — production uses `URLSession` to POST to the Payabli
/// telemetry endpoint; tests inject an in-memory sink.
package protocol TelemetryTransport: Sendable {
    /// Sends one batch, once. A batch this transport does not accept is kept for a later flush, or
    /// discarded when the same body would be refused the same way again.
    ///
    /// - Parameter batch: the events, oldest first.
    /// - Returns: whether the route accepted the batch, kept it for a later flush, or discarded it.
    @discardableResult
    func send(_ batch: [TelemetryEvent]) async -> TelemetrySendOutcome
}

/// Batched, best-effort telemetry client. The caller never passes a PAN, CVV or token.
///
/// Sends on a full batch, a timer, backgrounding, and at once for a failure. A batch that is not
/// accepted goes back to the front of the queue and is sent on a later flush.
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
            // The overflow event takes one of a request's places, so a request needs one left for anything else.
            precondition(maxEventsPerRequest >= 2, "maxEventsPerRequest must be at least 2")
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
    private let logger: PayabliLogger
    private let deviceId: @Sendable () -> String?
    private var queue: TelemetryQueue

    /// The last drain scheduled. Drains run one after another, so this is also the one that finishes last.
    private var tail: Task<Void, Never>?
    /// A drain scheduled and not yet started. A request made while one waits joins it.
    private var waiting: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    private var stopped = false
    /// Set while `handOff` waits for the drains already scheduled, so a batch kept then stays queued for the successor.
    private var handingOff = false

    /// - Parameter configuration: the batch and queue sizes and the identifiers every event carries.
    /// - Parameter transport: where batches are sent.
    /// - Parameter sleep: the timer's wait.
    /// - Parameter lifecycle: the app's movement to the background.
    /// - Parameter deviceId: the device's identity, read as each batch leaves; `nil` while it cannot be read.
    /// - Parameter queued: events queued before anything else can record, oldest first, held to the catalog as
    ///   `emit` holds them.
    /// - Parameter sessionId: the identifier every event from this client carries.
    /// - Parameter logger: where the client's own log lines go.
    /// - Parameter predecessor: the replaced session's client, whose queue this one takes before its first send, ahead
    ///   of what this one queues; `nil` when nothing is taken over.
    package init(
        configuration: Configuration,
        transport: TelemetryTransport,
        sleep: @escaping Sleep,
        lifecycle: any AppLifecycle,
        deviceId: @escaping @Sendable () -> String?,
        queued: [(name: String, properties: [String: String])],
        sessionId: String = UUID().uuidString,
        logger: PayabliLogger = PayabliLogger(category: .telemetry),
        predecessor: TelemetryClient? = nil
    ) {
        self.configuration = configuration
        self.logger = logger
        self.transport = transport
        self.sleep = sleep
        self.lifecycle = lifecycle
        self.deviceId = deviceId
        self.sessionId = sessionId
        var queue = TelemetryQueue(capacity: configuration.queueCapacity)
        let now = Date()
        for (name, properties) in queued {
            guard let properties = TelemetryCatalog.scrub(name, properties) else { continue }
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
        // The first drain, so every later one and `settled()` wait for what the predecessor hands over.
        if let predecessor {
            tail = Task { [weak self] in
                let handed = await predecessor.handOff()
                await self?.adopt(handed.events, dropped: handed.dropped)
            }
        }
        if !queued.isEmpty {
            Task { [weak self] in await self?.startIfNeeded() }
        }
    }

    deinit {
        timer?.cancel()
        watcher?.cancel()
    }

    /// Stops this client: its timer and its background watcher end, a later record or flush is refused, and one last
    /// drain of at most `maxRequestsPerDrain` requests runs after any drain already scheduled. A batch that drain
    /// cannot send is dropped. Called once, when the session it reports for is replaced.
    package func stop() {
        guard !stopped else { return }
        stopped = true
        timer?.cancel()
        watcher?.cancel()
        let previous = tail
        let bound = configuration.maxRequestsPerDrain
        // Nothing is queued after this, so the drain ends when the queue is empty or the bound is reached.
        tail = Task {
            await previous?.value
            var requests = 0
            while requests < bound, await self.sendOneRequest() {
                requests += 1
            }
        }
    }

    /// Stops this client and gives up what it has queued: its timer and its background watcher end, a later record or
    /// flush is refused, and the drains already scheduled finish first. A batch one of them cannot send stays queued.
    ///
    /// - Returns: the events left, oldest first, and how many the queue evicted that no batch has reported.
    package func handOff() async -> (events: [TelemetryEvent], dropped: Int) {
        stopped = true
        handingOff = true
        timer?.cancel()
        watcher?.cancel()
        await settled()
        handingOff = false
        let events = queue.drain(queue.count)
        return (events, queue.takeDropCount())
    }

    /// Stops this client and drops what it has queued, logging how many events were dropped. Called when the session it
    /// reports for is replaced by one with a different entry point or environment.
    package func discard() async {
        let (events, _) = await handOff()
        logger.debug("telemetry_queue_dropped_on_replacement count=\(events.count)")
    }

    /// Puts a predecessor's events ahead of what this client has queued and sends them, each keeping the session it was
    /// recorded under.
    ///
    /// - Parameter events: the predecessor's events, oldest first.
    /// - Parameter dropped: how many events the predecessor's queue evicted that no batch has reported.
    private func adopt(_ events: [TelemetryEvent], dropped: Int) async {
        queue.restoreFront(events, droppedSinceLastSend: dropped)
        guard !events.isEmpty || dropped > 0 else { return }
        await drainWhatWasWaiting()
    }

    /// Enqueue an event.
    ///
    /// - Parameter name: the event's catalog name.
    /// - Parameter properties: the string values the event carries. A pair the catalog does not allow the event is
    ///   dropped, and an event the catalog does not name is dropped whole.
    package func emit(_ name: String, properties: [String: String] = [:]) async {
        await emit(name, properties: properties, occurredAt: Date())
    }

    /// Enqueue an event stamped with when it happened.
    ///
    /// - Parameter name: the event's catalog name.
    /// - Parameter properties: the string values the event carries. A pair the catalog does not allow the event is
    ///   dropped, and an event the catalog does not name is dropped whole.
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
        guard let properties = TelemetryCatalog.scrub(name, properties) else {
            logger.warning("telemetry_event_unknown: event not in the catalog; dropped")
            return
        }
        guard !stopped else {
            logger.debug("telemetry_event_after_stop: this channel was stopped; dropped")
            return
        }
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
        // Counts what was offered since the last send attempt, so a refused batch back on the queue does not
        // make every later event a full batch.
        let offered = queue.offer(event)
        if offered >= configuration.batchSize || (!waitsForBatch && Self.sendsAtOnce(name, properties)) {
            requestFlush()
        }
    }

    /// Sends everything queued, and returns once the flush has finished; a batch that is kept stays
    /// queued for a later flush.
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

    /// The events waiting to be sent, oldest first.
    var queuedEvents: [TelemetryEvent] {
        queue.events
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
        guard let outcome = properties[TelemetryProperty.outcome.rawValue] else { return false }
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
        // A stopped client's last drain is already scheduled, so a request waits for it and adds nothing.
        if stopped, let tail {
            return tail
        }
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

    /// Sends as many requests as what was queued when the drain started needs, up to a bound. Each
    /// request takes what is queued when it leaves, and a kept batch stops the drain, so a failure
    /// sends no second request.
    private func drainWhatWasWaiting() async {
        // Every request may carry an overflow event, since a discarded batch gives its count back. A request
        // left with nothing to send is not made and ends the drain, so the spare places cost nothing.
        let perRequest = configuration.maxEventsPerRequest - 1
        let needed = (queue.count + perRequest - 1) / perRequest
        var requests = min(max(needed, 1), configuration.maxRequestsPerDrain)
        while requests > 0, await sendOneRequest() {
            requests -= 1
        }
    }

    /// Sends one request's worth.
    ///
    /// - Returns: whether the drain may send another request.
    private func sendOneRequest() async -> Bool {
        let dropped = queue.takeDropCount()
        // The overflow event takes one of the request's places, so a request never carries more than
        // `maxEventsPerRequest` events.
        let perRequest = configuration.maxEventsPerRequest
        let batch = queue.drain(dropped > 0 ? perRequest - 1 : perRequest)
        // The count resets as it is read, so a count taken with nothing to send goes back for a later batch.
        guard !batch.isEmpty else {
            queue.restoreDropCount(dropped)
            return false
        }
        var events = batch
        if dropped > 0 {
            logger.warning("telemetry_queue_overflow dropped=\(dropped)")
            if let overflow = overflowEvent(dropped) {
                events.append(overflow)
            }
        }
        // The session's identifier as it is, already a digest; the route compares it with the one registration sent.
        let device = deviceId().flatMap { $0.isEmpty ? nil : $0 }
        let stamped = events.map { $0.carrying(deviceIdHash: device) }
        switch await transport.send(stamped) {
        case .delivered:
            return true
        case .kept:
            // Nothing reads a stopped client's queue after its last drain, so a batch kept then is dropped and the
            // drain moves on to the next. A client handing its queue over keeps the batch for its successor.
            guard !stopped || handingOff else {
                queue.restoreDropCount(dropped)
                logger.debug("telemetry_batch_after_stop count=\(batch.count)")
                return true
            }
            // The count goes back beside the events rather than as an event among them, so the events offered
            // during the send can evict the batch but never the count.
            queue.restoreFront(batch, droppedSinceLastSend: dropped)
            return false
        case .discarded:
            queue.restoreDropCount(dropped)
            return true
        }
    }

    /// The event that reports evictions, last in its batch and timed when the send noticed them.
    ///
    /// - Parameter dropped: how many events the queue evicted, more than zero.
    /// - Returns: the event to append to the batch, or `nil` when the catalog does not name it.
    private func overflowEvent(_ dropped: Int) -> TelemetryEvent? {
        guard let properties = TelemetryCatalog.scrub(
            TelemetryEventName.sdkTelemetryOverflow,
            [TelemetryProperty.dropped.rawValue: String(dropped)]
        ) else { return nil }
        return TelemetryEvent(
            sdkVersion: configuration.sdkVersion,
            sessionId: sessionId,
            deviceIdHash: nil,
            entry: configuration.entry,
            environment: configuration.environment,
            event: TelemetryEventName.sdkTelemetryOverflow,
            properties: properties,
            timestamp: Date()
        )
    }
}
