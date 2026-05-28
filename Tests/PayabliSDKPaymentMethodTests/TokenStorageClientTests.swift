@testable import PayabliSDKCore
@testable import PayabliSDKPaymentMethod
import SwiftUI
import XCTest

final class TokenStorageClientTests: XCTestCase {
    func testAddMethodSerializesCardPaymentMethodRequest() async throws {
        let transport = MockTransport(responseBody: """
        {
          "responseText": "Success",
          "isSuccess": true,
          "responseData": {
            "referenceId": "stored-123",
            "resultCode": 1,
            "resultText": "Approved",
            "customerId": 4440,
            "methodReferenceId": "stored-123"
          }
        }
        """)
        let client = TokenStorageClient(
            transport: transport,
            accessTokenProvider: { "access-token-1" }
        )

        let result = try await client.addMethod(
            entryPoint: "f743aed24a",
            paymentMethod: .card(PayabliCardPaymentMethodData(
                cardNumber: "4111 1111 1111 1111",
                expiration: "02/25",
                cardholderName: "John Doe",
                cvv: "123",
                billingZip: "12345"
            )),
            options: PayabliPaymentMethodOptions(
                createAnonymous: true,
                forceCustomerCreation: false,
                temporary: true,
                idempotencyKey: "idem-1",
                customerData: PayabliPaymentMethodCustomerData(customerId: 4440),
                fallbackAuth: true,
                fallbackAuthAmount: 100,
                methodDescription: "Primary Visa card",
                source: "ios-sdk",
                subdomain: "checkout"
            )
        )

        assertCardPaymentMethodResult(result)
        try await assertCardPaymentMethodRequest(firstRequest(from: transport))
    }

    func testAddMethodSerializesAuthorizationHeaderOnly() async throws {
        let transport = MockTransport(responseBody: """
        {
          "responseText": "Success",
          "isSuccess": true,
          "responseData": {
            "referenceId": "stored-123",
            "resultCode": 1,
            "resultText": "Approved"
          }
        }
        """)
        let client = TokenStorageClient(
            transport: transport,
            accessTokenProvider: { "access-token-1" }
        )

        _ = try await client.addMethod(
            entryPoint: "f743aed24a",
            paymentMethod: .card(PayabliCardPaymentMethodData(
                cardNumber: "4111111111111111",
                expiration: "02/25",
                cardholderName: "John Doe",
                cvv: "123",
                billingZip: "12345"
            ))
        )

        let request = try await firstRequest(from: transport)
        XCTAssertEqual(request.headers["Authorization"], "Bearer access-token-1")
        XCTAssertEqual(Set(request.headers.keys), ["Authorization", "Content-Type"])
    }

    func testAddMethodSerializesACHPaymentMethodRequest() async throws {
        let transport = MockTransport(responseBody: """
        {
          "responseText": "Success",
          "isSuccess": true,
          "responseData": {
            "referenceId": "ach-123",
            "resultCode": 1,
            "resultText": "Approved",
            "customerId": 0,
            "methodReferenceId": "ach-123"
          }
        }
        """)
        let client = TokenStorageClient(
            transport: transport,
            accessTokenProvider: { "access-token-2" }
        )

        _ = try await client.addMethod(
            entryPoint: "f743aed24a",
            paymentMethod: .ach(PayabliACHPaymentMethodData(
                accountNumber: "1111111111111",
                accountType: .checking,
                holderName: "John Doe",
                routingNumber: "123456780",
                secCode: .web,
                holderType: .personal
            )),
            options: PayabliPaymentMethodOptions(
                achValidation: true,
                vendorData: PayabliPaymentMethodVendorData(vendorId: 7890)
            )
        )

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.query.map(\.name), ["achValidation"])
        XCTAssertEqual(request.query.first?.value, "true")

        let body = try parseBody(request)
        let vendor = try XCTUnwrap(body["vendorData"] as? [String: Any])
        XCTAssertEqual(vendor["vendorId"] as? Int, 7890)

