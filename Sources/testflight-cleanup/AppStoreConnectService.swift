import Foundation

enum AppStoreConnectAPIService {
    static let betaTesters = "https://api.appstoreconnect.apple.com/v1/betaTesters"
    static func betaTesters(for appID: String) -> String {
        "https://api.appstoreconnect.apple.com/v1/apps/\(appID)/relationships/betaTesters"
    }
    static func usage(for tester: String) -> String {
        "https://api.appstoreconnect.apple.com/v1/betaTesters/\(tester)/metrics/betaTesterUsages"
    }
}

enum AppStoreConnectAPIQuery: String {
    case filterByApp = "filter[apps]"
    case period
    case limit
}

enum UsagePeriod: String {
    case week = "P7D"
    case month = "P30D"
    case threeMonth = "P90D"
    case year = "P365D"

    var description: String {
        switch self {
        case .week:
            "one week"
        case .month:
            "one month"
        case .threeMonth:
            "three months"
        case .year:
            "one year"
        }
    }
}

struct TesterPage {
    let testers: [Tester]
    let nextURL: URL?
}

enum TestflightCleanupError: Error, CustomStringConvertible {
    case missingEnvironment(String)
    case missingPrivateKey
    case apiError(String)
    case invalidResponse

    var description: String {
        switch self {
        case .missingEnvironment(let name):
            return "Missing required environment variable: \(name)"
        case .missingPrivateKey:
            return "No private key found. Set APPSTORE_PRIVATE_KEY or place AuthKey.p8 in the repo root."
        case .apiError(let message):
            return message
        case .invalidResponse:
            return "Received an invalid response from the App Store Connect API."
        }
    }
}

struct AppStoreConnectClient {
    let token: String
    let appID: String
    let urlSession: URLSession


    static func fetchTesterPage(_ token: String, appID: String, nextURL: URL?) async throws -> TesterPage {

        do {
            let url = nextURL ?? URL(string: AppStoreConnectAPIService.betaTesters)?.appending(queryItems: [
                URLQueryItem(name: AppStoreConnectAPIQuery.filterByApp.rawValue, value: appID),
                URLQueryItem(name: AppStoreConnectAPIQuery.limit.rawValue, value: "200"),
            ])
            guard let url else { throw TestflightCleanupError.apiError("URL cannot be found") }
            var request = URLRequest(url: url)
            print("Fetching from url \(url)")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let statusCode = (response as? HTTPURLResponse)?.statusCode else {
                throw TestflightCleanupError.apiError("Missing status code")
            }

            guard (200...299).contains(statusCode) else {
                throw TestflightCleanupError.apiError("Invalid status code \(statusCode)")
            }
            let testerResponse = try JSONDecoder().decode(BetaTestersResponse.self, from: data)
            let next = testerResponse.links.next
            let nextURL = next != nil ? URL(string: next!)! : nil
            return TesterPage(testers: testerResponse.data, nextURL: nextURL)
        } catch let error as DecodingError {
            throw TestflightCleanupError.apiError("Decoding error \(error)")
        } catch let error as EncodingError {
            throw TestflightCleanupError.apiError("Encoding error \(error)")
        } catch let error as URLError {
            throw TestflightCleanupError.apiError("Request failed with error \(error)")
        } catch let error as TestflightCleanupError {
            throw error
        } catch {
            throw TestflightCleanupError.apiError("Request failed with error \(error)")
        }
    }

    static func fetchTesters(_ token: String, appID: String, pageLimit: Int? = nil) async throws -> [Tester] {
        var allTesters: [Tester] = []
        var nextURL: URL? = URL(string: AppStoreConnectAPIService.betaTesters)?.appending(queryItems: [
            URLQueryItem(name: AppStoreConnectAPIQuery.filterByApp.rawValue, value: appID)
        ])
        var pageCount = 1
        while let url = nextURL {
            var request = URLRequest(url: url)
            print("Fetching from url \(url)")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            print("Fetching page \(pageCount)")
            let (data, _) = try await URLSession.shared.data(for: request)
            let testerResponse = try JSONDecoder().decode(BetaTestersResponse.self, from: data)
            allTesters.append(contentsOf: testerResponse.data)

            if let limit = pageLimit, pageCount >= limit {
                nextURL = nil
            } else if let next = testerResponse.links.next {
                nextURL = URL(string: next)
                pageCount += 1
            } else {
                nextURL = nil
            }
        }
        print("Found \(allTesters.count) tester(s) across all pages")
        return allTesters
    }

    static func fetchMetrics(for tester: String, token: String, appID: String, period: UsagePeriod = .month) async throws -> UsageMetrics? {
        var url = URL(string: AppStoreConnectAPIService.usage(for: tester))!
        url = url.appending(queryItems: [
            URLQueryItem(name: AppStoreConnectAPIQuery.filterByApp.rawValue, value: appID),
            URLQueryItem(name: AppStoreConnectAPIQuery.period.rawValue, value: period.rawValue)
        ])
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(BetaTesterUsageResponse.self, from: data)
        return response.data.first?.dataPoints.first?.values

    }

    static func deleteTesters(_ testers: [RemovableTester], token: String, appID: String) async throws {
        let url = URL(string: AppStoreConnectAPIService.betaTesters(for: appID))!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "data": testers.map { ["type": "betaTesters", "id": $0.id] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 else {
            throw URLError(.badServerResponse)
        }
        print("Deleted \(testers.count) tester(s)")
    }
}
