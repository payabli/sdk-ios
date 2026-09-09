@testable import PayabliSDKCore
import XCTest

final class PayabliAuthTests: XCTestCase {
    // MARK: - Helpers

    private func makeConfig(
        accessToken: String = "partner_minted_token",
        tokenProvider: PayabliTokenRefresh? = nil
    ) throws -> PayabliConfig {
        try PayabliConfig(
            accessToken: accessToken,
            tokenProvider: tokenProvider,
            entryPoint: "test_entry",
            environment: .sandbox
        )
    }

    // MARK: - Initial token

    func testInitialTokenComesFromConfig() async throws {
        let auth = PayabliAuth(config: try makeConfig(accessToken: "seed"))
        let token = await auth.currentAccessToken()
        XCTAssertEqual(token, "seed")
    }

    // MARK: - Refresh via tokenProvider

    func testInvalidateAndRefreshCallsProvider() async throws {
        let counter = Counter()
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: {
                _ = await counter.increment()
                return "fresh_from_partner"
            }
        ))

        let fresh = try await auth.invalidateAndRefresh(rejectedToken: "old")
        XCTAssertEqual(fresh, "fresh_from_partner")
        let calls = await counter.count
        XCTAssertEqual(calls, 1)

        // Subsequent currentAccessToken returns the refreshed value.
        let current = await auth.currentAccessToken()
        XCTAssertEqual(current, "fresh_from_partner")
    }

    func testInvalidateAndRefreshWithoutProviderThrowsTokenExpired() async throws {
        let auth = PayabliAuth(config: try makeConfig(accessToken: "old", tokenProvider: nil))
        do {
            _ = try await auth.invalidateAndRefresh(rejectedToken: "old")
            XCTFail("expected throw")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .tokenExpired)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testInvalidateAndRefreshCoalescesConcurrentCallers() async throws {
        let counter = Counter()
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: {
                _ = await counter.increment()
                try await Task.sleep(nanoseconds: 20_000_000)
                return "fresh"
            }
        ))

        async let a = auth.invalidateAndRefresh(rejectedToken: "old")
        async let b = auth.invalidateAndRefresh(rejectedToken: "old")
        async let c = auth.invalidateAndRefresh(rejectedToken: "old")
        let results = try await [a, b, c]

        XCTAssertEqual(Set(results), ["fresh"])
        let calls = await counter.count
        XCTAssertEqual(calls, 1, "Concurrent refresh requests should share a single in-flight Task")
    }

    // MARK: - A provider that calls back into the SDK

    /// A caller already inside this holder's own provider is answered with the token being replaced,
    /// rather than joining the refresh that is waiting on it.
    ///
    /// Bounded: without the reentrancy step this wedges, and an unbounded wait would hang the suite
    /// rather than report.
    func testACallFromInsideTheProviderIsAnsweredInsteadOfJoining() async throws {
        let holder = Slot<PayabliAuth>()
        let nested = Slot<String>()
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: {
                let inner = try? await holder.value!.invalidateAndRefresh(rejectedToken: "old")
                nested.set(inner ?? "threw")
                return "fresh"
            }
        ))
        holder.set(auth)

        let outcome = await outcomeWithinCeiling {
            (try? await auth.invalidateAndRefresh(rejectedToken: "old")) ?? "threw"
        }

        guard let outcome else {
            return XCTFail("the refresh never finished: the nested call joined the refresh awaiting it")
        }
        XCTAssertEqual(outcome, "fresh")
        XCTAssertEqual(nested.value, "old", "a nested call receives the token being replaced")
    }

    /// The mark names the holder, so a nested call into a *different* holder is an ordinary caller
    /// there and refreshes normally. A mark that recorded only that some refresh was running would
    /// short-circuit this one and hand back its stale token.
    func testAProviderCallingADifferentHolderStillRefreshesThere() async throws {
        let other = PayabliAuth(config: try makeConfig(
            accessToken: "other-old",
            tokenProvider: { "other-fresh" }
        ))
        let nested = Slot<String>()
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "own-old",
            tokenProvider: {
                let inner = try? await other.invalidateAndRefresh(rejectedToken: "other-old")
                nested.set(inner ?? "threw")
                return "own-fresh"
            }
        ))

        let fresh = try await auth.invalidateAndRefresh(rejectedToken: "own-old")

        XCTAssertEqual(fresh, "own-fresh")
        XCTAssertEqual(nested.value, "other-fresh", "a second holder's refresh is not this one's")
    }

    /// Two holders whose providers call each other. The second holder is an ordinary caller of the
    /// first, so it starts its own refresh; the mark has to record both, because the call that comes
    /// back is a call into the outer one.
    ///
    /// Recording only the innermost holder leaves the outer one unmarked, and the callback joins the
    /// refresh that is waiting on it. Bounded for that reason.
    func testTwoHoldersWhoseProvidersCallEachOtherBothComplete() async throws {
        let first = Slot<PayabliAuth>()
        let backIntoTheFirst = Slot<String>()

        let second = PayabliAuth(config: try makeConfig(
            accessToken: "second-old",
            tokenProvider: {
                let inner = try? await first.value!.invalidateAndRefresh(rejectedToken: "first-old")
                backIntoTheFirst.set(inner ?? "threw")
                return "second-fresh"
            }
        ))
        let outer = PayabliAuth(config: try makeConfig(
            accessToken: "first-old",
            tokenProvider: {
                _ = try? await second.invalidateAndRefresh(rejectedToken: "second-old")
                return "first-fresh"
            }
        ))
        first.set(outer)

        let outcome = await outcomeWithinCeiling {
            (try? await outer.invalidateAndRefresh(rejectedToken: "first-old")) ?? "threw"
        }

        guard let outcome else {
            return XCTFail("the refresh never finished: a callback joined the refresh awaiting it")
        }
        XCTAssertEqual(outcome, "first-fresh")
        XCTAssertEqual(
            backIntoTheFirst.value,
            "first-old",
            "a call back into an enclosing holder is answered, not joined"
        )
        let settled = await outer.currentAccessToken()
        XCTAssertEqual(settled, "first-fresh")
    }

    /// A task the provider leaves running outlives the refresh that marked it, and an unstructured
    /// `Task` inherits task-local values, so the mark it captured survives past the refresh it belongs
    /// to. It must not answer a later rejection on this holder.
    ///
    /// Bounded: the escaped task is polled for rather than awaited, since nothing else owns it.
    func testATaskLeftRunningByTheProviderDoesNotAnswerALaterRejection() async throws {
        let holder = Slot<PayabliAuth>()
        let escaped = Slot<String>()
        let released = Latch()
        let providerCalls = Counter()

        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: {
                let call = await providerCalls.increment()
                guard call == 1 else { return "second" }
                Task {
                    await released.wait()
                    let later = try? await holder.value!.invalidateAndRefresh(rejectedToken: "first")
                    escaped.set(later ?? "threw")
                }
                return "first"
            }
        ))
        holder.set(auth)

        let first = try await auth.invalidateAndRefresh(rejectedToken: "old")
        XCTAssertEqual(first, "first")

        released.open()

        guard let later = await valueWithinCeiling(escaped) else {
            return XCTFail("the task the provider left running never finished")
        }
        XCTAssertEqual(later, "second", "a mark left behind must not answer a later rejection")
        let calls = await providerCalls.count
        XCTAssertEqual(calls, 2, "the later rejection starts its own refresh")
    }

    /// The same mark, but a later refresh on this holder is in flight when the escaped task calls.
    ///
    /// The mark names the refresh it belongs to, so the call joins the live refresh. Dropping the
    /// refresh half of the check and keeping the holder half leaves this answered immediately, from a
    /// mark whose own refresh is long over, with the token that was just rejected.
    func testAMarkFromAFinishedRefreshJoinsTheLiveOneRatherThanAnsweringIt() async throws {
        let holder = Slot<PayabliAuth>()
        let escaped = Slot<String>()
        let escapedAtTheCall = Slot<String>()
        let secondProviderEntered = Slot<String>()
        let releaseEscaped = Latch()
        let releaseSecondProvider = Latch()
        let providerCalls = Counter()

        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: {
                let call = await providerCalls.increment()
                guard call > 1 else {
                    Task {
                        await releaseEscaped.wait()
                        escapedAtTheCall.set("at the call")
                        let seen = try? await holder.value!.invalidateAndRefresh(rejectedToken: "first")
                        escaped.set(seen ?? "threw")
                    }
                    return "first"
                }
                secondProviderEntered.set("entered")
                await releaseSecondProvider.wait()
                return "second"
            }
        ))
        holder.set(auth)

        let first = try await auth.invalidateAndRefresh(rejectedToken: "old")
        XCTAssertEqual(first, "first")

        let secondRefresh = Task { try? await auth.invalidateAndRefresh(rejectedToken: "first") }
        guard await valueWithinCeiling(secondProviderEntered) != nil else {
            return XCTFail("the second refresh never reached its provider")
        }

        // The escaped call runs while that refresh is still in flight. Joining it means nothing is set
        // yet; answering from the stale mark would already have set the rejected token.
        releaseEscaped.open()
        guard await valueWithinCeiling(escapedAtTheCall) != nil else {
            return XCTFail("the task the provider left running never resumed")
        }
        let answeredEarly = await valueWithinCeiling(escaped, attempts: 12)
        releaseSecondProvider.open()
        _ = await secondRefresh.value

        XCTAssertNil(answeredEarly, "a mark whose own refresh had finished answered instead of joining")
        let joined = await valueWithinCeiling(escaped)
        XCTAssertEqual(joined, "second", "the call takes the live refresh's outcome")
    }

    /// A detached caller the provider does not await, driving the recovery path directly. It inherits
    /// no mark, so it is an ordinary caller: it joins the refresh in flight rather than being answered
    /// from inside it, and completes once the provider has returned.
    ///
    /// The shape that cannot finish is the provider awaiting such work once it is refused, which is
    /// what the public documentation rules out. Fire and forget is not that shape.
    func testADetachedRequestTheProviderDoesNotAwaitCompletes() async throws {
        let holder = Slot<PayabliAuth>()
        let detached = Slot<String>()
        let providerCalls = Counter()

        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: {
                _ = await providerCalls.increment()
                Task.detached {
                    let seen = try? await holder.value!.invalidateAndRefresh(rejectedToken: "old")
                    detached.set(seen ?? "threw")
                }
                return "fresh"
            }
        ))
        holder.set(auth)

        let fresh = try await auth.invalidateAndRefresh(rejectedToken: "old")
        XCTAssertEqual(fresh, "fresh")

        guard let seen = await valueWithinCeiling(detached) else {
            return XCTFail("the detached request never finished")
        }
        // The same answer whether it joined the refresh in flight or arrived after it had rotated.
        XCTAssertEqual(seen, "fresh")
        let calls = await providerCalls.count
        XCTAssertEqual(calls, 1, "the detached request must not spend a second provider call")
    }

    /// A task the provider leaves running keeps its inherited marks for as long as it lives, so a mark
    /// holding the session would keep the session, and the credential in it, alive after the host had
    /// released both.
    func testATaskLeftRunningDoesNotRetainTheSession() async throws {
        weak var session: PayabliAuth?
        let released = Latch()
        let spawned = Slot<String>()

        do {
            // The closure captures the latch and the slot, never the session.
            let auth = PayabliAuth(config: try makeConfig(
                accessToken: "old",
                tokenProvider: {
                    Task {
                        await released.wait()
                        spawned.set("done")
                    }
                    return "fresh"
                }
            ))
            session = auth
            let fresh = try await auth.invalidateAndRefresh(rejectedToken: "old")
            XCTAssertEqual(fresh, "fresh")
        }

        // The spawned task is still parked, so anything it holds is still held.
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(session, "a task left running kept the session alive through its inherited mark")

        released.open()
        _ = await valueWithinCeiling(spawned)
    }

    func testProviderErrorMapsToTokenExpired() async throws {
        struct ProviderError: Error {}
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: { throw ProviderError() }
        ))
        do {
            _ = try await auth.invalidateAndRefresh(rejectedToken: "old")
            XCTFail("expected throw")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .tokenExpired)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    /// A refresh that failed leaves nothing installed, so the next rejection reaches the provider.
    ///
    /// Both of a refresh's endings clear the marker, and a failure that skipped it would leave a
    /// finished task in flight: every later rejection joins that task and is handed the failure it
    /// already produced, for the life of the session.
    func testAFailedRefreshDoesNotStandInForTheNextOne() async throws {
        struct ProviderError: Error {}
        let calls = Counter()
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: {
                let call = await calls.increment()
                guard call > 1 else { throw ProviderError() }
                return "fresh"
            }
        ))

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
        let auth = try makeRacingAuth(race)
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
        XCTAssertEqual(count, 2, "the last rejection joined the refresh in flight rather than starting one")
    }

    // MARK: - The rejected token

    /// Two requests sent with the same token can have their 401s arrive far apart.
    /// The later one must not spend a provider call replacing a token that has
    /// already rotated, which would discard the rotation the first one obtained.
    func testARejectionOnAnAlreadyRotatedTokenDoesNotCallTheProvider() async throws {
        let counter = Counter()
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: {
                _ = await counter.increment()
                return "fresh"
            }
        ))

        let first = try await auth.invalidateAndRefresh(rejectedToken: "old")
        XCTAssertEqual(first, "fresh")

        let second = try await auth.invalidateAndRefresh(rejectedToken: "old")
        XCTAssertEqual(second, "fresh", "The stale 401 should be answered with the rotated token")

        let calls = await counter.count
        XCTAssertEqual(calls, 1, "The second rejection names a token that is no longer current")
    }

    // MARK: - What may be committed

    func testAProviderReturningTheRejectedTokenFailsRatherThanLooping() async throws {
        let counter = Counter()
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: {
                _ = await counter.increment()
                return "old"
            }
        ))

        do {
            _ = try await auth.invalidateAndRefresh(rejectedToken: "old")
            XCTFail("expected throw")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .tokenExpired)
        }

        let calls = await counter.count
        XCTAssertEqual(calls, 1)
        let current = await auth.currentAccessToken()
        XCTAssertEqual(current, "old", "The refused credential must not be committed")
    }

    /// Whitespace is printable ASCII, so a token of spaces passes the header check
    /// and would be committed carrying nothing.
    func testABlankRefreshedTokenIsNotCommitted() async throws {
        for blank in ["", " ", "   ", "\t\n"] {
            let auth = PayabliAuth(config: try makeConfig(
                accessToken: "old",
                tokenProvider: { blank }
            ))

            do {
                _ = try await auth.invalidateAndRefresh(rejectedToken: "old")
                XCTFail("expected throw for \(blank.debugDescription)")
            } catch let err as PayabliGenericError {
                XCTAssertEqual(err.code, .tokenExpired, blank.debugDescription)
            }

            let current = await auth.currentAccessToken()
            XCTAssertEqual(current, "old", blank.debugDescription)
        }
    }

    // MARK: - What a joining caller receives

    /// A caller that arrives while a refresh is in flight awaits the same task, so
    /// the checks have to be inside it. Otherwise the joiner returns a token nothing
    /// validated.
    func testAJoinerDoesNotReceiveAnUnvalidatedToken() async throws {
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: {
                try await Task.sleep(nanoseconds: 30_000_000)
                return "   "
            }
        ))

        async let first = auth.invalidateAndRefresh(rejectedToken: "old")
        async let second = auth.invalidateAndRefresh(rejectedToken: "old")

        for outcome in await [try? first, try? second] {
            XCTAssertNil(outcome, "a blank token reached a caller")
        }
        let current = await auth.currentAccessToken()
        XCTAssertEqual(current, "old")
    }

    /// The provider's text must not reach a joiner either, which it does when the
    /// redaction is applied by the initiating caller rather than inside the task.
    func testAJoinerDoesNotReceiveTheProvidersOwnMessage() async throws {
        struct ChattyProviderError: Error {
            let responseBody: String
        }
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: {
                try await Task.sleep(nanoseconds: 30_000_000)
                throw ChattyProviderError(responseBody: "SHOULD_NOT_LEAVE_THE_PROVIDER")
            }
        ))

        async let first = auth.invalidateAndRefresh(rejectedToken: "old")
        async let second = auth.invalidateAndRefresh(rejectedToken: "old")

        var rendered = ""
        do {
            _ = try await first
            XCTFail("expected the initiating caller to fail")
        } catch {
            rendered += " \(error) \(String(describing: (error as? PayabliGenericError)?.underlying))"
        }
        do {
            _ = try await second
            XCTFail("expected the joining caller to fail")
        } catch {
            rendered += " \(error) \(String(describing: (error as? PayabliGenericError)?.underlying))"
        }
        XCTAssertFalse(rendered.contains("SHOULD_NOT_LEAVE_THE_PROVIDER"), rendered)
    }

    /// A CR or LF in a bearer is header injection, and the platform drops the header
    /// rather than reporting it, so the request goes out unauthenticated.
    func testATokenThatCannotBeAHeaderValueIsNotCommitted() async throws {
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: { "fresh\r\nX-Injected: true" }
        ))

        do {
            _ = try await auth.invalidateAndRefresh(rejectedToken: "old")
            XCTFail("expected throw")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .tokenMalformed)
        }

        let current = await auth.currentAccessToken()
        XCTAssertEqual(current, "old")
    }

    // MARK: - What the provider's failure may carry

    /// The provider is host code and its error text can name the host's own endpoint
    /// or quote a response body. An `underlying` error reaches a crash reporter the
    /// SDK does not scrub.
    func testTheProvidersOwnMessageDoesNotReachTheErrorChain() async throws {
        // A stored property, because that is what a rendered error shows. A type
        // with none renders as its own name whatever `errorDescription` returns,
        // which would make this assertion unable to fail.
        struct ChattyProviderError: Error {
            let responseBody: String
        }
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: { throw ChattyProviderError(responseBody: "SHOULD_NOT_LEAVE_THE_PROVIDER") }
        ))

        do {
            _ = try await auth.invalidateAndRefresh(rejectedToken: "old")
            XCTFail("expected throw")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .tokenExpired)
            let rendered = "\(err) \(err.localizedDescription) \(String(describing: err.underlying))"
            XCTAssertFalse(
                rendered.contains("SHOULD_NOT_LEAVE_THE_PROVIDER"),
                "the provider's own text reached the error chain: \(rendered)"
            )
            XCTAssertTrue(
                rendered.contains("ChattyProviderError"),
                "the failing type should survive, since it names no subject: \(rendered)"
            )
        }
    }
}
