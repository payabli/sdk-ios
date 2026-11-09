@import XCTest;
@import PayabliSDKPayIn;

/// What an Objective-C host compiles against to store a bank account: named values, whose numbers are fixed.
@interface PayabliPayInBankAccountCodesTests : XCTestCase
@end

@implementation PayabliPayInBankAccountCodesTests

- (void)testTheBankAccountValuesKeepTheirNumbers {
    XCTAssertEqual(PayabliPayInAccountTypeCodeChecking, 0);
    XCTAssertEqual(PayabliPayInAccountTypeCodeSavings, 1);

    XCTAssertEqual(PayabliPayInSecCodeCodeUnspecified, 0);
    XCTAssertEqual(PayabliPayInSecCodeCodePpd, 1);
    XCTAssertEqual(PayabliPayInSecCodeCodeWeb, 2);
    XCTAssertEqual(PayabliPayInSecCodeCodeTel, 3);
    XCTAssertEqual(PayabliPayInSecCodeCodeCcd, 4);
    XCTAssertEqual(PayabliPayInSecCodeCodeBoc, 5);

    XCTAssertEqual(PayabliPayInAccountHolderTypeCodeUnspecified, 0);
    XCTAssertEqual(PayabliPayInAccountHolderTypeCodePersonal, 1);
    XCTAssertEqual(PayabliPayInAccountHolderTypeCodeBusiness, 2);
}

- (void)testAHostBuildsABankAccountToStoreWithTheNamedValues {
    PayabliPayInStoreRequestObjC *request = [PayabliPayInStoreRequestObjC bankAccountWithAccountNumber:@"1111111111"
                                                                                         routingNumber:@"123456780"
                                                                                           accountType:PayabliPayInAccountTypeCodeChecking
                                                                                            holderName:@"Jane Doe"
                                                                                            holderType:PayabliPayInAccountHolderTypeCodeUnspecified
                                                                                               secCode:PayabliPayInSecCodeCodeUnspecified];
    XCTAssertNotNil(request);
}

- (void)testAHostBuildsABankAccountPaymentWithTheNamedValues {
    PayabliPayInRequestObjC *request = [PayabliPayInRequestObjC bankAccountWithAccountNumber:@"1111111111"
                                                                               routingNumber:@"123456780"
                                                                                 accountType:PayabliPayInAccountTypeCodeSavings
                                                                                  holderName:@"Jane Doe"
                                                                                  holderType:PayabliPayInAccountHolderTypeCodeBusiness
                                                                                     secCode:PayabliPayInSecCodeCodePpd
                                                                                 totalAmount:10];
    XCTAssertNotNil(request);
}

@end
