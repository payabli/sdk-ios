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
