import Foundation

/// Response from POST /api/v2/TapToPay/challenge
struct ChallengeResponse: Decodable {
    let challenge: String
}
