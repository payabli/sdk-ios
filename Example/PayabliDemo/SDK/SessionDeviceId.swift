import PayabliSDKCore

/// This device's identity, read off the session.
enum SessionDeviceId {
    /// - Parameter session: the session the app started.
    /// - Returns: the session's `deviceId`, read off the main thread because it reads the keychain.
    static func read(_ session: PayabliSession) async -> String? {
        await Task.detached { session.deviceId }.value
    }
}
