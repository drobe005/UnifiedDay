import UIKit

/// Builds the Send Feedback email in Settings. A backup to TestFlight's own
/// screenshot feedback, which some testers never find.
enum Feedback {
    /// Where feedback goes. Testers can see this address.
    static let address = "design@deiondrick.com"

    /// For example "0.1 (1)", read from the build so it never goes stale.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// The hardware model, for example "iPhone17,3". UIDevice only says "iPhone".
    private static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let model = withUnsafeBytes(of: &systemInfo.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return model.isEmpty ? UIDevice.current.model : model
    }

    @MainActor
    static func mailURL() -> URL? {
        let body = """


        ---
        What happened, or what would make UnifiedDay better? Write above this line.
        App: UnifiedDay \(appVersion)
        Device: \(deviceModel), iOS \(UIDevice.current.systemVersion)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "UnifiedDay feedback (\(appVersion))"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
