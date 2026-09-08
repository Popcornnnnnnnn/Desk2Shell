import Foundation

final class TelemetryClient: @unchecked Sendable {
    static let shared = TelemetryClient()
    private let consentKey = "telemetryOptIn"
    private let installationKey = "telemetryInstallationId"

    var isAvailable: Bool { endpoint != nil }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: consentKey) && isAvailable }
        set { UserDefaults.standard.set(newValue && isAvailable, forKey: consentKey) }
    }

    func send(event: String, errorCode: String? = nil) {
        guard isEnabled, let endpoint, allowedEvents.contains(event) else { return }
        var installationId = UserDefaults.standard.string(forKey: installationKey)
        if installationId == nil {
            installationId = UUID().uuidString.lowercased()
            UserDefaults.standard.set(installationId, forKey: installationKey)
        }
        let payload = TelemetryEvent(
            schemaVersion: 1,
            installationId: installationId!,
            event: event,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
            osFamily: "macOS",
            osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            durationBucket: nil,
            errorCode: errorCode,
            occurredAt: DateCodec.string(Date())
        )
        guard let data = try? JSONEncoder.desk2Shell.encode(payload) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        URLSession.shared.dataTask(with: request).resume()
    }

    private var endpoint: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "Desk2ShellTelemetryEndpoint") as? String,
              value.hasPrefix("https://") else { return nil }
        return URL(string: value)
    }

    private let allowedEvents: Set<String> = [
        "package_created", "target_observed", "ssh_verified", "access_expired", "access_revoked", "operation_failed"
    ]
}

private struct TelemetryEvent: Codable {
    let schemaVersion: Int
    let installationId: String
    let event: String
    let appVersion: String
    let osFamily: String
    let osMajor: Int
    let durationBucket: String?
    let errorCode: String?
    let occurredAt: String
}
