
import Foundation
import CryptoKit

/// Generates an ES256-signed JWT for App Store Connect authentication.
enum AppStoreToken {
    /// Loads the private key contents from the environment or a local `AuthKey.p8`.
    static func loadPrivateKeyPEM(baseDir: URL) throws -> String {
        if let inline = Env.string("APPSTORE_PRIVATE_KEY") {
            return inline.replacingOccurrences(of: "\\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let configuredPath = Env.string("PRIVATE_KEY_PATH")
        var keyURL: URL
        if let configuredPath {
            let candidate = URL(fileURLWithPath: configuredPath)
            keyURL = candidate.path.hasPrefix("/") ? candidate : baseDir.appendingPathComponent(configuredPath)
        } else {
            keyURL = baseDir.appendingPathComponent("AuthKey.p8")
        }

        guard FileManager.default.fileExists(atPath: keyURL.path),
              let contents = try? String(contentsOf: keyURL, encoding: .utf8) else {
            throw TestflightCleanupError.missingPrivateKey
        }

        return contents.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func generate(baseDir: URL) throws -> String {
        let keyID = try Env.require("APPSTORE_KEY_ID")
        let issuerID = Env.string("APPSTORE_ISSUER_ID")
        let pem = try loadPrivateKeyPEM(baseDir: baseDir)

        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)

        let header: [String: Any] = [
            "alg": "ES256",
            "kid": keyID,
            "typ": "JWT",
        ]

        let now = Int(Date().timeIntervalSince1970)
        var payload: [String: Any] = [
            "iat": now,
            "exp": now + 20 * 60,
            "aud": "appstoreconnect-v1",
        ]

        if let issuerID {
            payload["iss"] = issuerID
        } else {
            payload["sub"] = "user"
        }

        let headerSegment = try base64URLEncodedJSON(header)
        let payloadSegment = try base64URLEncodedJSON(payload)
        let signingInput = "\(headerSegment).\(payloadSegment)"

        let signature = try privateKey.signature(for: Data(signingInput.utf8))
        let signatureSegment = base64URLEncode(signature.rawRepresentation)

        return "\(signingInput).\(signatureSegment)"
    }

    private static func base64URLEncodedJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return base64URLEncode(data)
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
