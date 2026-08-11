import PayabliSDKTapToPay
import XCTest

/// The Tap to Pay sequence, over every combination it can be asked for.
final class TapToPayStepsTests: XCTestCase {
    /// What the probe said, where the session is, and what activation did.
    private struct Combination: CustomStringConvertible {
        let tokenCheck: TokenCheck
        let session: PayabliTTPSessionState
        let outcome: TapToPayActivationOutcome

        var description: String {
            "token \(tokenCheck), session \(sessionName(session)), activation \(outcome)"
        }
    }

    private let everyCombination: [Combination] = {
        let checks: [TokenCheck] = [.notRun, .checking, .reachable, .unreachable]
        let outcomes: [TapToPayActivationOutcome] = [.none, .activationFailed, .enableFailed, .succeeded]
        return checks.flatMap { check in
            everyTapToPaySession.flatMap { session in
                outcomes.map { Combination(tokenCheck: check, session: session, outcome: $0) }
            }
        }
    }()

    private func steps(_ combination: Combination) -> TapToPayFlowSteps {
        TapToPaySteps.forCharging(
            tokenCheck: combination.tokenCheck,
            session: combination.session,
            activation: combination.outcome
        )
    }

    func testTheSpaceIsTheSizeItClaims() {
        XCTAssertEqual(everyCombination.count, 4 * 9 * 4)
    }

    // MARK: - Invariants, over the whole space

    func testNoTwoStepsShowTheirControlsAtOnce() {
        for combination in everyCombination {
            let showing = steps(combination).all.filter(\.status.showsContent)
            XCTAssertLessThanOrEqual(
                showing.count, 1,
                "\(combination) renders \(showing.map(\.title))"
            )
        }
    }

    func testNoTwoStepsAskForSomethingAtOnce() {
        for combination in everyCombination {
            let actionable = steps(combination).all.filter(\.status.isActionable)
            XCTAssertLessThanOrEqual(
                actionable.count, 1,
                "\(combination) asks for \(actionable.map(\.title))"
            )
        }
    }

    func testAFailureIsNeverReportedByMoreThanOneStep() {
        for combination in everyCombination {
            let failed = steps(combination).all.filter { $0.status == .failed }
            XCTAssertLessThanOrEqual(
                failed.count, 1,
                "\(combination) reports \(failed.count) failures: \(failed.map(\.title))"
            )
        }
    }

    func testEveryStepAfterAnUnfinishedOneIsBlocked() {
        for combination in everyCombination {
            let all = steps(combination).all
            guard let firstUnfinished = all.firstIndex(where: { !$0.status.isFinished }) else { continue }
            for step in all.dropFirst(firstUnfinished + 1) {
                XCTAssertEqual(
                    step.status, .blocked,
                    "\(combination) let \(step.title) run past \(all[firstUnfinished].title)"
                )
            }
        }
    }

    func testEveryStepSomeoneCanActOnShowsItsControls() {
        for combination in everyCombination {
            for step in steps(combination).all where step.status.isActionable {
                XCTAssertTrue(
                    step.status.showsContent,
                    "\(combination): \(step.title) asks for something it does not show"
                )
            }
        }
    }

    func testAChargeIsOfferedOnlyWhenEveryStepBeforeItHasFinished() {
        for combination in everyCombination {
            let sequence = steps(combination)
            guard sequence.charge.status.isActionable else { continue }
            XCTAssertTrue(sequence.token.status.isFinished, "\(combination) offered a charge")
            XCTAssertEqual(sequence.enable.status, .done, "\(combination) offered a charge")
            XCTAssertTrue(sequence.activation.status.isFinished, "\(combination) offered a charge")
            XCTAssertEqual(combination.session, .ready, "\(combination) offered a charge")
        }
    }

    func testTheActivationCodeIsOfferedOnlyWhereTheSDKAcceptsIt() {
        // `activateDevice` throws `.invalidState` for any session but
        // `.pendingActivation`.
        for combination in everyCombination
            where steps(combination).nextAction == .enterActivationCode
        {
            XCTAssertEqual(
                combination.session, .pendingActivation,
                "\(combination) offered the activation code"
            )
        }
    }

    func testAChargeIsOfferedOnlyByAReadyTerminal() {
        for combination in everyCombination where steps(combination).nextAction == .charge {
            XCTAssertEqual(combination.session, .ready, "\(combination) offered a charge")
        }
    }

    func testRecoveryWaitsForTheTokenStepLikeEverythingElse() {
        // Re-initialize re-runs config, which a backend known to be down cannot
        // answer, and offering it beside the probe's own retry is two next
        // actions again.
        for combination in everyCombination where steps(combination).nextAction == .reinitialize {
            let sequence = steps(combination)
            XCTAssertTrue(sequence.token.status.isFinished, "\(combination) offered Re-initialize")
            XCTAssertTrue(
                combination.session == .error || combination.session == .sessionExpired,
                "\(combination) offered Re-initialize"
            )
        }
    }

