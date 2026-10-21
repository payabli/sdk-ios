@testable import PayabliSDKCore
import XCTest

/// A holder finished by a refused replay refuses every new token, and only a refusal of the token it still holds
/// finishes it.
final class PayabliAuthFinishedTests: XCTestCase {
    func testAFinishedHolderRefusesARefreshWithoutCallingTheProvider() async throws {
        let counter = Counter()
        let auth = try await makeWarmAuth(accessToken: "held", tokenProvider: {
            _ = await counter.increment()
            return "would_be_fresh"
        })
        await auth.finish(with: PayabliGenericError(type: .tokenExpired, reason: "finished"))

        do {
            _ = try await auth.invalidateAndRefresh(rejectedToken: "held")
            XCTFail("a finished holder must not refresh")
        } catch {
            XCTAssertEqual((error as? PayabliGenericError)?.type, .tokenExpired)
        }
        let calls = await counter.count
        XCTAssertEqual(calls, 0)
    }

    func testAFinishedHolderWithNoTokenRefusesTheFirstRead() async throws {
        let counter = Counter()
        let auth = PayabliAuth(config: try makeConfig(tokenProvider: {
            _ = await counter.increment()
            return "would_be_first"
        }))
        await auth.finish(with: PayabliGenericError(type: .tokenExpired, reason: "finished"))

        do {
            _ = try await auth.currentAccessToken()
            XCTFail("a finished holder must not mint")
        } catch {
            XCTAssertEqual((error as? PayabliGenericError)?.type, .tokenExpired)
        }
        let calls = await counter.count
        XCTAssertEqual(calls, 0)
    }

    func testEveryConcurrentCallerOnAFinishedHolderGetsTheSameRefusal() async throws {
        let counter = Counter()
        let auth = try await makeWarmAuth(accessToken: "held", tokenProvider: {
            _ = await counter.increment()
            return "never-minted"
        })
        let finished = await auth.finishIfSettled(
            on: "held",
            with: PayabliGenericError(type: .tokenExpired, reason: "finished")
        )
        XCTAssertTrue(finished)

        let reasons = await withTaskGroup(of: String?.self) { group in
            for _ in 0 ..< 3 {
                group.addTask {
                    do {
                        _ = try await auth.invalidateAndRefresh(rejectedToken: "held")
                        return nil
                    } catch {
                        return (error as? PayabliGenericError)?.reason
                    }
                }
            }
            return await group.reduce(into: [String?]()) { $0.append($1) }
        }

        XCTAssertEqual(reasons, ["finished", "finished", "finished"], "every caller is refused, none waits")
        let calls = await counter.count
        XCTAssertEqual(calls, 0, "no caller reached the provider")
    }

    func testARejectionArrivingWhileItsTokenIsBeingReplacedFinishesNothing() async throws {
        let entered = Slot<String>()
        let release = Latch()
        let auth = try await makeWarmAuth(accessToken: "held", tokenProvider: {
            entered.set("in the provider")
            await release.wait()
            return "replacement"
        })
        let refresh = Task { try await auth.invalidateAndRefresh(rejectedToken: "held") }
        let reached = await valueWithinCeiling(entered)
        XCTAssertNotNil(reached, "the replacement has to be in flight before the rejection is reported")

        let finished = await auth.finishIfSettled(
            on: "held",
            with: PayabliGenericError(type: .tokenExpired, reason: "finished")
        )
        release.open()
        _ = try await refresh.value

        XCTAssertFalse(finished, "the token was being replaced, so its refusal says nothing about the session")
        XCTAssertNil(auth.terminalFailure)
    }
}
