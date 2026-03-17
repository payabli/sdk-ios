import Foundation

public struct CustomerData: Sendable {
    public let firstName: String?
    public let lastName: String?

    public init(firstName: String? = nil, lastName: String? = nil) {
        self.firstName = firstName
        self.lastName = lastName
    }
}
