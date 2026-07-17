import Foundation

enum AppStoreConnectAPIService {
    static let betaTesters = "https://api.appstoreconnect.apple.com/v1/betaTesters"
    static func betaTesters(for appID: String) -> String {
        "https://api.appstoreconnect.apple.com/v1/apps/\(appID)/relationships/betaTesters"
    }
}

enum AppStoreConnectAPIQuery: String {
    case filterByApp = "filter[apps]"
}

struct AppStoreConnectClient {
    let urlSession: URLSession

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

    static func deleteTesters(_ testers: [Tester], token: String, appID: String) async throws {
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
