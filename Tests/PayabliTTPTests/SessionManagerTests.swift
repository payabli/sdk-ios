import XCTest
@testable import PayabliTTP

final class SessionManagerTests: XCTestCase {

    private var attester: MockDeviceAttester!
    private var http: MockNetworking!
    private var cardReader: MockCardReader!
    private var events: EventStream!
    private var sut: SessionManager!

    override func setUp() {
        super.setUp()
        attester = MockDeviceAttester(alreadyAttested: false)
        http = MockNetworking()
        cardReader = MockCardReader()
        events = EventStream()

        let attestationService = AttestationService(http: http)
        let transactionService = TransactionService(http: http)

        sut = SessionManager(
            attester: attester,
            attestationService: attestationService,
            transactionService: transactionService,
            cardReader: cardReader,
            deviceId: "test-device-id",
            events: events
        )
    }

    // MARK: - Happy path

    func testInitializeFullFlowNewDevice() async throws {
        // Queue mock responses: challenge → (attest void) → config
        http.responses = [
            TestFixtures.makeChallengeResponse(),
            TestFixtures.makeConfigResponse()
        ]

        try await sut.initialize()

        // Attestation phase
        XCTAssertTrue(attester.generateKeyCalled)
        XCTAssertTrue(attester.attestKeyCalled)
        XCTAssertTrue(attester.persistKeyIdCalled)

        // Config phase
        XCTAssertTrue(attester.generateAssertionCalled)
        XCTAssertNotNil(sut.currentConfig)
        XCTAssertEqual(sut.currentConfig?.requestToken, "mock-request-token")

        // Card reader phase
        XCTAssertTrue(cardReader.configureCalled)
        XCTAssertTrue(cardReader.requestSessionTokenCalled)
        XCTAssertTrue(cardReader.initializeSessionCalled)

        // Final state
        XCTAssertEqual(sut.state, .ready)
        XCTAssertTrue(sut.isReady)
    }

    func testInitializeSkipsAttestationIfAlreadyAttested() async throws {
        attester = MockDeviceAttester(alreadyAttested: true)

        let attestationService = AttestationService(http: http)
        let transactionService = TransactionService(http: http)

        sut = SessionManager(
            attester: attester,
            attestationService: attestationService,
            transactionService: transactionService,
            cardReader: cardReader,
            deviceId: "test-device-id",
            events: events
        )

        // Only need config response (no challenge needed)
        http.responses = [TestFixtures.makeConfigResponse()]

        try await sut.initialize()

        XCTAssertFalse(attester.generateKeyCalled, "Should skip key generation")
        XCTAssertFalse(attester.attestKeyCalled, "Should skip attestation")
        XCTAssertTrue(attester.generateAssertionCalled, "Should still generate assertion for config")
        XCTAssertEqual(sut.state, .ready)
    }

    func testInitializeLinksAccountIfNotLinked() async throws {
        attester = MockDeviceAttester(alreadyAttested: true)
        cardReader.isAccountLinkedResult = false

        let attestationService = AttestationService(http: http)
        let transactionService = TransactionService(http: http)

        sut = SessionManager(
            attester: attester,
            attestationService: attestationService,
            transactionService: transactionService,
            cardReader: cardReader,
            deviceId: "test-device-id",
            events: events
        )

        http.responses = [TestFixtures.makeConfigResponse()]

        try await sut.initialize()

        XCTAssertTrue(cardReader.linkAccountCalled)
    }

    // MARK: - Error handling

    func testInitializeFailsOnAttestationError() async {
        attester.shouldFailGeneration = true
        http.responses = [TestFixtures.makeChallengeResponse()]

        do {
            try await sut.initialize()
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is PayabliTTPError)
        }
    }

    func testInitializeFailsOnCardReaderSetup() async {
        attester = MockDeviceAttester(alreadyAttested: true)
        cardReader.shouldFailSetup = true

        let attestationService = AttestationService(http: http)
        let transactionService = TransactionService(http: http)

        sut = SessionManager(
            attester: attester,
            attestationService: attestationService,
            transactionService: transactionService,
            cardReader: cardReader,
            deviceId: "test-device-id",
            events: events
        )

        http.responses = [TestFixtures.makeConfigResponse()]

        do {
            try await sut.initialize()
            XCTFail("Should have thrown")
        } catch {
            XCTAssertFalse(sut.isReady)
        }
    }

    // MARK: - Reinitialize

    func testReinitializeWhenSessionActive() async throws {
        // First initialize
        attester = MockDeviceAttester(alreadyAttested: true)
        let attestationService = AttestationService(http: http)
        let transactionService = TransactionService(http: http)

        sut = SessionManager(
            attester: attester,
            attestationService: attestationService,
            transactionService: transactionService,
            cardReader: cardReader,
            deviceId: "test-device-id",
            events: events
        )

        http.responses = [TestFixtures.makeConfigResponse()]
        try await sut.initialize()

        // Card reader is active, so reinitialize should be a no-op
        let callsBefore = http.executeCalled
        try await sut.reinitializeIfNeeded()

        XCTAssertEqual(http.executeCalled, callsBefore, "Should not make new HTTP calls if session is active")
        XCTAssertEqual(sut.state, .ready)
    }

    func testReinitializeWhenSessionExpired() async throws {
        attester = MockDeviceAttester(alreadyAttested: true)
        let attestationService = AttestationService(http: http)
        let transactionService = TransactionService(http: http)

        sut = SessionManager(
            attester: attester,
            attestationService: attestationService,
            transactionService: transactionService,
            cardReader: cardReader,
            deviceId: "test-device-id",
            events: events
        )

        http.responses = [TestFixtures.makeConfigResponse()]
        try await sut.initialize()

        // Simulate session expiry
        cardReader.isSessionActive = false

        // Queue new config for reinit
        http.responses = [TestFixtures.makeConfigResponse()]

        try await sut.reinitializeIfNeeded()
        XCTAssertEqual(sut.state, .ready)
    }

    // MARK: - State machine

    func testStartsInIdleState() {
        XCTAssertEqual(sut.state, .idle)
        XCTAssertFalse(sut.isReady)
    }
}
