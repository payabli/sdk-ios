import Foundation

/// How long a money-moving attempt's idempotency key is held: as long as a repeat under it may still be refused, plus
/// a token fetch, a request, a refresh and a replay at the whole-call budget each. Erring short can take a payment
/// twice, since a retry that has lost its key goes out under a fresh one.
package let payabliIdempotencyKeyMaxAge: Duration = .seconds(120) + .seconds(PayabliService.wholeCallTimeout * 4)
