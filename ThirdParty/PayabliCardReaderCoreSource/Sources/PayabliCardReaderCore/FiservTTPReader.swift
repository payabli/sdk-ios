//  FiservTTP
//
//  Copyright (c) 2022 - 2025 Fiserv, Inc.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation
import ProximityReader

internal class FiservTTPReader {
    
    private var paymentCardReader: PaymentCardReader?
    
    private var cardReaderSession: PaymentCardReaderSession?
    
    private let config: FiservTTPConfig

    /// The subscription to the reader's event stream.
    ///
    /// Held so `finalize()` can end it. Apple's `events` is one `AsyncStream`
    /// per reader and a second iteration of it would take events away from the
    /// first, so an abandoned task is not merely idle.
    private var eventTask: Task<Void, Never>?
    
    internal init(config: FiservTTPConfig) {
        
        self.config = config
        
        self.paymentCardReader = PaymentCardReader()
    }
    
    deinit {
        // Releasing a task does not cancel it. Without this the subscription
        // outlives the reader, holding the platform's stream open and calling a
        // handler for a session that is gone. `finalize()` is not called on
        // every path that drops a reader.
        eventTask?.cancel()
    }

    internal func finalize() {
        eventTask?.cancel()
        eventTask = nil
        paymentCardReader = nil
        cardReaderSession = nil
    }
    
    internal func readerIdentifier() async throws -> String? {
        
        let title = "Reader Identifier"
        
        if let cardReader = self.paymentCardReader {
            
            do {
                return try await cardReader.readerIdentifier
            } catch {
                throw FiservTTPCardReaderError(title: title,
                                               localizedDescription: NSLocalizedString("Payment Card Reader not identified.", comment: ""))
            }
        }
        
        return nil
    }
    
    internal func readerIsSupported() -> Bool {
        
        return PaymentCardReader.isSupported
    }
    
    @available(iOS 16.4, *)
    internal func isAccountLinked(token: String) async throws -> Bool {
        
        let title = "Is Account Linked"
        
        guard let cardReader = self.paymentCardReader else {
            
            throw FiservTTPCardReaderError(title: title,
                                           localizedDescription: NSLocalizedString("Payment Card Reader not available.", comment: ""))
        }
        
        let token = PaymentCardReader.Token(rawValue: token)
        
        do {
            
            return try await cardReader.isAccountLinked(using: token)
            
        } catch {
            
            if let err = error as? PaymentCardReaderError {
                
                throw FiservTTPCardReaderError(title: err.errorName,
                                               localizedDescription: NSLocalizedString(err.errorDescription, comment: ""),
                                               underlying: err)
                
            } else {
                throw FiservTTPCardReaderError(title: title,
                                               localizedDescription: error.localizedDescription)
            }
        }
    }
    
    // Only handle the condition where the account is already linked
    // All other errors will propagate to surrounding scope
    internal func linkAccount(token: String) async throws {
        
        let title = "Link Account"
        
        guard let cardReader = self.paymentCardReader else {
            
            throw FiservTTPCardReaderError(title: title,
                                           localizedDescription: NSLocalizedString("Payment Card Reader not available.", comment: ""))
        }
        
        let token = PaymentCardReader.Token(rawValue: token)
        
        do {
            
            try await cardReader.linkAccount(using: token)
            
            // Only handle the condition where the account is already linked
            // All other erreors will propagate to surrounding scope
        } catch PaymentCardReaderError.accountAlreadyLinked {
            // This error will not be thrown
        } catch {
            
            if let err = error as? PaymentCardReaderError {
            
                throw FiservTTPCardReaderError(title: err.errorName,
                                               localizedDescription: NSLocalizedString(err.errorDescription, comment: ""),
                                               underlying: err)
                
            } else {
                throw FiservTTPCardReaderError(title: title,
                                               localizedDescription: error.localizedDescription)
            }
        }
    }
    
    // Before using a device to read payment cards, you need to configure it appropriately.
    // This configuration must be done on every device using for Tap to Pay on iPhone
    // for the first time. The initial configuration of a device can take up to two minutes.
    // Any subsequent configuration updates typically take just a few seconds.
    
