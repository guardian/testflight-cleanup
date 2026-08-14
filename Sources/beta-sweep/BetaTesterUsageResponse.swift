import Foundation

struct BetaTesterUsageResponse: Codable {
    let data: [UsageData]
}

struct UsageData: Codable {
    let type: String
    let dataPoints: [DataPoint]
}

struct DataPoint: Codable {
    let start: String
    let end: String
    let values: UsageMetrics
}

struct UsageMetrics: Codable {
    let sessionCount: Int
    let crashCount: Int
    let feedbackCount: Int
}
