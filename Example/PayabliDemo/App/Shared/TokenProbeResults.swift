import SwiftUI

/// The latest answer from each token probe, shared by every screen that runs one
/// or derives a step from one.
///
/// One owner, so the answer travels in both directions: a probe run on the
/// Configuration tab reaches the tab whose sequence reads it, and a tab whose
/// backend step has finished renders no content and so offers no probe button of
/// its own. It also lets a failing probe outrank an earlier success everywhere
/// rather than only in a unit test.
///
/// Three probes, because they are three token functions. `Secrets.swift.sample`
/// forwards the capture one to the stored-method one and says that holds for the
/// sample "unless your backend separates scopes"; `Secrets.swift` is per
/// developer, so a tab reporting on an endpoint it never calls would be
/// answering a different question.
///
/// The fetches are supplied rather than called directly, so the ordering rule
/// below can be tested without a backend.
///
/// Each probe reports only *that* a token arrived. Never the token.
@MainActor
final class TokenProbeResults: ObservableObject {
    typealias Fetch = @Sendable () async throws -> String

    enum Probe: Hashable {
        /// The partner token Tap to Pay attests with.
        case cardPresent
        /// The token the stored-method tab submits with.
        case storedMethod
        /// The token the capture tab submits with.
        case capture
    }

    /// The last answer each probe settled on. A run in flight does not clear it:
    /// the probe is shared, so a run started on the Configuration tab would
    /// otherwise retract a verdict a payment tab had already acted on, and a
    /// backend step that stops being finished takes the form row down with it,
    /// along with the `@StateObject` holding what a payer had typed.
    @Published private(set) var cardPresent = ""
    @Published private(set) var storedMethod = ""
    @Published private(set) var capture = ""

    /// Which probes are in flight, kept apart from the answers for the reason
    /// above. A screen reads it to disable the control that would start another.
    @Published private(set) var running: Set<Probe> = []

    private let fetches: [Probe: Fetch]

    /// Which run of each probe is current. `@MainActor` serialises the writes but
    /// suspends at the fetch, so two probes started from different tabs
    /// interleave and can finish in either order. Without this, a slower earlier
    /// request publishes over the answer a later one already gave, and the shared
    /// state reports something other than the latest.
    private var generations: [Probe: Int] = [:]

    init(
        fetchCardPresent: @escaping Fetch,
        fetchStoredMethod: @escaping Fetch,
        fetchCapture: @escaping Fetch
    ) {
        fetches = [
            .cardPresent: fetchCardPresent,
            .storedMethod: fetchStoredMethod,
            .capture: fetchCapture
        ]
    }

    /// A store whose probes answer immediately and reach no backend, for previews.
    static func inert() -> TokenProbeResults {
        TokenProbeResults(
            fetchCardPresent: { "" },
            fetchStoredMethod: { "" },
            fetchCapture: { "" }
        )
    }

    func answer(for probe: Probe) -> String {
        switch probe {
        case .cardPresent: cardPresent
        case .storedMethod: storedMethod
        case .capture: capture
        }
    }

    func isRunning(_ probe: Probe) -> Bool {
        running.contains(probe)
    }

    /// What a step sequence should read. A run in flight is the answer only while
    /// there is no earlier one to keep; after that the earlier verdict stands
    /// until the new one lands, so the sequence does not step backwards and take
    /// the form down while a payer is filling it in.
    func check(_ probe: Probe) -> TokenCheck {
        let answer = answer(for: probe)
        if answer.isEmpty, isRunning(probe) {
            return .checking
        }
        return TokenCheck.classify(answer)
    }

    /// What a step row should show. Unlike `check`, this does report a run in
    /// flight over an earlier answer, because a row a person is looking at should
    /// say the button they pressed is doing something.
    func display(for probe: Probe) -> String {
        isRunning(probe) ? "Checking…" : answer(for: probe)
    }

    func probeCardPresent() async {
        await run(.cardPresent, named: "Card-present token endpoint")
    }

    func probeStoredMethod() async {
        await run(.storedMethod, named: "Stored-method token endpoint")
    }

    func probeCapture() async {
        await run(.capture, named: "Capture token endpoint")
    }

    private func run(_ probe: Probe, named name: String) async {
        let generation = (generations[probe] ?? 0) + 1
        generations[probe] = generation
        running.insert(probe)

        let answer: String
        do {
            _ = try await fetches[probe]?()
            answer = "✓ \(name) returned a token"
        } catch {
            answer = "✗ \(name) failed: \(error.localizedDescription)"
        }

        // A later run of this probe has already answered, so this one is stale
        // and leaves both the answer and the in-flight set to that later run.
        guard generations[probe] == generation else { return }
        running.remove(probe)
        publish(answer, to: probe)
    }

    private func publish(_ text: String, to probe: Probe) {
        switch probe {
        case .cardPresent: cardPresent = text
        case .storedMethod: storedMethod = text
        case .capture: capture = text
        }
    }
}
