import SwiftUI

/// The latest answer from each token probe, shared by every screen that runs one
/// or derives a step from one.
///
/// Each screen used to keep its own copy, which made the answer unshareable in
/// both directions. A probe run on the Configuration tab could not reach the tab
/// whose sequence reads it, and a tab whose backend step had already finished
/// renders no content, so its own probe button was gone. Between them a failing
/// probe could not be made to outrank an earlier success anywhere except a unit
/// test.
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

    @Published private(set) var cardPresent = ""
    @Published private(set) var storedMethod = ""
    @Published private(set) var capture = ""

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
        publish("Checking…", to: probe)

        let answer: String
        do {
            _ = try await fetches[probe]?()
            answer = "✓ \(name) returned a token"
        } catch {
            answer = "✗ \(name) failed: \(error.localizedDescription)"
        }

        // A later run of this probe has already answered, so this one is stale.
        guard generations[probe] == generation else { return }
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
