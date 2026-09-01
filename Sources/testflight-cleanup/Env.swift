import Foundation

/// Minimal environment helpers, including loading a local `.env` file.
enum Env {
    /// Loads key/value pairs from a `.env` file into the process environment
    /// without overriding variables that are already set.
    static func loadDotEnv(at url: URL) {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }

        for rawLine in contents.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            guard let separatorIndex = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)

            // Strip matching surrounding quotes.
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }

            if ProcessInfo.processInfo.environment[key] == nil {
                setenv(key, value, 0)
            }
        }
    }

    static func string(_ name: String) -> String? {
        let value = ProcessInfo.processInfo.environment[name]
        if let value, !value.isEmpty {
            return value
        }
        return nil
    }

    static func string(_ name: String, default defaultValue: String) -> String {
        string(name) ?? defaultValue
    }

    static func int(_ name: String, default defaultValue: Int) -> Int {
        guard let value = string(name), let parsed = Int(value) else {
            return defaultValue
        }
        return parsed
    }

    static func require(_ name: String) throws -> String {
        guard let value = string(name) else {
            throw TestflightCleanupError.missingEnvironment(name)
        }
        return value
    }
}