    func testAFailedProbeKeepsTheOnlyActionOnTheProbe() {
        for session in everyTapToPaySession {
            let sequence = TapToPaySteps.forCharging(
                tokenCheck: .unreachable, session: session, activation: .activationFailed
            )
            XCTAssertEqual(
                sequence.nextAction, .checkToken,
                "session \(sessionName(session)) moved past a failed probe"
            )
        }
    }

    func testAnEnableThatFailedAfterActivationKeepsItsOwnStep() {
        // Activation succeeded and the enable that follows it did not. `/config`
        // answering 403 again leaves the session `.pendingActivation`, and the
        // reason is written to the enable step, which says so: "see step 2".
        let sequence = TapToPaySteps.forCharging(
            tokenCheck: .reachable, session: .pendingActivation, activation: .enableFailed
        )
        XCTAssertEqual(sequence.enable.status, .failed)
        XCTAssertTrue(sequence.enable.status.showsContent)
        XCTAssertEqual(sequence.activation.status, .blocked)
        XCTAssertEqual(sequence.nextAction, .enableTerminal)
    }

    func testARecordedEnableFailureIsAnsweredByTheEnableStep() {
        for combination in everyCombination
            where combination.outcome == .enableFailed && steps(combination).token.status.isFinished
        {
            let sequence = steps(combination)
            guard sequence.enable.status.isFinished else { continue }
            XCTAssertNotEqual(
                combination.session, .pendingActivation,
                "\(combination) finished the enable step over a recorded enable failure"
            )
        }
    }

    func testEveryStepSaysWhatItIs() {
        for combination in everyCombination {
            let all = steps(combination).all
            XCTAssertEqual(all.count, 4, "\(combination)")
            for step in all {
                XCTAssertFalse(step.title.isEmpty, "\(combination)")
                XCTAssertFalse(step.detail.isEmpty, "\(combination)")
            }
        }
    }

    // MARK: - The order, one point at a time

    func testAnUnprovenBackendKeepsTheSequenceOnTheProbe() {
        let sequence = TapToPaySteps.forCharging(tokenCheck: .notRun, session: .idle, activation: .none)
        XCTAssertEqual(sequence.token.status, .current)
        XCTAssertEqual(sequence.enable.status, .blocked)
    }

    func testAProbeInFlightIsTheAppWorkingNotThePerson() {
        let sequence = TapToPaySteps.forCharging(tokenCheck: .checking, session: .idle, activation: .none)
        XCTAssertEqual(sequence.token.status, .inProgress)
        XCTAssertFalse(sequence.token.status.isActionable)
    }

    func testAProvenBackendHandsTheSequenceToTheTerminal() {
        let sequence = TapToPaySteps.forCharging(tokenCheck: .reachable, session: .idle, activation: .none)
        XCTAssertEqual(sequence.token.status, .done)
        XCTAssertEqual(sequence.enable.status, .current)
    }

    func testStartingTheTerminalIsTheAppWaitingNotThePerson() {
        for session in [PayabliTTPSessionState.attestingDevice, .fetchingConfig, .initializingReader, .reinitializing] {
            let sequence = TapToPaySteps.forCharging(tokenCheck: .reachable, session: session, activation: .none)
            XCTAssertEqual(sequence.enable.status, .inProgress, "\(sessionName(session))")
            XCTAssertFalse(sequence.enable.status.isActionable, "\(sessionName(session))")
        }
    }

    func testASessionThatStoppedKeepsTheStepThatCanStartItAgain() {
        for session in [PayabliTTPSessionState.error, .sessionExpired] {
            let sequence = TapToPaySteps.forCharging(tokenCheck: .reachable, session: session, activation: .none)
            XCTAssertEqual(sequence.enable.status, .failed, "\(sessionName(session))")
            XCTAssertTrue(sequence.enable.status.showsContent, "\(sessionName(session))")
        }
    }

    func testADeviceAwaitingRegistrationIsAskedForACodeAndCannotChargeYet() {
        let sequence = TapToPaySteps.forCharging(
            tokenCheck: .reachable, session: .pendingActivation, activation: .none
        )
        XCTAssertEqual(sequence.enable.status, .done)
        XCTAssertEqual(sequence.activation.status, .current)
        XCTAssertEqual(sequence.charge.status, .blocked)
    }

