import Foundation

// MARK: - AppStoreConnectResponse
struct BuildInformationResponse: Codable {
    let data: [BuildData]
}

// MARK: - BuildData
struct BuildData: Codable {
    let attributes: BuildAttributes
}

// MARK: - Attributes
struct BuildAttributes: Codable {
    let version: String
    let uploadedDate: String
    let expirationDate: String
    let expired: Bool
    let minOsVersion: String
    let lsMinimumSystemVersion: String?
    let processingState: String
    let buildAudienceType: String
}
