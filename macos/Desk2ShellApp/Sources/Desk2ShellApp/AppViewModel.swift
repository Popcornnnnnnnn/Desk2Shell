import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.defaultsKey) }
    }
    @Published var targetAlias = ""
    @Published var authKey = ""
    @Published var windowsUser = ""
    @Published var durationHours = 24
    @Published private var statusMessage = BilingualText("正在检查 Tailscale…", "Checking Tailscale…")
    @Published var pairingCode = ""
    @Published var packagePath = ""
    @Published var targetIPv4 = ""
    @Published var busy = false
    @Published var telemetryOptIn = false

    let telemetryAvailable = TelemetryClient.shared.isAvailable

    private let services = ControllerServices()
    private var record: EnrollmentRecord?
    private var pollingTask: Task<Void, Never>?
    private var pairingKey = Data()

    init() {
        language = AppLanguage.preferred
        telemetryOptIn = TelemetryClient.shared.isEnabled
        preparePairingCode()
        Task { await preflight() }
    }

    var status: String { statusMessage.value(for: language) }
    var statusIsSuccess: Bool { statusMessage.isSuccess }

    func text(_ chinese: String, _ english: String) -> String {
        language.text(chinese, english)
    }

    private func setStatus(_ chinese: String, _ english: String, isSuccess: Bool = false) {
        statusMessage = BilingualText(chinese, english, isSuccess: isSuccess)
    }

    private func setError(_ error: Error) {
        if let error = error as? Desk2ShellError {
            statusMessage = error.message
        } else {
            statusMessage = BilingualText(error.localizedDescription, error.localizedDescription)
        }
    }

    private func preparePairingCode() {
        do {
            let pairing = try EnrollmentCrypto.makePairingCode()
            pairingKey = pairing.key
            pairingCode = pairing.display
        } catch {
            setError(error)
        }
    }

    func preflight() async {
        do {
            let snapshot = try services.tailscaleSnapshot()
            setStatus("Tailscale 已连接：\(snapshot.controllerIPv4)", "Tailscale connected: \(snapshot.controllerIPv4)")
        } catch {
            setError(error)
        }
    }

    func createPackage() {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            guard ControllerServices.validAlias(targetAlias) else { throw Desk2ShellError.invalidAlias }
            guard authKey.hasPrefix("tskey-auth-") || authKey.hasPrefix("tskey-client-") else { throw Desk2ShellError.invalidAuthKey }
            guard (1...168).contains(durationHours) else {
                throw Desk2ShellError.commandFailed(BilingualText(
                    "有效期必须在 1–168 小时之间。",
                    "The access duration must be between 1 and 168 hours."
                ))
            }

            if !packagePath.isEmpty || pairingKey.count != 32 {
                preparePairingCode()
            }
            guard pairingKey.count == 32 else { throw Desk2ShellError.invalidPairingCode }

            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Desk2Shell-\(targetAlias).zip"
            panel.allowedContentTypes = [.zip]
            guard panel.runModal() == .OK, let destination = panel.url else { return }

            let snapshot = try services.tailscaleSnapshot()
            let id = UUID().uuidString.lowercased()
            let created = Date()
            let expires = created.addingTimeInterval(TimeInterval(durationHours * 3600))
            let key = try services.createKey(enrollmentId: id)
            let payload = EnrollmentPayload(
                schemaVersion: 1,
                enrollmentId: id,
                targetAlias: targetAlias,
                controllerPublicKey: key.publicKey,
                controllerTailscaleIPv4: snapshot.controllerIPv4,
                controllerNodeName: snapshot.controllerNodeName,
                tailnetName: snapshot.tailnetName,
                createdAt: DateCodec.string(created),
                expiresAt: DateCodec.string(expires),
                tailscaleAuthKey: authKey
            )
            let envelope = try EnrollmentCrypto.seal(payload: payload, keyData: pairingKey, createdAt: payload.createdAt)
            try services.exportPackage(envelope: envelope, alias: targetAlias, destination: destination)

            let newRecord = EnrollmentRecord(
                id: id,
                targetAlias: targetAlias,
                keyPath: key.privateKey.path,
                createdAt: payload.createdAt,
                expiresAt: payload.expiresAt,
                targetIPv4: nil,
                windowsUser: windowsUser.isEmpty ? nil : windowsUser
            )
            try services.store(record: newRecord)
            record = newRecord
            packagePath = destination.path
            authKey = ""
            setStatus(
                "安装包已生成。传到 Windows 后粘贴下方配对码。",
                "The setup package is ready. Transfer it to Windows, then paste the pairing code below."
            )
            TelemetryClient.shared.send(event: "package_created")
            startPolling()
        } catch {
            setError(error)
        }
    }

    func openTailscaleAuthKeyPage() {
        guard let url = URL(string: "https://login.tailscale.com/admin/settings/keys") else { return }
        NSWorkspace.shared.open(url)
        setStatus(
            "请创建一次性、短有效期、不要勾选 Ephemeral 的 Auth Key，然后返回粘贴。",
            "Create a one-off, short-lived Auth Key without Ephemeral enabled, then return and paste it."
        )
    }

    func pasteAuthKey() {
        guard let value = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              value.hasPrefix("tskey-auth-") || value.hasPrefix("tskey-client-")
        else {
            setStatus(
                "剪贴板里没有可识别的 Tailscale Auth Key。",
                "The clipboard does not contain a recognized Tailscale Auth Key."
            )
            return
        }
        authKey = value
        setStatus(
            "Auth Key 已粘贴；生成安装包后会立即从界面清除。",
            "Auth Key pasted. It will be cleared from the interface after the package is generated."
        )
    }

    func copyPairingCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingCode, forType: .string)
        setStatus(
            "配对码已复制；安装完成后会自动清除剪贴板。",
            "Pairing code copied. The clipboard will be cleared automatically after setup."
        )
        let copied = pairingCode
        Task {
            try? await Task.sleep(for: .seconds(120))
            if NSPasteboard.general.string(forType: .string) == copied {
                NSPasteboard.general.clearContents()
            }
        }
    }

    func checkConnection() {
        guard let record else {
            setStatus("请先生成安装包。", "Generate the setup package first.")
            return
        }
        busy = true
        defer { busy = false }
        do {
            if let result = try services.receiveTargetResult(enrollmentId: record.id) {
                try finalize(result: result, record: record)
                return
            }
            guard let ip = try services.findTargetIPv4(alias: record.targetAlias) else {
                setStatus(
                    "尚未发现目标机；保持 Windows 完成页打开后重试。",
                    "The target has not been found yet. Keep the Windows completion page open and try again."
                )
                return
            }
            targetIPv4 = ip
            guard !windowsUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                setStatus(
                    "已发现 \(ip)，但还没收到 Taildrop 结果。可重试或手动导入 desk2shell-result.json。",
                    "Found \(ip), but the Taildrop result has not arrived. Try again or import desk2shell-result.json manually."
                )
                return
            }
            setStatus(
                "已发现目标，但没有可验证的主机指纹。请导入 Windows 生成的 desk2shell-result.json。",
                "The target was found, but no verifiable host fingerprint is available. Import the desk2shell-result.json generated on Windows."
            )
        } catch {
            setError(error)
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            for _ in 0..<180 {
                if Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(5))
                guard let self, !self.busy else { continue }
                self.checkConnection()
                if self.statusIsSuccess { return }
            }
        }
    }

    func importResult() {
        guard let record else {
            setStatus("请先生成安装包。", "Generate the setup package first.")
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try finalize(result: services.readTargetResult(url: url, enrollmentId: record.id), record: record)
        } catch {
            setError(error)
        }
    }

    private func finalize(result: TargetResult, record: EnrollmentRecord) throws {
        guard result.targetAlias == record.targetAlias else {
            throw Desk2ShellError.commandFailed(BilingualText(
                "结果文件中的目标名与当前 enrollment 不匹配。",
                "The target name in the result file does not match the current enrollment."
            ))
        }
        targetIPv4 = result.tailscaleIPv4
        windowsUser = result.windowsUser
        try services.pinHostKey(host: result.tailscaleIPv4, port: result.sshPort, expectedFingerprint: result.hostKeyFingerprint)
        try services.installSSHConfig(alias: record.targetAlias, host: result.tailscaleIPv4, user: result.windowsUser, keyPath: record.keyPath)
        try services.loadKeyIntoAgent(enrollmentId: record.id, keyPath: record.keyPath)
        let identity = try services.verifySSH(alias: record.targetAlias, expectedUser: result.windowsUser)
        var updated = record
        updated.targetIPv4 = result.tailscaleIPv4
        updated.windowsUser = result.windowsUser
        updated.expiresAt = result.expiresAt
        try services.store(record: updated)
        self.record = updated
        pollingTask?.cancel()
        NSPasteboard.general.clearContents()
        setStatus(
            "连接成功：\(identity)。现在可使用 ssh \(record.targetAlias)。",
            "Connected as \(identity). You can now use ssh \(record.targetAlias).",
            isSuccess: true
        )
        TelemetryClient.shared.send(event: "ssh_verified")
    }

    func setTelemetryOptIn(_ value: Bool) {
        telemetryOptIn = value
        TelemetryClient.shared.isEnabled = value
    }

    func copySSHCommand() {
        guard let record else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("ssh \(record.targetAlias)", forType: .string)
        setStatus("SSH 命令已复制。", "SSH command copied.")
    }
}
