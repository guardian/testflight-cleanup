import Foundation

enum AppStoreConnectAPIService: String {
    case allTesters = "https://api.appstoreconnect.apple.com/v1/betaTesters"
}

struct AppStoreConnectService {
    let urlSession: URLSession

    static func fetchTesters(_ token: String, appID: String, pageLimit: Int? = nil) async throws -> [Tester] {
        var allTesters: [Tester] = []
        var nextURL: URL? = URL(string: AppStoreConnectAPIService.allTesters.rawValue)?.appending(queryItems: [URLQueryItem(name: "filter[apps]", value: appID)])
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

    // TODO: find all testers on a build older than a given number
    // List them out formatted with useful information


    // TODO: Add dry run parameter and introduce real deletion

    // When dry run false, delete users
    // We will need to hit delete endpoint for
}
