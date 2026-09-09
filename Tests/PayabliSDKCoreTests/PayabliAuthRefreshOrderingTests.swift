import Foundation
@testable import PayabliSDKCore
import XCTest

/// What a refresh leaves behind when it ends, and what a caller waiting on one may clear.
///
/// Its own class because both cases build an order rather than assert a value, and the holder's
/// own suite is about what it answers.
final class PayabliAuthRefreshOrderingTests: XCTestCase {
    /// A refresh that failed leaves nothing installed, so the next rejection reaches the provider.
    ///
    /// Both of a refresh's endings clear the marker, and a failure that skipped it would leave a
    /// finished task in flight: every later rejection joins that task and is handed the failure it
    /// already produced, for the life of the session.
    func testAFailedRefreshDoesNotStandInForTheNextOne() async throws {
        struct ProviderError: Error {}
        let calls = Counter()
        // Warm, because the subject is what a failed refresh leaves behind rather than how the first
        // token arrives, and a holder now has none until it asks.
        let auth = try await makeWarmAuth(accessToken: "old", tokenProvider: {
            let call = await calls.increment()
            guard call > 1 else { throw ProviderError() }
            return "fresh"
        })

        do {
            _ = try await auth.invalidateAndRefresh(rejectedToken: "old")
            XCTFail("the first refresh has to fail")
        } catch {
            // The mapped failure is `testProviderErrorMapsToTokenExpired`'s subject, not this one's.
        }

        let second = try await auth.invalidateAndRefresh(rejectedToken: "old")

        XCTAssertEqual(second, "fresh")
        let count = await calls.count
        XCTAssertEqual(count, 2, "the second rejection reaches the provider, not a task that has ended")
    }

    /// A caller cancelled while waiting does not clear the refresh that started after its own.
    ///
    /// Cancellation is reported once the refresh being waited on has committed and cleared, and the
    /// holder is free between those two points. A rejection arriving there installs a refresh of its
    /// own, and a clear naming no refresh took that one's marker with it: the next rejection found
    /// nothing in flight and called the provider alongside it.
    ///
    /// The holder is serial, so the order is built rather than waited for. The commit holds its turn
    /// inside the log sink, the second caller is enqueued behind it, and the cancelled caller resumes
    /// only once that turn ends, which puts its cleanup after that install.
    func testACancelledCallerDoesNotClearTheRefreshThatFollowedIt() async throws {
        let race = RefreshRace()
        let auth = try await makeRacingAuth(race)
        let (firstProvider, committing) = (race.firstProvider, race.committing)
        let (secondProvider, thirdProvider) = (race.secondProvider, race.thirdProvider)
        let (followerCalling, joinerCalling) = (race.followerCalling, race.joinerCalling)
        let (releaseFirst, releaseSecond) = (race.releaseFirst, race.releaseSecond)
        let (calls, sink) = (race.calls, race.sink)

        let cancelled = Task { try await auth.invalidateAndRefresh(rejectedToken: "first") }
        guard await valueWithinCeiling(firstProvider) != nil else {
            return XCTFail("the first refresh never reached its provider")
        }
        cancelled.cancel()
        releaseFirst.open()

        // The commit holds the holder from inside the sink. A call made now is enqueued behind that turn
        // and runs before the cancelled caller, which is resumed only when the turn ends.
        guard await valueWithinCeiling(committing) != nil else {
            return XCTFail("the first refresh never committed")
        }
        let follower = Task {
            followerCalling.set("calling")
            return try? await auth.invalidateAndRefresh(rejectedToken: "second")
        }
        guard await valueWithinCeiling(followerCalling) != nil else {
            return XCTFail("the second caller never ran")
        }
        sink.open()

        guard await valueWithinCeiling(secondProvider) != nil else {
            return XCTFail("the second refresh never reached its provider")
        }

        // That refresh stays in its provider until this case releases it, so the last caller cannot
        // arrive after it finished and take the already-rotated path instead of joining it.
        let joiner = Task {
            joinerCalling.set("calling")
            return try? await auth.invalidateAndRefresh(rejectedToken: "second")
        }
        guard await valueWithinCeiling(joinerCalling) != nil else {
            return XCTFail("the last caller never ran")
        }
        let startedItsOwn = await valueWithinCeiling(thirdProvider, attempts: 12)
        releaseSecond.open()

        let joined = await joiner.value
        _ = await follower.value
        do {
            _ = try await cancelled.value
            XCTFail("the cancelled caller has to report cancellation")
        } catch is CancellationError {
            // What puts it on the path this case is about.
        }

        XCTAssertNil(startedItsOwn, "the marker was cleared, so the last rejection called the provider")
        XCTAssertEqual(joined, "third", "it took the refresh in flight's own answer")
        let count = await calls.count
        XCTAssertEqual(
            count, 3,
            "one acquisition and two refreshes: the last rejection joined rather than starting one"
        )
    }
}
