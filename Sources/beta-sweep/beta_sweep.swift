import ArgumentParser
import Foundation

struct RemovableTester {
    let id: String
    var buildVersion: Int?
    var sessionCount: Int?
}

@main
struct beta_sweep: AsyncParsableCommand {

    @Option(help: "The App Store Connect app ID to filter testers by")
    var appID: String

    @Option(help: "The token used to authenticate with App Store Connect")
    var token: String

    @Option(help: "Page limit if required") 
    var pageLimit: Int? = nil

    @Option(help: "Minimum build number a user should have installed")
    var minimumBuildNumber: Int

//    @Option(help: "Dry run mode, no users will be removed")
//    var dryRun: Bool = true

    mutating func run() async throws {
        var nextURL: URL?
        var pageIndex = 0
        var totalRemoved = 0
        var totalProcessed = 0

        repeat {
            pageIndex += 1
            let page = try await AppStoreConnectClient.fetchTesterPage(token, appID: appID, nextURL: nextURL)
            let testers = page.testers
            nextURL = page.nextURL

            print("--- Page \(pageIndex): \(testers.count) testers ---")
            testers.forEach { print($0.debugDescription) }

            // GET testers with an old build
            let testersOnDeprecatedBuild = testers.filter { $0.isBelow(minimumBuild: minimumBuildNumber) }

            print("\(testersOnDeprecatedBuild.count) testers on an old build")

            var testersToDelete = testersOnDeprecatedBuild.map {
                RemovableTester(
                    id: $0.id,
                    buildVersion: $0.installedBuildVersion,
                    sessionCount: nil)
            }

            for index in testersToDelete.indices {
                let usageMetrics = try await AppStoreConnectClient.fetchMetrics(for: testersToDelete[index].id, token: token, appID: appID)
                testersToDelete[index].sessionCount = usageMetrics?.sessionCount
                print("TESTER \(testersToDelete[index].id) has had \(testersToDelete[index].sessionCount ?? 0) sessions")
            }

            let testersWithoutSessions = testersToDelete.filter { $0.sessionCount == 0 }
            print("\(testersWithoutSessions.count) testers have had zero sessions")

            // TODO: add deletion
            // Delete testers
    //        guard dryRun == false else { return }
    //        print("DELETING TESTERS")
    //        try await AppStoreConnectClient.deleteTesters(testersWithoutSessions, token: token, appID: appID)

            totalRemoved += testersWithoutSessions.count
            totalProcessed += testers.count

            if let limit = pageLimit, pageIndex >= limit {
                print("Reached page limit of \(limit)")
                break
            }
        } while nextURL != nil
        print("--- Done: \(totalRemoved) removable testers found across \(totalProcessed) total testers ---")
    }
}

fileprivate extension Tester {
    var installedBuildVersion: Int? {
        attributes.appDevices.first?.appBuildVersion.buildVersion
    }

    func isBelow(minimumBuild: Int) -> Bool {
        guard let installed = installedBuildVersion else { return true }
                return installed < minimumBuild
    }

    var debugDescription: String {
        let version = attributes.appDevices.first?.appBuildVersion.appVersionString ?? "No version"
        let build = installedBuildVersion.map(String.init) ?? "No build"
        return "[\(attributes.state)] \(id) - Version: \(version) Build: \(build)"
    }
}

// MARK: String Parsing

fileprivate extension String {
    var appVersionString: String? {
        components(separatedBy: " ").first
    }

    var buildVersion: Int? {
        if let buildString = components(separatedBy: " ")
            .last?.replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "") {
            return Int(buildString)
        }
        return nil
    }
}
