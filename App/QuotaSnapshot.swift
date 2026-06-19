import Foundation

/// Mirrors the JSON returned by `GET /quota` from the Cloudflare Worker
/// in `workers/quota.js`. All fields are required — the Worker always
/// emits the full shape on success.
struct QuotaSnapshot: Codable, Equatable {
    var monthlyQuotaGB: Double
    var usedGB: Double
    var usedBytes: Int64
    var remainingGB: Double
    var percentUsed: Double
    var daysUntilReset: Int
    var billingPeriodStart: String
    var billingPeriodEnd: String
    var incomingBytes: Int64
    var outgoingBytes: Int64
    var fetchedAt: Date
    // Owner-only: the owner's own device usage alongside the server total.
    var selfUsedGB: Double? = nil
    var selfQuotaGB: Double? = nil
}
