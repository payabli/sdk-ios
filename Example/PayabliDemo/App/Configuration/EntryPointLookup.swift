import Foundation

/// Which paypoint the running environment uses, and what to say when it has none.
///
/// Separate from `DemoConfiguration` so the demo's own test target can exercise
/// it: that type reads `Secrets`, which is gitignored and belongs to the app
/// target alone, and a lookup nobody can run against a map of their own is a
/// lookup nobody can check.
///
/// The map is keyed by the environment's name, so the credentials file that
/// supplies it needs no type of this app's or the SDK's. That file is the one an
/// integrator copies and the one thing here that is not committed.
enum EntryPointLookup {
    /// A row present but blank is not a paypoint, so it reads as missing here
    /// rather than reaching the SDK as an empty identifier and coming back as a
    /// rejected credential, several screens from the line that holds the blank.
    static func entryPoint(
        from entryPoints: [String: String],
        for environment: DemoEnvironment
    ) -> String? {
        guard let configured = entryPoints[environment.label] else { return nil }
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Names the environment that has no paypoint, and the ones that do, because
    /// the answer is almost always that the scheme and the map disagree.
    static func problem(
        from entryPoints: [String: String],
        for environment: DemoEnvironment
    ) -> String? {
        guard entryPoint(from: entryPoints, for: environment) == nil else { return nil }
        let configured = entryPoints
            .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .keys
            .sorted()
            .joined(separator: ", ")
        return "No entry point for \(environment.label) in Secrets.entryPoints"
            + (configured.isEmpty ? "." : ". Configured: \(configured).")
    }
}
