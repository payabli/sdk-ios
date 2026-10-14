import PayabliSDKCore

/// The environments this build offers: the SDK's committed ones, then what this
/// machine's build added. The app reads `ExtraEnvironments` from a gitignored
/// file, and the flow tests supply their own.
enum OfferedEnvironments {
    static let sdk: [PayabliEnvironment] = PayabliEnvironment.entries + ExtraEnvironments.added

    static let demo: [DemoEnvironment] = sdk.map(DemoEnvironment.init)
}

extension DemoEnvironment {
    /// The SDK environment this one names.
    var sdkEnvironment: PayabliEnvironment {
        guard let environment = OfferedEnvironments.sdk.first(where: { $0.name == label }) else {
            preconditionFailure("\(label) is offered without an SDK environment")
        }
        return environment
    }
}