        let paymentMethod = try XCTUnwrap(body["paymentMethod"] as? [String: Any])
        XCTAssertEqual(paymentMethod["method"] as? String, "ach")
        XCTAssertEqual(paymentMethod["achAccount"] as? String, "1111111111111")
        XCTAssertEqual(paymentMethod["achAccountType"] as? String, "Checking")
        XCTAssertEqual(paymentMethod["achCode"] as? String, "WEB")
        XCTAssertEqual(paymentMethod["achHolder"] as? String, "John Doe")
        XCTAssertEqual(paymentMethod["achHolderType"] as? String, "personal")
        XCTAssertEqual(paymentMethod["achRouting"] as? String, "123456780")
    }

    func testACHPaymentMethodDefaultsSecCodeToWeb() async throws {
        let transport = MockTransport(responseBody: """
        {
          "responseText": "Success",
          "isSuccess": true,
          "responseData": {
            "referenceId": "ach-default-sec",
            "resultCode": 1,
            "resultText": "Approved"
          }
        }
        """)
        let client = TokenStorageClient(
            transport: transport,
            accessTokenProvider: { "access-token-ach" }
        )

        _ = try await client.addMethod(
            entryPoint: "f743aed24a",
            paymentMethod: .ach(PayabliACHPaymentMethodData(
                accountNumber: "1111111111111",
                accountType: .checking,
                holderName: "John Doe",
                routingNumber: "123456780"
            ))
        )

        let request = try await firstRequest(from: transport)
        let body = try parseBody(request)
        let paymentMethod = try XCTUnwrap(body["paymentMethod"] as? [String: Any])
        XCTAssertEqual(paymentMethod["achCode"] as? String, "WEB")
    }

    func testInvalidCardDoesNotReachTransport() async throws {
        let transport = MockTransport(responseBody: "{}")
        let client = TokenStorageClient(
            transport: transport,
            accessTokenProvider: { "access-token" }
        )

        do {
            _ = try await client.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliCardPaymentMethodData(
                    cardNumber: "4111111111111112",
                    expiration: "02/25",
                    cardholderName: "John Doe",
                    billingZip: "12345"
                ))
            )
            XCTFail("Expected validation error")
        } catch PayabliPaymentMethodError.invalidInput {
            let requests = await transport.requests
            XCTAssertTrue(requests.isEmpty)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testMissingCardZipDoesNotReachTransport() async throws {
        let transport = MockTransport(responseBody: "{}")
        let client = TokenStorageClient(
            transport: transport,
            accessTokenProvider: { "access-token" }
        )

        do {
            _ = try await client.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliCardPaymentMethodData(
                    cardNumber: "4111111111111111",
                    expiration: "02/25",
                    cardholderName: "John Doe",
                    billingZip: ""
                ))
            )
            XCTFail("Expected validation error")
        } catch let PayabliPaymentMethodError.invalidInput(message) {
            XCTAssertEqual(message, "Card ZIP code is required.")
            let requests = await transport.requests
            XCTAssertTrue(requests.isEmpty)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testMissingCardCvvDoesNotReachTransport() async throws {
        let transport = MockTransport(responseBody: "{}")
        let client = TokenStorageClient(
            transport: transport,
            accessTokenProvider: { "access-token" }
        )

        do {
            _ = try await client.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliCardPaymentMethodData(
                    cardNumber: "4111111111111111",
                    expiration: "02/25",
                    cardholderName: "John Doe",
                    billingZip: "12345"
                ))
            )
            XCTFail("Expected validation error")
        } catch let PayabliPaymentMethodError.invalidInput(message) {
            XCTAssertEqual(message, "CVV is required.")
            let requests = await transport.requests
            XCTAssertTrue(requests.isEmpty)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testCardLengthLimitsDoNotReachTransport() async throws {
        let scenarios: [(PayabliCardPaymentMethodData, String)] = [
            (PayabliCardPaymentMethodData(
                cardNumber: String(repeating: "4", count: 20),
                expiration: "02/25",
                cardholderName: "John Doe",
                cvv: "123",
                billingZip: "12345"
            ), "Card number must be 12 to 19 digits."),
            (PayabliCardPaymentMethodData(
                cardNumber: "4111111111111111",
                expiration: "02/25",
                cardholderName: String(repeating: "A", count: 61),
                cvv: "123",
                billingZip: "12345"
            ), "Cardholder name must be 60 characters or fewer."),
            (PayabliCardPaymentMethodData(
                cardNumber: "4111111111111111",
                expiration: "02/25",
                cardholderName: "John Doe",
                cvv: "12345",
                billingZip: "12345"
            ), "CVV must be 3 or 4 digits."),
            (PayabliCardPaymentMethodData(
                cardNumber: "4111111111111111",
                expiration: "02/25",
                cardholderName: "John Doe",
                cvv: "123",
                billingZip: String(repeating: "A", count: 13)
            ), "Card ZIP code must be 12 characters or fewer.")
        ]

        for (paymentMethod, expectedMessage) in scenarios {
            let transport = MockTransport(responseBody: "{}")
            let client = TokenStorageClient(
                transport: transport,
                accessTokenProvider: { "access-token" }
            )

            do {
                _ = try await client.addMethod(
                    entryPoint: "entry",
                    paymentMethod: .card(paymentMethod)
                )
                XCTFail("Expected validation error")
            } catch let PayabliPaymentMethodError.invalidInput(message) {
                XCTAssertEqual(message, expectedMessage)
                let requests = await transport.requests
                XCTAssertTrue(requests.isEmpty)
            } catch {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    func testACHLengthLimitsDoNotReachTransport() async throws {
        let scenarios: [(PayabliACHPaymentMethodData, String)] = [
            (PayabliACHPaymentMethodData(
                accountNumber: String(repeating: "1", count: 18),
                accountType: .checking,
                holderName: "John Doe",
                routingNumber: "123456780"
            ), "ACH account number must be 4 to 17 digits."),
            (PayabliACHPaymentMethodData(
                accountNumber: "1111111111111",
                accountType: .checking,
                holderName: "John Doe",
                routingNumber: "1234567800"
            ), "ACH routing number must be 9 digits."),
            (PayabliACHPaymentMethodData(
                accountNumber: "1111111111111",
                accountType: .checking,
                holderName: String(repeating: "A", count: 61),
                routingNumber: "123456780"
            ), "ACH account holder must be 60 characters or fewer.")
        ]

        for (paymentMethod, expectedMessage) in scenarios {
            let transport = MockTransport(responseBody: "{}")
            let client = TokenStorageClient(
                transport: transport,
                accessTokenProvider: { "access-token" }
            )

            do {
                _ = try await client.addMethod(
                    entryPoint: "entry",
                    paymentMethod: .ach(paymentMethod)
                )
                XCTFail("Expected validation error")
            } catch let PayabliPaymentMethodError.invalidInput(message) {
                XCTAssertEqual(message, expectedMessage)
                let requests = await transport.requests
                XCTAssertTrue(requests.isEmpty)
            } catch {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    @MainActor
    func testViewModelInputLimitHelpers() {
        let component = PayabliPaymentMethod(
            accessToken: "access-token",
            entryPoint: "entry",
            environment: .sandbox,
            transport: MockTransport(responseBody: "{}")
        )
        let viewModel = PayabliPaymentMethodViewModel(component: component)

        XCTAssertEqual(viewModel.limitCardholderName(String(repeating: "A", count: 61)).count, 60)
        XCTAssertEqual(viewModel.formatCardNumber(String(repeating: "4", count: 25)).digitsOnly.count, 19)
        XCTAssertEqual(viewModel.limitCardCvv("12345"), "1234")
        XCTAssertEqual(viewModel.limitPostalCode("A1A 1A1-EXTRA").count, 12)
        XCTAssertEqual(viewModel.limitACHHolderName(String(repeating: "A", count: 61)).count, 60)
        XCTAssertEqual(viewModel.limitACHRouting("1234567890"), "123456789")
        XCTAssertEqual(viewModel.limitACHAccount(String(repeating: "1", count: 20)).count, 17)
    }

    func testDetectsCardBrandFromCardNumberPrefix() {
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: "4111 1111 1111 1111"), .visa)
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: "5555 5555 5555 4444"), .mastercard)
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: "378282246310005"), .americanExpress)
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: "6011111111111117"), .discover)
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: "30569309025904"), .dinersClub)
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: "3530111333300000"), .jcb)
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: "6200000000000005"), .unionPay)
        XCTAssertEqual(PayabliPaymentMethodCardBrand.detect(cardNumber: ""), .unknown)
    }

    func testCardBrandAssetNamesUsePayabliCatalogNames() {
        XCTAssertEqual(PayabliPaymentMethodCardBrand.visa.brandAssetName, "brand-visa")
        XCTAssertEqual(PayabliPaymentMethodCardBrand.mastercard.brandAssetName, "brand-mastercard")
        XCTAssertEqual(PayabliPaymentMethodCardBrand.americanExpress.brandAssetName, "brand-amex")
        XCTAssertEqual(PayabliPaymentMethodCardBrand.discover.brandAssetName, "brand-discover")
        XCTAssertNil(PayabliPaymentMethodCardBrand.unknown.brandAssetName)
        XCTAssertNil(PayabliPaymentMethodCardBrand.jcb.brandAssetName)
    }

    func testCardBrandIconPlacementIsConfigurable() {
        let configuration = PayabliPaymentMethodFormConfiguration(cardBrandIconPlacement: .leading)

        XCTAssertEqual(configuration.cardBrandIconPlacement, .leading)
    }

    func testErrorMessagePlacementIsConfigurable() {
        XCTAssertEqual(PayabliPaymentMethodFormConfiguration().errorMessagePlacement, .aboveSubmitButton)

        let configuration = PayabliPaymentMethodFormConfiguration(errorMessagePlacement: .top)

        XCTAssertEqual(configuration.errorMessagePlacement, .top)
    }

    func testPaymentMethodLabelsDefaultSubmitButtonText() {
        XCTAssertEqual(PayabliPaymentMethodLabels().submitButton, "Add Payment Method")
    }

    func testSheetConfigurationDefaultsToSdkOwnedPresentation() {
        let configuration = PayabliPaymentMethodSheetConfiguration()

        XCTAssertEqual(configuration.dismissButton, .close)
        XCTAssertTrue(configuration.dismissesOnSuccess)
        XCTAssertTrue(configuration.movesFormHeaderToSheetHeader)
        XCTAssertTrue(configuration.sizesToContentWhenPossible)
        XCTAssertTrue(configuration.expandsToLargeWhenContentDoesNotFit)
        XCTAssertFalse(configuration.detents.isEmpty)
    }

    func testSheetConfigurationUsesLargeDetentWhenGivenEmptySet() {
        let configuration = PayabliPaymentMethodSheetConfiguration(detents: Set<PresentationDetent>())

        XCTAssertEqual(configuration.detents, [.large])
    }

    func testDiagnosticsLogRedactedRequestAndResponse() async throws {
        let sink = DiagnosticSink()
        let transport = MockTransport(responseBody: """
        {
          "responseText": "Success",
          "isSuccess": true,
          "responseData": {
            "referenceId": "stored-secret-123",
            "resultCode": 1,
            "resultText": "Added",
            "customerId": 4440,
            "methodReferenceId": "method-secret-123"
          }
        }
        """)
        let client = TokenStorageClient(
            transport: transport,
            accessTokenProvider: { "access-token-secret" },
            baseURL: URL(string: "https://api-qa.payabli.com"),
            diagnostics: .enabled { sink.append($0) }
        )

        _ = try await client.addMethod(
            entryPoint: "f743aed24a",
            paymentMethod: .card(PayabliCardPaymentMethodData(
                cardNumber: "4111111111111111",
                expiration: "02/25",
                cardholderName: "Jane Doe",
                cvv: "123",
                billingZip: "33139"
            )),
            options: PayabliPaymentMethodOptions(
                createAnonymous: false,
                forceCustomerCreation: true,
                temporary: false,
                customerData: PayabliPaymentMethodCustomerData(
                    billingEmail: "jane@example.com",
                    customerNumber: "cust-secret"
                ),
                source: "ios-sdk"
            )
        )

        let entries = sink.entries()
        XCTAssertEqual(entries.map(\.phase), [.request, .response])

        let request = try XCTUnwrap(entries.first)
        XCTAssertTrue(request.url.contains("https://api-qa.payabli.com/api/TokenStorage/add"))
        XCTAssertTrue(request.url.contains("createAnonymous=false"))
        XCTAssertTrue(request.url.contains("forceCustomerCreation=true"))
        XCTAssertTrue(request.url.contains("temporary=false"))
        XCTAssertEqual(request.headers["Authorization"], "[REDACTED]")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        let requestBody = try XCTUnwrap(request.body)
        XCTAssertTrue(requestBody.contains("\"entryPoint\":\"f743aed24a\""))
        XCTAssertTrue(requestBody.contains("\"source\":\"ios-sdk\""))
        XCTAssertFalse(requestBody.contains("4111111111111111"))
        XCTAssertFalse(requestBody.contains("Jane Doe"))
        XCTAssertFalse(requestBody.contains("123"))
        XCTAssertFalse(requestBody.contains("jane@example.com"))
        XCTAssertFalse(requestBody.contains("cust-secret"))

        let response = try XCTUnwrap(entries.last)
        XCTAssertEqual(response.statusCode, 200)
        let responseBody = try XCTUnwrap(response.body)
        XCTAssertTrue(responseBody.contains("\"resultCode\":1"))
        XCTAssertTrue(responseBody.contains("\"resultText\":\"Added\""))
        XCTAssertFalse(responseBody.contains("stored-secret-123"))
        XCTAssertFalse(responseBody.contains("method-secret-123"))
        XCTAssertFalse(responseBody.contains("4440"))
    }

    func testDeclinedPaymentMethodThrowsDomainError() async throws {
        let transport = MockTransport(responseBody: """
        {
          "responseText": "Declined",
          "isSuccess": false,
          "responseData": {
            "resultCode": 2,
            "resultText": "Account validation failed"
          }
        }
        """)
        let client = TokenStorageClient(
            transport: transport,
            accessTokenProvider: { "access-token" }
        )

        do {
            _ = try await client.addMethod(
                entryPoint: "entry",
                paymentMethod: .ach(PayabliACHPaymentMethodData(
                    accountNumber: "1111111111111",
                    accountType: .checking,
                    holderName: "John Doe",
                    routingNumber: "123456780"
                ))
            )
            XCTFail("Expected payment method failure")
        } catch let PayabliPaymentMethodError.saveFailed(failure) {
            XCTAssertEqual(failure.responseText, "Declined")
            XCTAssertEqual(failure.resultCode, 2)
            XCTAssertEqual(failure.resultText, "Account validation failed")
            XCTAssertEqual(failure.reason, "Account validation failed")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testBadRequestPaymentMethodEnvelopeThrowsPaymentMethodFailure() async throws {
        let transport = MockTransport(statusCode: 400, responseBody: """
        {
          "isSuccess": false,
          "responseText": "Error",
          "responseCode": 6000,
          "responseData": {
            "explanation": "Invalid Card",
            "todoAction": "Please check your card details and try again."
          }
        }
        """)
        let client = TokenStorageClient(
            transport: transport,
            accessTokenProvider: { "access-token" }
        )

        do {
            _ = try await client.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliCardPaymentMethodData(
                    cardNumber: "4111111111111111",
                    expiration: "02/28",
                    cardholderName: "Jane Doe",
                    cvv: "123",
                    billingZip: "33139"
                ))
            )
            XCTFail("Expected payment method failure")
        } catch let PayabliPaymentMethodError.saveFailed(failure) {
            XCTAssertEqual(failure.httpStatusCode, 400)
            XCTAssertEqual(failure.responseText, "Error")
            XCTAssertEqual(failure.responseCode, 6000)
            XCTAssertEqual(failure.explanation, "Invalid Card")
            XCTAssertEqual(failure.todoAction, "Please check your card details and try again.")
            XCTAssertEqual(failure.reason, "Invalid Card")
            XCTAssertEqual(failure.detail, "Please check your card details and try again.")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testServerErrorPaymentMethodEnvelopeUsesSafeMessage() async throws {
        let transport = MockTransport(statusCode: 500, responseBody: """
        {
          "isSuccess": false,
          "responseText": "Error"
        }
        """)
        let client = TokenStorageClient(
            transport: transport,
            accessTokenProvider: { "access-token" }
        )

        do {
            _ = try await client.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliCardPaymentMethodData(
                    cardNumber: "4111111111111111",
                    expiration: "02/28",
                    cardholderName: "Jane Doe",
                    cvv: "123",
                    billingZip: "33139"
                ))
            )
            XCTFail("Expected payment method failure")
        } catch let PayabliPaymentMethodError.saveFailed(failure) {
            XCTAssertEqual(failure.httpStatusCode, 500)
            XCTAssertEqual(failure.responseText, "Error")
            XCTAssertEqual(failure.reason, "Unable to save payment method right now. Please try again.")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    @MainActor
    func testFormConfigurationSubmitsRequiredCardFieldsAndHiddenOptionalFields() async throws {
        let transport = MockTransport(responseBody: """
        {
          "responseText": "Success",
          "isSuccess": true,
          "responseData": {
            "referenceId": "stored-hidden",
            "resultCode": 1,
            "resultText": "Approved",
            "customerId": 888,
            "methodReferenceId": "stored-hidden"
          }
        }
        """)
        let component = PayabliPaymentMethod(
            accessToken: "access-token-hidden",
            entryPoint: "entry-hidden",
            environment: .sandbox,
            transport: transport
        )
        let viewModel = PayabliPaymentMethodViewModel(
            component: component,
            configuration: PayabliPaymentMethodFormConfiguration(
                allowedMethods: [.card],
                cardFieldOrder: [.cardNumber, .cardExpiration, .cardholderName],
                hiddenValues: PayabliPaymentMethodHiddenValues(
                    methodDescription: "Hidden primary card",
                    customerData: PayabliPaymentMethodCustomerData(
                        billingEmail: "hidden@example.com",
                        customerNumber: "cust-hidden"
                    )
                )
            )
        )
        viewModel.cardNumber = "4111 1111 1111 1111"
        viewModel.cardExpiration = "02/25"
        viewModel.cardholderName = "Jane Doe"
        XCTAssertFalse(viewModel.canSubmit)
        viewModel.cardCvv = "321"
        XCTAssertFalse(viewModel.canSubmit)
        viewModel.cardZip = "33139"
        XCTAssertTrue(viewModel.activeFields.contains(.cardCvv))
        XCTAssertTrue(viewModel.activeFields.contains(.cardZip))
        XCTAssertTrue(viewModel.canSubmit)

        let result = try await viewModel.submit()

        XCTAssertEqual(result.storedMethodId, "stored-hidden")

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        let body = try parseBody(request)
        XCTAssertEqual(body["methodDescription"] as? String, "Hidden primary card")

        let customer = try XCTUnwrap(body["customerData"] as? [String: Any])
        XCTAssertEqual(customer["customerNumber"] as? String, "cust-hidden")
        XCTAssertEqual(customer["billingEmail"] as? String, "hidden@example.com")

        let paymentMethod = try XCTUnwrap(body["paymentMethod"] as? [String: Any])
        XCTAssertEqual(paymentMethod["cardcvv"] as? String, "321")
        XCTAssertEqual(paymentMethod["cardzip"] as? String, "33139")
    }

    @MainActor
    func testFormConfigurationCanRequireOptionalFields() async throws {
        let transport = MockTransport(responseBody: """
        {
          "responseText": "Success",
          "isSuccess": true,
          "responseData": {
            "referenceId": "stored-required",
            "resultCode": 1,
            "resultText": "Approved",
            "methodReferenceId": "stored-required"
          }
        }
        """)
        let component = PayabliPaymentMethod(
            accessToken: "access-token-required",
            entryPoint: "entry-required",
            environment: .sandbox,
            transport: transport
        )
        let viewModel = PayabliPaymentMethodViewModel(
            component: component,
            configuration: PayabliPaymentMethodFormConfiguration(
                allowedMethods: [.card],
                cardFieldOrder: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip],
                requiredFields: [.billingEmail, .methodDescription]
            )
        )

        XCTAssertTrue(viewModel.activeFields.contains(.billingEmail))
        XCTAssertTrue(viewModel.activeFields.contains(.methodDescription))

        viewModel.cardholderName = "Jane Doe"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "02/28"
        viewModel.cardCvv = "123"
        viewModel.cardZip = "33139"
        XCTAssertFalse(viewModel.canSubmit)

        viewModel.billingEmail = "jane@example.com"
        XCTAssertFalse(viewModel.canSubmit)

        viewModel.methodDescription = "Primary card"
        XCTAssertTrue(viewModel.canSubmit)

        _ = try await viewModel.submit()

        let request = try await firstRequest(from: transport)
        let body = try parseBody(request)
        XCTAssertEqual(body["methodDescription"] as? String, "Primary card")
        let customer = try XCTUnwrap(body["customerData"] as? [String: Any])
        XCTAssertEqual(customer["billingEmail"] as? String, "jane@example.com")
    }

    @MainActor
    func testACHSecCodeIsHiddenAndSubmittedFromHiddenValues() async throws {
        let transport = MockTransport(responseBody: """
        {
          "responseText": "Success",
          "isSuccess": true,
          "responseData": {
            "referenceId": "ach-hidden-sec",
            "resultCode": 1,
            "resultText": "Approved",
            "methodReferenceId": "ach-hidden-sec"
          }
        }
        """)
        let component = PayabliPaymentMethod(
            accessToken: "access-token-ach-hidden",
            entryPoint: "entry-ach-hidden",
            environment: .sandbox,
            transport: transport
        )
        let viewModel = PayabliPaymentMethodViewModel(
            component: component,
            configuration: PayabliPaymentMethodFormConfiguration(
                allowedMethods: [.ach],
                defaultMethod: .ach,
                achFieldOrder: [.achHolder, .achRouting, .achAccount, .achAccountType, .achSecCode],
                hiddenValues: PayabliPaymentMethodHiddenValues(
                    achHolderType: .business,
                    achSecCode: .ccd
                )
            )
        )

        XCTAssertFalse(viewModel.activeFields.contains(PayabliPaymentMethodField.achSecCode))

        viewModel.achHolder = "Jane Business"
        viewModel.achRouting = "123456780"
        viewModel.achAccount = "1111111111111"
        XCTAssertTrue(viewModel.canSubmit)

        let result = try await viewModel.submit()
        XCTAssertEqual(result.storedMethodId, "ach-hidden-sec")

        let request = try await firstRequest(from: transport)
        let body = try parseBody(request)
        let paymentMethod = try XCTUnwrap(body["paymentMethod"] as? [String: Any])
        XCTAssertEqual(paymentMethod["achCode"] as? String, "CCD")
        XCTAssertEqual(paymentMethod["achHolderType"] as? String, "business")
    }

    @MainActor
    func testViewModelShowsPaymentMethodFailureActionAndKeepsEditableFields() async throws {
        let transport = MockTransport(statusCode: 400, responseBody: """
        {
          "isSuccess": false,
          "responseText": "Error",
          "responseCode": 6000,
          "responseData": {
            "explanation": "Invalid Card",
            "todoAction": "Please check your card details and try again."
          }
        }
        """)
        let viewModel = PayabliPaymentMethodViewModel(
            component: PayabliPaymentMethod(
                accessToken: "access-token",
                entryPoint: "entry",
                environment: .sandbox,
                transport: transport
            ),
            configuration: PayabliPaymentMethodFormConfiguration(allowedMethods: [.card])
        )
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "02/28"
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardCvv = "123"
        viewModel.cardZip = "33139"

        do {
            _ = try await viewModel.submit()
            XCTFail("Expected payment method failure")
        } catch let PayabliPaymentMethodError.saveFailed(failure) {
            XCTAssertEqual(failure.responseCode, 6000)
            XCTAssertEqual(viewModel.errorMessage, "Invalid Card\nPlease check your card details and try again.")
            XCTAssertEqual(viewModel.cardNumber, "4111111111111111")
            XCTAssertEqual(viewModel.cardExpiration, "02/28")
            XCTAssertEqual(viewModel.cardholderName, "Jane Doe")
            XCTAssertEqual(viewModel.cardZip, "33139")
            XCTAssertEqual(viewModel.cardCvv, "")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    @MainActor
    func testViewModelReportsInvalidCardNumberAsUserTypes() {
        let viewModel = PayabliPaymentMethodViewModel(
            component: PayabliPaymentMethod(
                accessToken: "access-token",
                entryPoint: "entry",
                environment: .sandbox,
                transport: MockTransport(responseBody: "{}")
            ),
            configuration: PayabliPaymentMethodFormConfiguration(allowedMethods: [.card])
        )

        viewModel.cardNumber = "4111 1111"
        XCTAssertNil(viewModel.cardNumberValidationMessage)

        viewModel.cardNumber = "4111 1111 1111 1112"
        XCTAssertEqual(viewModel.cardNumberValidationMessage, "Invalid Card Number")

        viewModel.cardholderName = "Jane Doe"
        viewModel.cardExpiration = "02/28"
        viewModel.cardCvv = "123"
        viewModel.cardZip = "33139"
        XCTAssertFalse(viewModel.canSubmit)

        viewModel.cardNumber = "4111 1111 1111 1111"
        XCTAssertNil(viewModel.cardNumberValidationMessage)
        XCTAssertTrue(viewModel.canSubmit)
    }

    @MainActor
    func testViewModelBuildsExpirationFromMonthYearSelection() {
        let viewModel = PayabliPaymentMethodViewModel(
            component: PayabliPaymentMethod(
                accessToken: "access-token",
                entryPoint: "entry",
                environment: .sandbox,
                transport: MockTransport(responseBody: "{}")
            ),
            configuration: PayabliPaymentMethodFormConfiguration(allowedMethods: [.card])
        )

        XCTAssertEqual(viewModel.expirationDisplayText, "MM/YY")

        viewModel.selectExpirationMonth(2)
        XCTAssertEqual(viewModel.expirationDisplayText, "02/YY")
        XCTAssertEqual(viewModel.cardExpiration, "")

        viewModel.selectExpirationYear(2028)
        XCTAssertEqual(viewModel.expirationDisplayText, "02/28")
        XCTAssertEqual(viewModel.cardExpiration, "02/28")
    }
}

private func parseBody(_ request: PayabliRequest) throws -> [String: Any] {
    let body = try XCTUnwrap(request.body)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func firstRequest(from transport: MockTransport) async throws -> PayabliRequest {
    let requests = await transport.requests
    return try XCTUnwrap(requests.first)
}

private func assertCardPaymentMethodResult(_ result: PayabliStoredPaymentMethod) {
    XCTAssertEqual(result.storedMethodId, "stored-123")
    XCTAssertEqual(result.apiResponse.isSuccess, true)
    XCTAssertEqual(result.apiResponse.responseText, "Success")
    XCTAssertEqual(result.apiResponse.responseData?.referenceId, "stored-123")
    XCTAssertEqual(result.apiResponse.responseData?.customerId, 4440)
}

private func assertCardPaymentMethodRequest(_ request: PayabliRequest) throws {
    XCTAssertEqual(request.method, .post)
    XCTAssertEqual(request.path, "/api/TokenStorage/add")
    XCTAssertEqual(request.headers["Authorization"], "Bearer access-token-1")
    XCTAssertEqual(request.headers["idempotencyKey"], "idem-1")
    XCTAssertEqual(request.headers["Content-Type"], "application/json")
    XCTAssertEqual(Set(request.headers.keys), ["Authorization", "Content-Type", "idempotencyKey"])
    XCTAssertEqual(
        request.query.map { "\($0.name)=\($0.value ?? "")" }.sorted(),
        ["createAnonymous=true", "forceCustomerCreation=false", "temporary=true"]
    )

    let body = try parseBody(request)
    XCTAssertEqual(body["entryPoint"] as? String, "f743aed24a")
    XCTAssertEqual(body["fallbackAuth"] as? Bool, true)
    XCTAssertEqual(body["fallbackAuthAmount"] as? Int, 100)
    XCTAssertEqual(body["methodDescription"] as? String, "Primary Visa card")
    XCTAssertEqual(body["source"] as? String, "ios-sdk")
    XCTAssertEqual(body["subdomain"] as? String, "checkout")

    let customer = try XCTUnwrap(body["customerData"] as? [String: Any])
    XCTAssertEqual(customer["customerId"] as? Int, 4440)

    let paymentMethod = try XCTUnwrap(body["paymentMethod"] as? [String: Any])
    XCTAssertEqual(paymentMethod["method"] as? String, "card")
    XCTAssertEqual(paymentMethod["cardnumber"] as? String, "4111111111111111")
    XCTAssertEqual(paymentMethod["cardexp"] as? String, "02/25")
    XCTAssertEqual(paymentMethod["cardHolder"] as? String, "John Doe")
    XCTAssertEqual(paymentMethod["cardcvv"] as? String, "123")
    XCTAssertEqual(paymentMethod["cardzip"] as? String, "12345")
}

private actor MockTransport: PayabliTransport {
    private let statusCode: Int
    private let responseBody: String
    private(set) var requests: [PayabliRequest] = []

    init(statusCode: Int = 200, responseBody: String) {
        self.statusCode = statusCode
        self.responseBody = responseBody
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        requests.append(request)
        return PayabliResponse(
            statusCode: statusCode,
            headers: [:],
            body: Data(responseBody.utf8)
        )
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        throw PayabliGenericError(code: .unknown, reason: "performV2 is not used")
    }
}

private final class DiagnosticSink: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [PayabliPaymentMethodDiagnosticEntry] = []

    func append(_ entry: PayabliPaymentMethodDiagnosticEntry) {
        lock.lock()
        defer { lock.unlock() }
        captured.append(entry)
    }

    func entries() -> [PayabliPaymentMethodDiagnosticEntry] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }
}
