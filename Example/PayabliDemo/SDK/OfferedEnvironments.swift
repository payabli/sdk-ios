import PayabliSDKCore

/// The environments this build offers: the SDK's committed ones, then what this
/// machine's build added. The app target's alone, because `ExtraEnvironments`
/// is a gitignored file only that target lists.
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