    internal func initializeSession(token: String, eventHandler: @escaping (PaymentCardReader.Event) -> Void) async throws {
        
        let title = "Initialize Session"
        
        guard let cardReader = self.paymentCardReader else {
            
            throw FiservTTPCardReaderError(title: title,
                                           localizedDescription: NSLocalizedString("Payment Card Reader not available.", comment: ""))
        }
        
        let readerToken = PaymentCardReader.Token(rawValue: token)
        
        let events = cardReader.events
        
        do {
            
            eventTask?.cancel()

            eventTask = Task {
                
                for await event in events {
                    
                    // A cancelled subscription has been replaced by a newer one,
                    // and its last in-flight event would report the old session's
                    // progress over the new session's.
                    if Task.isCancelled { break }
                    
                    await MainActor.run {
                        eventHandler(event)
                    }
                }
            }
            
            cardReaderSession = try await self.paymentCardReader?.prepare(using: readerToken)
            
        } catch {
            
            if let err = error as? PaymentCardReaderError {
            
                throw FiservTTPCardReaderError(title: err.errorName,
                                               localizedDescription: NSLocalizedString(err.errorDescription, comment: ""),
                                               underlying: err)
                
            } else {
                
                throw FiservTTPCardReaderError(title: title,
                                               localizedDescription: error.localizedDescription)
            }
        }
    }
    
    internal func validateCard(currencyCode: String, reason: PaymentCardVerificationRequest.Reason = .other) async throws -> FiservTTPValidateCardResponse {
        
        guard let session = cardReaderSession else {
         
            throw FiservTTPCardReaderError(title: "Invalid Session",
                                            localizedDescription: NSLocalizedString("The card reader session has not been initialized.", comment: ""))
        }
        
        do {
            
            let request = PaymentCardVerificationRequest(currencyCode: currencyCode, for: reason)
            
            // This method throws a ReadError if a person dismisses the sheet or the sheet fails to appear.
            let result = try await session.readPaymentCard(request)
            
            return FiservTTPValidateCardResponse(id: result.id,
                                                 generalCardData: result.generalCardData,
                                                 paymentCardData: result.paymentCardData)
        } catch {
            
            if let err = error as? PaymentCardReaderError {
            
                throw FiservTTPCardReaderError(title: err.errorName,
                                               localizedDescription: NSLocalizedString(err.errorDescription, comment: ""),
                                               underlying: err)
                
            } else if let err = error as? PaymentCardReaderSession.ReadError {
                
                throw FiservTTPCardReaderError(title: err.errorName,
                                               localizedDescription: NSLocalizedString(err.errorDescription, comment: ""),
                                               underlying: err)
                
            } else {
                
                throw FiservTTPCardReaderError(title: "Validate Card",
                                               localizedDescription: error.localizedDescription)
            }
        }
    }
    
    internal func readCard(for amount: Decimal,
                           currencyCode: String,
                           transactionType: PaymentCardTransactionRequest.TransactionType) async throws -> Result<PaymentCardReadResult, Error> {
        
        guard let session = cardReaderSession else {
         
            return .failure(FiservTTPCardReaderError(title: "Invalid Session",
                                                     localizedDescription: NSLocalizedString("The card reader session has not been initialized.", comment: "")))
        }
        do {
            
            let request = PaymentCardTransactionRequest(amount: amount, currencyCode: currencyCode, for: transactionType)
            
            // This method throws a ReadError if a person dismisses the sheet or the sheet fails to appear.
            
            let result = try await session.readPaymentCard(request)
            
            if let _ = result.generalCardData, let _ = result.paymentCardData {
                
                return .success(result)
            }
            
            return .failure(FiservTTPCardReaderError(title: "Read Payment Card",
                                                     localizedDescription: "The card was unable to be successfully read."))
            
        } catch {
            
            if let err = error as? PaymentCardReaderError {
            
                throw FiservTTPCardReaderError(title: err.errorName,
                                               localizedDescription: NSLocalizedString(err.errorDescription, comment: ""),
                                               underlying: err)
                
            } else if let err = error as? PaymentCardReaderSession.ReadError {
                
                throw FiservTTPCardReaderError(title: err.errorName,
                                               localizedDescription: NSLocalizedString(err.errorDescription, comment: ""),
                                               underlying: err)
                
            } else {
                
                throw FiservTTPCardReaderError(title: "Read Card Payment",
                                               localizedDescription: error.localizedDescription)
            }
        }
    }
}

