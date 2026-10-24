@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// The form's sensitive buffers: one registry per submission, closed on every exit that submission
/// can take.
final class PaymentMethodFormBufferTests: XCTestCase {
    /// The buffers the form builds for one submission are closed once that submission ends, whatever
    /// it ends in: the values live while the submission runs and are overwritten after it.
    @MainActor
    func testTheFormsCardBuffersCloseOnceTheSubmissionEnds() async throws {
        let viewModel = PayabliPayInViewModel(
            component: component(),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card, .bankAccount])
        )
        viewModel.selectedMethod = .card
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "02/27"
        viewModel.cardCvv = "999"
        viewModel.cardZip = "12345"

        var wipedWhileInside: [Bool] = []
        let input = try await viewModel.withFormBuffers { buffers -> PayabliPayInMethodInput in
            let method = viewModel.methodInput(with: buffers)
            guard case let .card(data) = method else {
                XCTFail("The card tab builds a card method")
                throw FormBufferTestError.submissionRefused
            }
            wipedWhileInside = [data.cardNumber.isWiped, data.securityCode.isWiped]
            return method
        }

        guard case let .card(data) = input else {
            XCTFail("The card tab builds a card method")
            return
        }
        XCTAssertEqual([false, false], wipedWhileInside, "The buffers live while the submission runs")
        XCTAssertTrue(data.cardNumber.isWiped)
        XCTAssertTrue(data.securityCode.isWiped)
        // The counts come from the fields the buffers were built from — the card number as the form
        // holds it, separators included — so discarded storage cannot pass as an overwrite.
        XCTAssertEqual(
            Array(repeating: SensitiveDigits.wipedByte, count: viewModel.cardNumber.utf8.count),
            data.cardNumber.rawCopy()
        )
        XCTAssertEqual(
            Array(repeating: SensitiveDigits.wipedByte, count: viewModel.cardCvv.utf8.count),
            data.securityCode.rawCopy()
        )
    }

    /// A submission that ends in a refusal closes them too: a retry builds its own buffers, and this
    /// one's are not held waiting for it.
    @MainActor
    func testTheFormsCardBuffersCloseWhenTheSubmissionThrows() async throws {
        let viewModel = PayabliPayInViewModel(
            component: component(),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card, .bankAccount])
        )
        viewModel.selectedMethod = .card
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "02/27"
        viewModel.cardCvv = "999"
        viewModel.cardZip = "12345"

        var held: [SensitiveDigits] = []
        do {
            _ = try await viewModel.withFormBuffers { buffers -> PayabliPayInMethodInput in
                let method = viewModel.methodInput(with: buffers)
                if case let .card(data) = method {
                    held = [data.cardNumber, data.securityCode]
                }
                throw FormBufferTestError.submissionRefused
            }
            XCTFail("The submission's refusal propagates")
        } catch is FormBufferTestError {
            // The close happens on the throw exit too, which is what is asserted below.
        }

        XCTAssertEqual(2, held.count)
        XCTAssertTrue(held.allSatisfy(\.isWiped))
        // The counts come from the fields the buffers were built from — the card number as the form
        // holds it, separators included — so discarded storage cannot pass as an overwrite.
        XCTAssertEqual(
            Array(repeating: SensitiveDigits.wipedByte, count: viewModel.cardNumber.utf8.count),
            held[0].rawCopy()
        )
        XCTAssertEqual(
            Array(repeating: SensitiveDigits.wipedByte, count: viewModel.cardCvv.utf8.count),
            held[1].rawCopy()
        )
    }

    /// The bank tab's account number is one of those buffers, closed by the same registry.
    @MainActor
    func testTheFormsAccountNumberClosesWithTheFormsBuffers() async throws {
        let viewModel = PayabliPayInViewModel(
            component: component(),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card, .bankAccount])
        )
        viewModel.selectedMethod = .bankAccount
        viewModel.accountHolder = "Jane Business"
        viewModel.routingNumber = "123456780"
        viewModel.accountNumber = "1111111111"

        var held: SensitiveDigits?
        _ = await viewModel.withFormBuffers { buffers -> PayabliPayInMethodInput in
            let method = viewModel.methodInput(with: buffers)
            if case let .bankAccount(data) = method {
                held = data.accountNumber
            }
            return method
        }

        let account = try XCTUnwrap(held)
        XCTAssertTrue(account.isWiped)
        // The count comes from the field the buffer was built from, so discarded storage cannot
        // pass as an overwrite.
        XCTAssertEqual(
            Array(repeating: SensitiveDigits.wipedByte, count: viewModel.accountNumber.utf8.count),
            account.rawCopy()
        )
    }

    @MainActor
    private func component() -> PayabliPayIn {
        flowOnSession(
            token: "access-token",
            entryPoint: "entry",
            environment: .sandbox
        )
    }
}

private enum FormBufferTestError: Error {
    case submissionRefused
}
