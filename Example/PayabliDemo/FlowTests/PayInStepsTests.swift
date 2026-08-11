import XCTest

/// The two card-not-present sequences, over every combination they can be asked
/// for. Both entry points go through the whole space, since they share a
/// derivation.
final class PayInStepsTests: XCTestCase {
    private struct Entry {
        let name: String
        let build: (PayInProgress) -> PayInFlowSteps
    }

    private let entries = [
        Entry(name: "storing a method", build: PayInSteps.forStoringMethod),
        Entry(name: "capturing a payment", build: PayInSteps.forCapture)
    ]

    private let everyProgress: [PayInProgress] = {
        let checks: [TokenCheck] = [.notRun, .checking, .reachable, .unreachable]
        return checks.flatMap { check in
            [false, true].flatMap { hasResult in
                [false, true].flatMap { acknowledged in
                    [false, true].flatMap { submitting in
                        [false, true].map { failed in
                            PayInProgress(
                                tokenCheck: check,
                                hasResult: hasResult,
                                resultAcknowledged: acknowledged,
                                isSubmitting: submitting,
                                submitFailed: failed
                            )
                        }
                    }
                }
            }
        }
    }()

    /// Enough of the progress to name the case a failure came from.
    private func describe(_ entry: Entry, _ progress: PayInProgress) -> String {
        """
        \(entry.name): token \(progress.tokenCheck), \
        result \(progress.hasResult), acknowledged \(progress.resultAcknowledged), \
        submitting \(progress.isSubmitting), failed \(progress.submitFailed)
        """
    }

    private func each(_ body: (Entry, PayInProgress, PayInFlowSteps) -> Void) {
        for entry in entries {
            for progress in everyProgress {
                body(entry, progress, entry.build(progress))
            }
        }
    }

    func testTheSpaceIsTheSizeItClaims() {
        XCTAssertEqual(everyProgress.count, 4 * 2 * 2 * 2 * 2)
    }

    // MARK: - Invariants, over the whole space

    func testNoTwoStepsShowTheirControlsAtOnce() {
        each { entry, progress, steps in
            let showing = steps.all.filter(\.status.showsContent)
            XCTAssertLessThanOrEqual(
                showing.count, 1,
                "\(describe(entry, progress)) renders \(showing.map(\.title))"
            )
        }
    }

    func testNoTwoStepsAskForSomethingAtOnce() {
        each { entry, progress, steps in
            let actionable = steps.all.filter(\.status.isActionable)
            XCTAssertLessThanOrEqual(
                actionable.count, 1,
                "\(describe(entry, progress)) asks for \(actionable.map(\.title))"
            )
        }
    }

    func testAFailureIsNeverReportedByMoreThanOneStep() {
        each { entry, progress, steps in
            let failed = steps.all.filter { $0.status == .failed }
            XCTAssertLessThanOrEqual(
                failed.count, 1,
                "\(describe(entry, progress)) reports \(failed.count) failures"
            )
        }
    }

    func testEveryStepAfterAnUnfinishedOneIsBlocked() {
        each { entry, progress, steps in
            let all = steps.all
            guard let firstUnfinished = all.firstIndex(where: { !$0.status.isFinished }) else { return }
            for step in all.dropFirst(firstUnfinished + 1) {
                XCTAssertEqual(
                    step.status, .blocked,
                    "\(describe(entry, progress)) let \(step.title) run past \(all[firstUnfinished].title)"
                )
            }
        }
    }

    func testEveryStepSomeoneCanActOnShowsItsControls() {
        each { entry, progress, steps in
            for step in steps.all where step.status.isActionable {
                XCTAssertTrue(
                    step.status.showsContent,
                    "\(describe(entry, progress)): \(step.title) asks for something it does not show"
                )
            }
        }
    }

    func testAResultIsOfferedOnlyWhenEveryStepBeforeItHasFinished() {
        each { entry, progress, steps in
            guard steps.result.status.isActionable else { return }
            XCTAssertTrue(steps.backend.status.isFinished, "\(describe(entry, progress)) offered a result")
            XCTAssertTrue(steps.form.status.isFinished, "\(describe(entry, progress)) offered a result")
        }
    }

