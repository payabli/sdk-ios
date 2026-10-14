import PayabliSDKCore

/// The environments this build offers: the SDK's committed ones, then what this
/// machine's build added. The app reads `ExtraEnvironments` from a gitignored
/// file, and the flow tests supply their own.
enum OfferedEnvironments {
    static let sdk: [PayabliEnvironment] = {
        let offered = PayabliEnvironment.entries + ExtraEnvironments.added
        let repeated = repeatedNames(in: offered)
        precondition(repeated.isEmpty, "more than one offered environment is named \(repeated)")
        return offered
    }()

    static let demo: [DemoEnvironment] = sdk.map(DemoEnvironment.init)

    /// The names more than one of `environments` carries, compared as a label
    /// is looked up, since a lookup by a shared name finds only the first.
    ///
    /// - Parameter environments: The environments a build would offer.
    /// - Returns: Each repeated name once, lowercased, in order of first repeat.
    static func repeatedNames(in environments: [PayabliEnvironment]) -> [String] {
        var seen: Set<String> = []
        var repeated: [String] = []
        for name in environments.map({ $0.name.lowercased() }) where !seen.insert(name).inserted {
            if !repeated.contains(name) {
                repeated.append(name)
            }
        }
        return repeated
    }
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
