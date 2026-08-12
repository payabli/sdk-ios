import XCTest

/// The probes are shared across tabs, so two runs of one can be in flight at
/// once and finish in either order. These pin the rule that the run started last
/// is the one that publishes, and that the three probes are separate answers.
@MainActor
final class TokenProbeResultsTests: XCTestCase {
    /// Holds each fetch until the test releases it, so the finishing order is the
    /// test's choice. Ordering asserted against real timing would be a coin toss.
    private actor Latch {
        private var entered = 0
        private var held: [Int: CheckedContinuation<Void, Never>] = [:]

        func enter() -> Int {
            entered += 1
            return entered
        }

        func count() -> Int {
            entered
        }

        func hold(_ run: Int) async {
            await withCheckedContinuation { held[run] = $0 }
        }

        func release(_ run: Int) {
            held.removeValue(forKey: run)?.resume()
        }
    }

    private struct Refused: Error, LocalizedError {
        var errorDescription: String? {
            "refused"
        }
    }

    private let succeeded = "✓ Card-present token endpoint returned a token"
    private let failed = "✗ Card-present token endpoint failed: refused"

    /// Bounded, so a condition that never holds fails with a name instead of
    /// running the suite into its timeout.
    private func waitUntil(
        _ description: String,
        _ condition: () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0 ..< 1000 {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("never became true: \(description)", file: file, line: line)
    }

    func testAnEarlierRunFinishingLastDoesNotOverwriteTheLatestAnswer() async {
        let latch = Latch()
        // The first run refuses and the second succeeds, so which one published
        // is visible in the text rather than inferred.
        let store = TokenProbeResults(
            fetchCardPresent: {
                let run = await latch.enter()
                await latch.hold(run)
                if run == 1 {
                    throw Refused()
                }
                return "token"
            },
            fetchStoredMethod: { "" },
            fetchCapture: { "" }
        )

        let first = Task { await store.probeCardPresent() }
        await waitUntil("the first run reaches its fetch") { await latch.count() >= 1 }
        let second = Task { await store.probeCardPresent() }
        await waitUntil("the second run reaches its fetch") { await latch.count() >= 2 }

        await latch.release(2)
        await second.value
        XCTAssertEqual(store.cardPresent, succeeded)

        await latch.release(1)
        await first.value
        XCTAssertEqual(
            store.cardPresent, succeeded,
            "the first run published over an answer given after it started"
        )
    }

    func testASingleRunStillPublishes() async {
        let store = TokenProbeResults(
            fetchCardPresent: { "token" },
            fetchStoredMethod: { "" },
            fetchCapture: { "" }
        )

        await store.probeCardPresent()

        XCTAssertEqual(store.cardPresent, succeeded)
    }

    func testAFailureIsPublishedLikeAnyOtherAnswer() async {
        let store = TokenProbeResults(
            fetchCardPresent: { throw Refused() },
            fetchStoredMethod: { "" },
            fetchCapture: { "" }
        )

        await store.probeCardPresent()

        XCTAssertEqual(store.cardPresent, failed)
    }

    /// The two card-not-present tabs submit with different token functions, so
    /// one answering must not answer for the other.
    func testTheThreeProbesAreSeparateAnswers() async {
        let store = TokenProbeResults(
            fetchCardPresent: { "token" },
            fetchStoredMethod: { "token" },
            fetchCapture: { throw Refused() }
        )

        await store.probeStoredMethod()

        XCTAssertEqual(store.storedMethod, "✓ Stored-method token endpoint returned a token")
        XCTAssertEqual(store.cardPresent, "")
        XCTAssertEqual(store.capture, "")

        await store.probeCapture()

        XCTAssertEqual(store.capture, "✗ Capture token endpoint failed: refused")
        XCTAssertEqual(store.storedMethod, "✓ Stored-method token endpoint returned a token")
    }
}
