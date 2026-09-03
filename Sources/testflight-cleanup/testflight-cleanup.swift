import ArgumentParser
import Foundation

struct RemovableTester {
    let id: String
    var buildVersion: Int?
    var sessionCount: Int?
}

@main
struct testflight_cleanup: AsyncParsableCommand {

    @Option(help: "The App Store Connect app ID to filter testers by")
    var appID: String

    @Option(help: "Page limit if required") 
    var pageLimit: Int? = nil

    @Option(help: "Minimum build number a user should have installed")
    var minimumBuildNumber: Int

    @Option(help: "Dry run mode, no users will be removed")
    var dryRun: Bool = true

    mutating func run() async throws {
        var nextURL: URL?
        var pageIndex = 0
        var totalRemoved = 0
        var totalProcessed = 0

        let timePeriod = UsagePeriod.month
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let token = try AppStoreToken.generate(baseDir: currentDir)

        do {
            repeat {
                pageIndex += 1
                let page = try await AppStoreConnectClient.fetchTesterPage(token, appID: appID, nextURL: nextURL)
                let testers = page.testers
                nextURL = page.nextURL

                print("--- Page \(pageIndex): \(testers.count) testers ---")
                testers.forEach { print($0.debugDescription) }

                let revokedTesters = testers.filter(\.isRevoked)
                print("\(revokedTesters.count) testers are already revoked")

                // Check if build is already expired
                let buildInfo = try await AppStoreConnectClient.buildInformation(for: minimumBuildNumber, token: token)
                let buildIsExpired = buildInfo?.expired

                // GET testers with an old build
                let testersOnDeprecatedBuild = testers.filter { $0.isBelow(minimumBuild: minimumBuildNumber) && $0.isRevoked == false }

                print("\(testersOnDeprecatedBuild.count) testers on an old build")


                // If build is expired, no need to check session count
                if buildIsExpired == true {
                    print("Build \(minimumBuildNumber) is expired in Testflight, no need to check session count.")
                    try await removeTesters(testersOnDeprecatedBuild.map { $0.id }, token: token, appID: appID, pageIndex: pageIndex)
                    totalRemoved += testersOnDeprecatedBuild.count
                } else {
                    print("Build \(minimumBuildNumber) is not expired in Testflight, fetching user metrics to check session count")
                    var removableTesters = testersOnDeprecatedBuild.map {
                        RemovableTester(
                            id: $0.id,
                            buildVersion: $0.latestInstalledBuild,
                            sessionCount: nil)
                    }

                    for index in removableTesters.indices {
                        // Fetch usage metrics for testers over time period
                        let usageMetrics = try await AppStoreConnectClient.fetchMetrics(for: removableTesters[index].id, token: token, appID: appID, period: timePeriod)
                        removableTesters[index].sessionCount = usageMetrics?.sessionCount
                        print("TESTER \(removableTesters[index].id) has had \(removableTesters[index].sessionCount ?? 0) sessions in the last \(timePeriod.description)")
                    }

                    let testersWithoutSessions = removableTesters.filter { $0.sessionCount == 0 }
                    print("\(testersWithoutSessions.count) testers have had zero sessions in the last \(timePeriod.description)")

                    try await removeTesters(testersWithoutSessions.map { $0.id }, token: token, appID: appID, pageIndex: pageIndex)
                    totalRemoved += testersWithoutSessions.count
                }

                totalProcessed += testers.count

                if let limit = pageLimit, pageIndex >= limit {
                    print("Reached page limit of \(limit)")
                    break
                }
            } while nextURL != nil
        } catch {
            printSummary(removed: totalRemoved, processed: totalProcessed)
            print("Error on page \(pageIndex): \(error)")
            throw error
        }
        printSummary(removed: totalRemoved, processed: totalProcessed)
    }

    private func removeTesters(_ testerIds: [String], token: String, appID: String, pageIndex: Int) async throws {
        if dryRun {
            print("DRY RUN: would delete \(testerIds.count) testers on page \(pageIndex)")
        } else {
            print("DELETING TESTERS")
            try await AppStoreConnectClient.deleteTesters(testerIds, token: token, appID: appID)
        }
    }

    private func printSummary(removed: Int, processed: Int) {
        print("--- Done: \(removed) removable testers found across \(processed) total testers ---")
    }
}

fileprivate extension Tester {
    
    /// A user may have the beta installed across multiple devices so it's important we check what the most recent build version is
    var latestInstalledBuild: Int? {
        let orderedDevices = attributes.appDevices.sorted { $0.appBuildVersion.buildVersion ?? 0 > $1.appBuildVersion.buildVersion ?? 0 }
        return orderedDevices.first?.appBuildVersion.buildVersion
    }

    func isBelow(minimumBuild: Int) -> Bool {
        guard let installed = latestInstalledBuild else { return true }
                return installed < minimumBuild
    }

    var isRevoked: Bool {
        attributes.state == .REVOKED
    }

    var debugDescription: String {
        let version = attributes.appDevices.first?.appBuildVersion.appVersionString ?? "No version"
        let build = latestInstalledBuild.map(String.init) ?? "No build"
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
