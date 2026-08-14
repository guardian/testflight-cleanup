import ArgumentParser

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
        var testersToDelete: [RemovableTester] = []
        let allTesters = try await  AppStoreConnectClient.fetchTesters(token, appID: appID, pageLimit: pageLimit)
        allTesters.forEach { tester in
            print(tester.debugDescription)
        }

        // GET testers with an old build
        let testersToRemove = allTesters.filter { tester in
            guard let installedBuild = tester.attributes.appDevices.first?.appBuildVersion.buildVersion else { return true }
            return installedBuild < minimumBuildNumber
        }
        testersToRemove.forEach { tester in
            print(tester.debugDescription)
        }
        print("\(testersToRemove.count) testers on an old build")

        testersToDelete = testersToRemove.map { RemovableTester(id: $0.id, buildVersion: $0.attributes.appDevices.first?.appBuildVersion.buildVersion, sessionCount: nil) }
        for index in testersToDelete.indices {
            let usageMetrics = try await AppStoreConnectClient.fetchMetrics(for: testersToDelete[index].id, token: token, appID: appID)
            testersToDelete[index].sessionCount = usageMetrics?.sessionCount
            print("TESTER \(testersToDelete[index].id) has had \(testersToDelete[index].sessionCount ?? 0) sessions")
        }
        print("\(testersToDelete.count) testers to remove")

        let testersWithoutSessions = testersToDelete.filter { $0.sessionCount == 0 }

        print("\(testersWithoutSessions.count) testers have had zero sessions")

        // Delete testers
//        guard dryRun == false else { return }
        print("DELETING TESTERS")
//        try await AppStoreConnectClient.deleteTesters(testersToRemove, token: token, appID: appID)
    }
}

extension String {
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

extension Tester {
    var debugDescription: String {
        let testerID = id
        let testerState = attributes.state
        let versionNumber = attributes.appDevices.first?.appBuildVersion.components(separatedBy: " ").first ?? "No version number"
        let buildVersion = attributes.appDevices.first?.appBuildVersion.components(separatedBy: " ").last?.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "") ?? "No build number"
        return "[\(testerState)] \(testerID) - Version: \(versionNumber) Build: \(buildVersion)"
    }
}