    func testEveryStepSaysWhatItIs() {
        each { entry, progress, steps in
            XCTAssertEqual(steps.all.count, 3, "\(describe(entry, progress))")
            for step in steps.all {
                XCTAssertFalse(step.title.isEmpty, "\(describe(entry, progress))")
                XCTAssertFalse(step.detail.isEmpty, "\(describe(entry, progress))")
            }
        }
    }

    // MARK: - The order, one point at a time

    func testAnUnprovenBackendKeepsTheSequenceOnTheProbe() {
        let steps = PayInSteps.forCapture(PayInProgress())
        XCTAssertEqual(steps.backend.status, .current)
        XCTAssertEqual(steps.form.status, .blocked)
        XCTAssertEqual(steps.result.status, .blocked)
    }

    func testAProbeInFlightIsTheAppWorkingNotThePerson() {
        let steps = PayInSteps.forCapture(PayInProgress(tokenCheck: .checking))
        XCTAssertEqual(steps.backend.status, .inProgress)
        XCTAssertFalse(steps.backend.status.isActionable)
    }

    func testAProvenBackendHandsTheSequenceToTheForm() {
        let steps = PayInSteps.forCapture(PayInProgress(tokenCheck: .reachable))
        XCTAssertEqual(steps.backend.status, .done)
        XCTAssertEqual(steps.form.status, .current)
    }

    func testASubmissionInFlightKeepsWhatTheFormIsHolding() {
        // A hidden row is a deallocated view model, so a decline would come back
        // to an empty form.
        let steps = PayInSteps.forCapture(PayInProgress(tokenCheck: .reachable, isSubmitting: true))
        XCTAssertEqual(steps.form.status, .inProgress)
        XCTAssertTrue(steps.form.status.showsContent)
        XCTAssertFalse(steps.form.status.isActionable)
    }

    func testAFailedSubmissionIsReportedByTheStepThatTookIt() {
        let steps = PayInSteps.forCapture(PayInProgress(tokenCheck: .reachable, submitFailed: true))
        XCTAssertEqual(steps.form.status, .failed)
        XCTAssertEqual(steps.result.status, .blocked)
    }

    func testAFinishedSubmissionHandsTheSequenceToItsResult() {
        let steps = PayInSteps.forCapture(PayInProgress(tokenCheck: .reachable, hasResult: true))
        XCTAssertEqual(steps.form.status, .done)
        XCTAssertEqual(steps.result.status, .current)
    }

    func testStartingOverHandsTheSequenceBackToTheForm() {
        let steps = PayInSteps.forCapture(
            PayInProgress(tokenCheck: .reachable, hasResult: true, resultAcknowledged: true)
        )
        XCTAssertEqual(steps.form.status, .current)
        XCTAssertEqual(steps.result.status, .blocked)
    }

    func testTheLatestProbeOutranksASubmissionThatSucceededEarlier() {
        let steps = PayInSteps.forCapture(PayInProgress(tokenCheck: .unreachable, hasResult: true))
        XCTAssertEqual(steps.backend.status, .failed)
        XCTAssertEqual(steps.form.status, .blocked)
        XCTAssertEqual(steps.result.status, .blocked)
    }

    func testASubmissionProvesTheBackendWhenNoProbeHasRun() {
        let steps = PayInSteps.forCapture(PayInProgress(tokenCheck: .notRun, hasResult: true))
        XCTAssertEqual(steps.backend.status, .done)
        XCTAssertEqual(steps.result.status, .current)
    }

    func testTheTwoEntryPointsDifferOnlyInWhatTheyCallTheirSteps() {
        let progress = PayInProgress(tokenCheck: .reachable, hasResult: true)
        let storing = PayInSteps.forStoringMethod(progress)
        let capturing = PayInSteps.forCapture(progress)

        XCTAssertEqual(storing.all.map(\.status), capturing.all.map(\.status))
        XCTAssertEqual(storing.backend.title, capturing.backend.title)
        XCTAssertNotEqual(storing.form.title, capturing.form.title)
        XCTAssertNotEqual(storing.result.title, capturing.result.title)
        XCTAssertNotEqual(storing.result.detail, capturing.result.detail)
    }
}
