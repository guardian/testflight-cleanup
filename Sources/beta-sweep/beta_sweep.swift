// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation

import ArgumentParser

@main
struct beta_sweep: AsyncParsableCommand {

    @Argument(help: "The App Store Connect app ID to filter testers by")
    var appID: String

    @Argument(help: "The token used to authenticate with App Store Connect")
    var token: String

    @Argument(help: "Page limit if required")
    var pageLimit: Int?

    mutating func run() async throws {
        let testers = try await  AppStoreConnectService.fetchTesters(token, appID: appID, pageLimit: pageLimit)
    }
}
