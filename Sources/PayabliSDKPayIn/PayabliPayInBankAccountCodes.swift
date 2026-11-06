import Foundation

/// ``PayabliPayInAccountType`` for Objective-C. Raw values are public API: do not reorder or renumber.
@objc public enum PayabliPayInAccountTypeCode: Int, Sendable, CaseIterable {
    case checking = 0
    case savings = 1

    var accountType: PayabliPayInAccountType {
        switch self {
        case .checking: .checking
        case .savings: .savings
        }
    }
}

/// ``PayabliPayInSecCode`` for Objective-C. Raw values are public API: do not reorder or renumber.
@objc public enum PayabliPayInSecCodeCode: Int, Sendable, CaseIterable {
    /// Not set: the SDK sends WEB.
    case unspecified = 0
    case ppd = 1
    case web = 2
    case tel = 3
    case ccd = 4
    case boc = 5

    var secCode: PayabliPayInSecCode? {
        switch self {
        case .unspecified: nil
        case .ppd: .ppd
        case .web: .web
        case .tel: .tel
        case .ccd: .ccd
        case .boc: .boc
        }
    }
}

/// ``PayabliPayInAccountHolderType`` for Objective-C. Raw values are public API: do not reorder or renumber.
@objc public enum PayabliPayInAccountHolderTypeCode: Int, Sendable, CaseIterable {
    /// Not set: the request leaves the holder type out, and the paypoint decides.
    case unspecified = 0
    case personal = 1
    case business = 2

    var holderType: PayabliPayInAccountHolderType? {
        switch self {
        case .unspecified: nil
        case .personal: .personal
        case .business: .business
        }
    }
}
