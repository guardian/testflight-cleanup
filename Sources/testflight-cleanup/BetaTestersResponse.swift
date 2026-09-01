import Foundation

struct BetaTestersResponse: Codable {
    let data: [Tester]
    let links: PageLinks
    let meta: Meta
}

struct PageLinks: Codable {
    let next: String?
    let `self`: String
}

struct AppDevices: Codable {
    let model: String
    let platform: String
    let osVersion: String
    let appBuildVersion: String
}

struct Attributes: Codable {
    let lastName: String?
    let firstName: String
    let inviteType: String
    let state: BetaTesterState
    let appDevices: [AppDevices]
    let email: String?
}

struct Links: Codable {
    let `self`: String
}

struct BetaGroups: Codable {
    let links: Links
}

struct Builds: Codable {
    let links: Links
}

struct Apps: Codable {
    let links: Links
}

struct Relationships: Codable {
    let betaGroups: BetaGroups
    let builds: Builds
    let apps: Apps
}

struct Tester: Codable {
    let type: String
    let id: String
    let attributes: Attributes
    let relationships: Relationships
    let links: Links
}

struct Paging: Codable {
    let nextCursor: String?
    let total: Int
    let limit: Int
}

struct Meta: Codable {
    let paging: Paging
}

enum BetaTesterState: String, Codable {

    // The beta tester is not currently invited.
    case NOT_INVITED

    // The build of your app is eligible for submission and release on the App Store.
    case INVITED

    // The beta tester has accepted an invite to test a build.
    case ACCEPTED

    // The beta tester has installed a build.
    case INSTALLED

    // The beta tester chose to stop testing, or the beta tester was removed from the app. In both cases, their installed build is not expired. Once the build expires, the system deletes the resource.
    case REVOKED

}
