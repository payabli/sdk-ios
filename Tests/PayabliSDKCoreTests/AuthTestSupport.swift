import Foundation
@testable import PayabliSDKCore

// Fixtures for the refresh-ordering case, out of the suite because a test class has a size bound and a
// fixture is not what that bound is for.

/// The pieces the refresh-ordering case drives, kept together so the case reads as the order it
/// builds rather than as its setup.
struct RefreshRace {
    let firstProvider = Slot<String>()
    let committing = Slot<String>()
    let secondProvider = Slot<String>()
    let thirdProvider = Slot<String>()
    let followerCalling = Slot<String>()
    let joinerCalling = Slot<String>()
    let releaseFirst = Latch()
    let releaseSecond = Latch()
    let calls = Counter()
    let sink: HoldingLogSink

    init() {
        // The second install: the first is the token the holder acquires before any rejection.
        sink = HoldingLogSink(holdingOn: "Access token installed", occurrence: 2, entered: committing)
    }
}

/// A holder already carrying a token, whose provider then mints once per rejection and holds the two the
/// case needs. A further call is the failure the case looks for, so it names itself and returns.
///
/// The first call is the acquisition rather than a rejection: the host supplies a provider and nothing
/// else, so a holder has no token until it asks for one.
func makeRacingAuth(_ race: RefreshRace) async throws -> PayabliAuth {
    let auth = PayabliAuth(
        config: try PayabliConfig(
            entryPoint: "test_entry",
            environment: .sandbox,
            tokenProvider: {
                switch await race.calls.increment() {
                case 1:
                    return "first"
                case 2:
                    race.firstProvider.set("entered")
                    await race.releaseFirst.wait()
                    return "second"
                case 3:
                    race.secondProvider.set("entered")
                    await race.releaseSecond.wait()
                    return "third"
                default:
                    race.thirdProvider.set("entered")
                    return "fourth"
                }
            }
        ),
        logger: PayabliLogger(category: .auth, sink: race.sink)
    )
    _ = try await auth.currentAccessToken()
    return auth
}

/// `accessToken`, when given, is what the provider answers on its first call; `tokenProvider` serves
/// every call after it. The holder carries no seed, so a test that starts on one token and rotates to
/// another says so here.
func makeConfig(
    accessToken: String? = nil,
    tokenProvider: PayabliTokenRefresh? = nil
) throws -> PayabliConfig {
    let calls = Counter()
    return try PayabliConfig(
        entryPoint: "test_entry",
        environment: .sandbox,

        tokenProvider: {
            let call = await calls.increment()
            if let accessToken, call == 1 {
                return accessToken
            }
            if let tokenProvider {
                return try await tokenProvider()
            }
            return accessToken ?? "partner_minted_token"
        }
    )
}

/// A holder with `accessToken` already installed, for the tests whose subject is what happens
/// to a token that is already held rather than how the first one arrives.
func makeWarmAuth(
    accessToken: String,
    tokenProvider: PayabliTokenRefresh? = nil
) async throws -> PayabliAuth {
    let auth = PayabliAuth(
        config: try makeConfig(accessToken: accessToken, tokenProvider: tokenProvider)
    )
    _ = try await auth.currentAccessToken()
    return auth
}

/// Fires its first deadline and parks on every one after, so a provider-bound case can race exactly
/// one mint against the bound and then prove the next mint is unraced — a clock that kept firing
/// would also time out the recovery the case is checking, rather than let the provider that answers
/// it win.
class FiresOnceRetryClock: RetryClock, @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    /// Every `seconds` this clock was asked to expire after, in call order — so a case can assert
    /// `PayabliAuth` raced the bound it documents (30s) rather than some other number.
    private(set) var requestedDeadlines: [TimeInterval] = []

    func elapsed() -> TimeInterval {
        0
    }

    func sleep(for seconds: TimeInterval) async throws {}

    func expire(after seconds: TimeInterval) async throws {
        lock.lock()
        let isFirst = !fired
        fired = true
        requestedDeadlines.append(seconds)
        lock.unlock()
        guard isFirst else {
            try await Task.sleep(nanoseconds: .max)
            return
        }
        await firstDeadlineReached()
    }

    /// Runs once, when the first `expire(after:)` would otherwise resolve. The base class resolves
    /// immediately; a subclass gating that moment overrides this rather than `expire(after:)` itself,
    /// so the recording and the once-only guard above stay in one place.
    func firstDeadlineReached() async {}
}

/// Fires its first deadline once `admitted` opens. A case racing several callers against the same
/// deadline needs every one of them to have actually joined the one live mint first, or a caller
/// the actor had not yet reached finds the mint already released by an earlier caller's timeout
/// and starts a second one, which this clock — having fired once — then parks on forever.
final class GatedFiresOnceRetryClock: FiresOnceRetryClock, @unchecked Sendable {
    private let admitted: Latch

    init(admittedAfter admitted: Latch) {
        self.admitted = admitted
    }

    override func firstDeadlineReached() async {
        await admitted.wait()
    }
}

/// Opens `admitted` on the `occurrence`th call to `admit()`, so a test can gate a synchronized
/// deadline on every intended caller having joined the one in-flight mint. Driven by
/// `PayabliAuth`'s `onJoinedInFlightMint` hook.
final class AdmissionCounter: @unchecked Sendable {
    private let occurrence: Int
    private let admitted: Latch
    private let lock = NSLock()
    private var seen = 0

    init(occurrence: Int, admitted: Latch) {
        self.occurrence = occurrence
        self.admitted = admitted
    }

    func admit() {
        lock.lock()
        seen += 1
        let isTheOne = seen == occurrence
        lock.unlock()
        guard isTheOne else { return }
        admitted.open()
    }
}
