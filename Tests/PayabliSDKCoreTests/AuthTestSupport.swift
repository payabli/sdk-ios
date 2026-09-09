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
        sink = HoldingLogSink(holdingOn: "Access token refreshed", entered: committing)
    }
}

/// A holder whose provider mints once per rejection and holds the first two where the case needs
/// them. A third call is the failure the case is looking for, so it names itself and returns.
func makeRacingAuth(_ race: RefreshRace) throws -> PayabliAuth {
    PayabliAuth(
        config: try PayabliConfig(
            accessToken: "first",
            tokenProvider: {
                switch await race.calls.increment() {
                case 1:
                    race.firstProvider.set("entered")
                    await race.releaseFirst.wait()
                    return "second"
                case 2:
                    race.secondProvider.set("entered")
                    await race.releaseSecond.wait()
                    return "third"
                default:
                    race.thirdProvider.set("entered")
                    return "fourth"
                }
            },
            entryPoint: "test_entry",
            environment: .sandbox
        ),
        logger: PayabliLogger(category: .auth, sink: race.sink)
    )
}
