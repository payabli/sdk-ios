import Foundation
import PayabliSDKCore

/// Which paypoint the running environment uses, and what to say when it has none.
///
/// Separate from `DemoConfiguration` so the demo's own test target can exercise
/// it: that type reads `Secrets`, which is gitignored and belongs to the app
/// target alone, and a lookup nobody can run against a map of their own is a
/// lookup nobody can check.
enum EntryPointLookup {
    /// A row present but blank is not a paypoint, so it reads as missing here
    /// rather than reaching the SDK as an empty identifier and coming back as a
    /// rejected credential, several screens from the line that holds the blank.
    static func entryPoint(
        from entryPoints: [PayabliEnvironment: String],
        for environment: PayabliEnvironment
    ) -> String? {
        guard let configured = entryPoints[environment] else { return nil }
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Names the environment that has no paypoint, and the ones that do, because
    /// the answer is almost always that the scheme and the map disagree.
    static func problem(
        from entryPoints: [PayabliEnvironment: String],
        for environment: PayabliEnvironment
    ) -> String? {
        guard entryPoint(from: entryPoints, for: environment) == nil else { return nil }
        let configured = entryPoints.keys
            .filter { entryPoint(from: entryPoints, for: $0) != nil }
            .map(name)
            .sorted()
            .joined(separator: ", ")
        return "No entry point for \(name(for: environment)) in Secrets.entryPoints"
            + (configured.isEmpty ? "." : ". Configured: \(configured).")
    }

    static func name(for environment: PayabliEnvironment) -> String {
        switch environment {
        case .qa: return "qa"
        case .sandbox: return "sandbox"
        case .production: return "production"
        default: return "other"
        }
    }
}
