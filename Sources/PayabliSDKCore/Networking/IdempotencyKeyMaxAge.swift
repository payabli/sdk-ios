import Foundation

/// How long a money-moving attempt's idempotency key is worth sending again: the two minutes the service remembers
/// one, plus a token fetch, a request, a refresh and a replay at the whole-call budget each. Erring short is what
/// can take a payment twice, since a forgotten key only runs as a new request.
package let payabliIdempotencyKeyMaxAge: Duration = .seconds(120) + .seconds(PayabliService.wholeCallTimeout * 4)
