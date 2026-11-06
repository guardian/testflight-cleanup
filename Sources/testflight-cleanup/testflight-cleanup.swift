import ArgumentParser
import Logging
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

    @Option(help: "Verbose logging enabled")
    var verboseLogging: Bool = false

    private var logger: Logger {
        var logger = Logger(label: "testflight-cleanup")
        logger.logLevel = verboseLogging ? .debug : .info
        return logger
    }

    mutating func run() async throws {
        let logger = self.logger
        var nextURL: URL?
        var pageIndex = 0
        var totalCandidates = 0
        var totalDeleted = 0
        var totalUnknownSessions = 0
        var totalProcessed = 0
        var candidateTesterIDs: [String] = []

        let timePeriod = UsagePeriod.month
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let token = try AppStoreToken.generate(baseDir: currentDir)
        // Build expiration is global for the run, so fetch once.
        let buildInfo = try await AppStoreConnectClient.buildInformation(for: minimumBuildNumber, token: token)
        let buildIsExpired = buildInfo?.expired == true
        if buildInfo == nil {
            logger.warning("Build \(minimumBuildNumber) could not be found; defaulting to session-count checks.")
        }

        do {
            repeat {
                pageIndex += 1
                let page = try await AppStoreConnectClient.fetchTesterPage(token, appID: appID, nextURL: nextURL, logger: logger)
                let testers = page.testers
                nextURL = page.nextURL
                totalProcessed += testers.count

                logger.info("--- Page \(pageIndex): \(testers.count) testers ---")
                testers.forEach { logger.debug("\($0.debugDescription)") }

                let revokedTesters = testers.filter(\.isRevoked)
                logger.debug("\(revokedTesters.count) testers are already revoked")

                // GET testers with an old build
                let testersOnDeprecatedBuild = testers.filter { $0.isBelow(minimumBuild: minimumBuildNumber) && $0.isRevoked == false }

                logger.info("\(testersOnDeprecatedBuild.count) testers on an old build")


                // If build is expired, no need to check session count
                if buildIsExpired {
                    logger.debug("Build \(minimumBuildNumber) is expired in Testflight, no need to check session count.")
                    let pageCandidateIDs = testersOnDeprecatedBuild.map(\.id)
                    totalCandidates += pageCandidateIDs.count
                    candidateTesterIDs.append(contentsOf: pageCandidateIDs)
                } else {
                    logger.debug("Build \(minimumBuildNumber) is not expired in Testflight, fetching user metrics to check session count")
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
                        let sessionText = removableTesters[index].sessionCount.map(String.init) ?? "unknown"
                        logger.debug("TESTER \(removableTesters[index].id) has had \(sessionText) sessions in the last \(timePeriod.description)")
                    }

                    let testersWithUnknownSessions = removableTesters.filter { $0.sessionCount == nil }
                    let testersWithoutSessions = removableTesters.filter { $0.sessionCount == 0 }
                    logger.info("\(testersWithoutSessions.count) testers have had zero sessions in the last \(timePeriod.description)")
                    if !testersWithUnknownSessions.isEmpty {
                        logger.warning("\(testersWithUnknownSessions.count) testers have unknown session counts and will not be deleted")
                    }

                    totalUnknownSessions += testersWithUnknownSessions.count
                    let pageCandidateIDs = testersWithoutSessions.map(\.id)
                    totalCandidates += pageCandidateIDs.count
                    candidateTesterIDs.append(contentsOf: pageCandidateIDs)
                }

                if let limit = pageLimit, pageIndex >= limit {
                    logger.info("Reached page limit of \(limit)")
                    break
                }
            } while nextURL != nil
        } catch {
            printSummary(candidates: totalCandidates, deleted: totalDeleted, unknownSessions: totalUnknownSessions, processed: totalProcessed)
            logger.error("Error on page \(pageIndex): \(error)")
            throw error
        }

        // Phase 2: delete only after pagination is complete to avoid cursor invalidation.
        let uniqueCandidateIDs = uniquePreservingOrder(candidateTesterIDs)
        logger.info("Collected \(uniqueCandidateIDs.count) unique tester(s) for deletion")
        totalDeleted = try await removeTestersInBatches(uniqueCandidateIDs, token: token, appID: appID)

        printSummary(candidates: totalCandidates, deleted: totalDeleted, unknownSessions: totalUnknownSessions, processed: totalProcessed)
    }

    private func removeTestersInBatches(_ testerIds: [String], token: String, appID: String, batchSize: Int = 200) async throws -> Int {
        guard !testerIds.isEmpty else {
            logger.info("No testers to delete")
            return 0
        }

        let batches = testerIds.chunked(into: batchSize)
        var deleted = 0

        if dryRun {
            logger.notice("DRY RUN: would delete \(testerIds.count) testers across \(batches.count) batch(es)")
            return 0
        } else {
            for (index, batch) in batches.enumerated() {
                logger.info("DELETING BATCH \(index + 1)/\(batches.count) with \(batch.count) tester(s)")
                try await AppStoreConnectClient.deleteTesters(batch, token: token, appID: appID, logger: logger)
                deleted += batch.count
            }
            return deleted
        }
    }

    private func uniquePreservingOrder(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func printSummary(candidates: Int, deleted: Int, unknownSessions: Int, processed: Int) {
        logger.info("--- Done: processed \(processed) testers; found \(candidates) deletion candidate(s); deleted \(deleted); unknown session count \(unknownSessions) ---")
    }
}

fileprivate extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { start in
            let end = Swift.min(start + size, count)
            return Array(self[start..<end])
        }
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
