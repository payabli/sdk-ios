@import XCTest;
@import PayabliSDKCore;

/// What an Objective-C host compiles against: an `NSError` code compared with a named catalog code.
@interface PayabliErrorTypeCodeTests : XCTestCase
@end

@implementation PayabliErrorTypeCodeTests

- (void)testAnErrorCodeIsComparedAgainstANamedCase {
    NSError *error = [NSError errorWithDomain:@"com.payabli.ttp" code:3036 userInfo:nil];
    XCTAssertEqual(error.code, PayabliErrorTypeCodeContactlessDisabled);
}

- (void)testAHostSwitchesOnNamedCases {
    NSString *remedy;
    switch ((PayabliErrorTypeCode)1002) {
        case PayabliErrorTypeCodeTokenExpired:
            remedy = @"credential";
            break;
        case PayabliErrorTypeCodeDevicePendingActivation:
            remedy = @"activate";
            break;
        default:
            remedy = @"other";
            break;
    }
    XCTAssertEqualObjects(remedy, @"credential");
}

@end