    func testARefusedActivationIsReportedByTheActivationStepWhenTheSessionRecordsTheError() {
        // `activateDevice` calls markError on failure, so the session reads
        // `.error` while the step that failed is activation. Blaming the enable
        // step for it blocks activation, which is where the reason and the retry
        // are rendered.
        let sequence = TapToPaySteps.forCharging(
            tokenCheck: .reachable, session: .error, activation: .activationFailed
        )
        XCTAssertEqual(sequence.enable.status, .done)
        XCTAssertEqual(sequence.activation.status, .failed)
        XCTAssertTrue(sequence.activation.status.showsContent)
        XCTAssertEqual(sequence.charge.status, .blocked)
        // The reason shows; Re-initialize is the way forward.
        XCTAssertEqual(sequence.nextAction, .reinitialize)
    }

    func testNoRecordedActivationFailureIsAnsweredByAnEarlierStep() {
        for combination in everyCombination
            where combination.outcome == .activationFailed && combination.session == .error
        {
            let sequence = steps(combination)
            // A probe that failed legitimately holds the whole sequence.
            guard sequence.token.status.isFinished else { continue }
            XCTAssertEqual(
                sequence.activation.status, .failed,
                "\(combination) answered an activation failure somewhere else"
            )
            XCTAssertTrue(sequence.activation.status.showsContent, "\(combination)")
        }
    }

    func testAnExpiredSessionIsStillTheEnableStepsFailure() {
        // Session expiry is not activation's doing, so a stale outcome must not
        // move that failure onto the step after it.
        let sequence = TapToPaySteps.forCharging(
            tokenCheck: .reachable, session: .sessionExpired, activation: .activationFailed
        )
        XCTAssertEqual(sequence.enable.status, .failed)
        XCTAssertEqual(sequence.activation.status, .blocked)
    }

    func testARefusedActivationKeepsItsOwnStepAndBlocksTheCharge() {
        let sequence = TapToPaySteps.forCharging(
            tokenCheck: .reachable, session: .pendingActivation, activation: .activationFailed
        )
        XCTAssertEqual(sequence.activation.status, .failed)
        XCTAssertTrue(sequence.activation.status.showsContent)
        XCTAssertEqual(sequence.charge.status, .blocked)
    }

    func testARecordedActivationFailureStaysQuietUntilTheSequenceReachesActivation() {
        let sequence = TapToPaySteps.forCharging(
            tokenCheck: .reachable, session: .idle, activation: .activationFailed
        )
        XCTAssertEqual(sequence.enable.status, .current)
        XCTAssertEqual(sequence.activation.status, .blocked)
    }

    func testAnActivationThatSucceededReadsAsDoneNotAsOneThatNeverApplied() {
        let sequence = TapToPaySteps.forCharging(
            tokenCheck: .reachable, session: .ready, activation: .succeeded
        )
        XCTAssertEqual(sequence.activation.status, .done)
    }

    func testATerminalThatNeverNeededActivationSaysSoRatherThanPretendingItIsDone() {
        let sequence = TapToPaySteps.forCharging(tokenCheck: .reachable, session: .ready, activation: .none)
        XCTAssertEqual(sequence.activation.status, .notNeeded)
        XCTAssertEqual(sequence.charge.status, .current)
    }

    func testAFailedProbeHoldsTheWholeSequenceEvenWithAReadyTerminal() {
        // Enable the terminal, then point the probe at a backend that is down.
        let sequence = TapToPaySteps.forCharging(
            tokenCheck: .unreachable, session: .ready, activation: .none
        )
        XCTAssertEqual(sequence.token.status, .failed)
        XCTAssertEqual(sequence.enable.status, .blocked)
        XCTAssertEqual(sequence.activation.status, .blocked)
        XCTAssertEqual(sequence.charge.status, .blocked)
    }

    func testTheActivationStepSaysWhereTheCodeComesFromOnlyWhenOneIsWanted() {
        let pending = TapToPaySteps.forCharging(
            tokenCheck: .reachable, session: .pendingActivation, activation: .none
        )
        let idle = TapToPaySteps.forCharging(tokenCheck: .reachable, session: .idle, activation: .none)
        XCTAssertTrue(pending.activation.detail.contains("Device Management"))
        XCTAssertNotEqual(idle.activation.detail, pending.activation.detail)
    }
}

/// `PayabliTTPSessionState` is `@objc`, so `String(describing:)` renders a raw
/// value rather than the case name, and a failure message has to name the state.
func sessionName(_ state: PayabliTTPSessionState) -> String {
    switch state {
    case .idle: return "idle"
    case .attestingDevice: return "attestingDevice"
    case .fetchingConfig: return "fetchingConfig"
    case .initializingReader: return "initializingReader"
    case .ready: return "ready"
    case .sessionExpired: return "sessionExpired"
    case .reinitializing: return "reinitializing"
    case .pendingActivation: return "pendingActivation"
    case .error: return "error"
    @unknown default: return "state(\(state.rawValue))"
    }
}
