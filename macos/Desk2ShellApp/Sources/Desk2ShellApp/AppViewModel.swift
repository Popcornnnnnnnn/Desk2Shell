import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var targetAlias = ""
    @Published var authKey = ""
    @Published var windowsUser = ""
    @Published var durationHours = 24
    @Published var status = "正在检查 Tailscale…"
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
        telemetryOptIn = TelemetryClient.shared.isEnabled
        preparePairingCode()
        Task { await preflight() }
    }

    private func preparePairingCode() {
        do {
            let pairing = try EnrollmentCrypto.makePairingCode()
            pairingKey = pairing.key
            pairingCode = pairing.display
        } catch {
            status = error.localizedDescription
        }
    }

    func preflight() async {
        do {
            let snapshot = try services.tailscaleSnapshot()
            status = "Tailscale 已连接：\(snapshot.controllerIPv4)"
        } catch {
            status = error.localizedDescription
        }
    }

    func createPackage() {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            guard ControllerServices.validAlias(targetAlias) else { throw Desk2ShellError.invalidAlias }
            guard authKey.hasPrefix("tskey-auth-") || authKey.hasPrefix("tskey-client-") else { throw Desk2ShellError.invalidAuthKey }
            guard (1...168).contains(durationHours) else { throw Desk2ShellError.commandFailed("有效期必须在 1–168 小时之间。") }

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
            status = "安装包已生成。传到 Windows 后粘贴下方配对码。"
            TelemetryClient.shared.send(event: "package_created")
            startPolling()
        } catch {
            status = error.localizedDescription
        }
    }

    func openTailscaleAuthKeyPage() {
        guard let url = URL(string: "https://login.tailscale.com/admin/settings/keys") else { return }
        NSWorkspace.shared.open(url)
        status = "请创建一次性、短有效期、不要勾选 Ephemeral 的 Auth Key，然后返回粘贴。"
    }

    func pasteAuthKey() {
        guard let value = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              value.hasPrefix("tskey-auth-") || value.hasPrefix("tskey-client-")
        else {
            status = "剪贴板里没有可识别的 Tailscale Auth Key。"
            return
        }
        authKey = value
        status = "Auth Key 已粘贴；生成安装包后会立即从界面清除。"
    }

    func copyPairingCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingCode, forType: .string)
        status = "配对码已复制；安装完成后会自动清除剪贴板。"
        let copied = pairingCode
        Task {
            try? await Task.sleep(for: .seconds(120))
            if NSPasteboard.general.string(forType: .string) == copied {
                NSPasteboard.general.clearContents()
            }
        }
    }

    func checkConnection() {
        guard let record else { status = "请先生成安装包。"; return }
        busy = true
        defer { busy = false }
        do {
            if let result = try services.receiveTargetResult(enrollmentId: record.id) {
                try finalize(result: result, record: record)
                return
            }
            guard let ip = try services.findTargetIPv4(alias: record.targetAlias) else {
                status = "尚未发现目标机；保持 Windows 完成页打开后重试。"
                return
            }
            targetIPv4 = ip
            guard !windowsUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                status = "已发现 \(ip)，但还没收到 Taildrop 结果。可重试或手动导入 desk2shell-result.json。"
                return
            }
            status = "已发现目标，但没有可验证的主机指纹。请导入 Windows 生成的 desk2shell-result.json。"
        } catch {
            status = error.localizedDescription
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
                if self.status.hasPrefix("连接成功") { return }
            }
        }
    }

    func importResult() {
        guard let record else { status = "请先生成安装包。"; return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try finalize(result: services.readTargetResult(url: url, enrollmentId: record.id), record: record)
        } catch {
            status = error.localizedDescription
        }
    }

    private func finalize(result: TargetResult, record: EnrollmentRecord) throws {
        guard result.targetAlias == record.targetAlias else {
            throw Desk2ShellError.commandFailed("结果文件中的目标名与当前 enrollment 不匹配。")
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
        status = "连接成功：\(identity)。现在可使用 ssh \(record.targetAlias)。"
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
        status = "SSH 命令已复制。"
    }
}
