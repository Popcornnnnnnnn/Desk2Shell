import AppKit
import Foundation

final class ControllerServices {
    private let fileManager = FileManager.default

    var applicationSupport: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Desk2Shell", isDirectory: true)
    }

    func tailscaleSnapshot() throws -> TailscaleSnapshot {
        let cli = try tailscaleCLI()
        let ip = try ProcessRunner.checked(cli, ["ip", "-4"])
            .split(whereSeparator: \Character.isWhitespace).first.map(String.init) ?? ""
        guard Self.validIPv4(ip) else {
            throw Desk2ShellError.tailscaleUnavailable(BilingualText("没有活动的 IPv4 地址", "no active IPv4 address"))
        }

        let statusText = try ProcessRunner.checked(cli, ["status", "--json"])
        guard let data = statusText.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let selfNode = json["Self"] as? [String: Any]
        else { throw Desk2ShellError.tailscaleUnavailable(BilingualText("无法读取状态", "unable to read status")) }

        let nodeName = (selfNode["HostName"] as? String)
            ?? (selfNode["DNSName"] as? String)?.split(separator: ".").first.map(String.init)
            ?? ""
        let tailnet = (json["CurrentTailnet"] as? [String: Any])?["Name"] as? String ?? ""
        guard !nodeName.isEmpty, !tailnet.isEmpty else {
            throw Desk2ShellError.tailscaleUnavailable(BilingualText("无法识别当前 tailnet", "unable to identify the current tailnet"))
        }
        return TailscaleSnapshot(controllerIPv4: ip, controllerNodeName: nodeName, tailnetName: tailnet)
    }

    func createKey(enrollmentId: String) throws -> (privateKey: URL, publicKey: String) {
        let keyDirectory = applicationSupport.appendingPathComponent("keys", isDirectory: true)
        try fileManager.createDirectory(at: keyDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let privateKey = keyDirectory.appendingPathComponent(enrollmentId)

        var passphraseBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, passphraseBytes.count, &passphraseBytes) == errSecSuccess else {
            throw Desk2ShellError.commandFailed(BilingualText("无法生成 SSH 密钥口令。", "Unable to generate the SSH key passphrase."))
        }
        let passphrase = Data(passphraseBytes).base64EncodedString()
        try KeychainStore.save(Data(passphrase.utf8), account: enrollmentId)

        let askpass = try askpassURL()
        let result = try ProcessRunner.run("/usr/bin/ssh-keygen", [
            "-q", "-t", "ed25519", "-a", "64",
            "-C", "desk2shell:\(enrollmentId)",
            "-f", privateKey.path
        ], environment: [
            "SSH_ASKPASS": askpass.path,
            "SSH_ASKPASS_REQUIRE": "force",
            "DISPLAY": "desk2shell",
            "DESK2SHELL_KEY_PASSPHRASE": passphrase
        ])
        guard result.exitCode == 0 else {
            try? fileManager.removeItem(at: privateKey)
            throw Desk2ShellError.commandFailed(BilingualText(
                "SSH 密钥生成失败：\(result.stderr)",
                "SSH key generation failed: \(result.stderr)"
            ))
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateKey.path)
        let publicKey = try String(contentsOf: privateKey.appendingPathExtension("pub"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (privateKey, publicKey)
    }

    func exportPackage(envelope: EnrollmentEnvelope, alias: String, destination: URL) throws {
        guard let resources = Bundle.module.resourceURL?.appendingPathComponent("Resources", isDirectory: true),
              let bootstrap = [
                resources.appendingPathComponent("Desk2Shell Bootstrap.exe"),
                resources.appendingPathComponent("Desk2Shell.Bootstrap.exe")
              ].first(where: { fileManager.fileExists(atPath: $0.path) })
        else { throw Desk2ShellError.bootstrapMissing }

        let temporary = fileManager.temporaryDirectory.appendingPathComponent("desk2shell-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporary) }
        let folder = temporary.appendingPathComponent("Desk2Shell-\(alias)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try fileManager.copyItem(at: bootstrap, to: folder.appendingPathComponent("Desk2Shell Bootstrap.exe"))
        let enrollmentURL = folder.appendingPathComponent("\(alias).d2s")
        try JSONEncoder.desk2Shell.encode(envelope).write(to: enrollmentURL, options: .atomic)
        let instructions = """
        Desk2Shell setup

        1. Keep the remote-desktop session connected.
        2. Run Desk2Shell Bootstrap.exe.
        3. Choose \(alias).d2s when prompted.
        4. Paste the separate pairing code from the Mac.
        5. Keep the final result window open until the Mac verifies SSH.
        """
        try Data(instructions.utf8).write(to: folder.appendingPathComponent("README.txt"), options: .atomic)
        let result = try ProcessRunner.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, destination.path])
        guard result.exitCode == 0 else {
            throw Desk2ShellError.commandFailed(BilingualText(
                "无法创建 ZIP：\(result.stderr)",
                "Unable to create the ZIP: \(result.stderr)"
            ))
        }
    }

    func store(record: EnrollmentRecord) throws {
        try fileManager.createDirectory(at: applicationSupport, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = applicationSupport.appendingPathComponent("enrollments.json")
        var records = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder.desk2Shell.decode([EnrollmentRecord].self, from: $0) } ?? []
        records.removeAll { $0.id == record.id || $0.targetAlias == record.targetAlias }
        records.append(record)
        try JSONEncoder.desk2Shell.encode(records).write(to: url, options: [.atomic, .completeFileProtection])
    }

    func installSSHConfig(alias: String, host: String, user: String, keyPath: String) throws {
        guard Self.validAlias(alias), Self.validIPv4(host), !user.isEmpty else {
            throw Desk2ShellError.commandFailed(BilingualText("SSH 配置参数无效。", "The SSH configuration parameters are invalid."))
        }
        let sshDirectory = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".ssh", isDirectory: true)
        try fileManager.createDirectory(at: sshDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let configURL = sshDirectory.appendingPathComponent("config")
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let begin = "# BEGIN DESK2SHELL \(alias)"
        let end = "# END DESK2SHELL \(alias)"
        var stripped = existing
        if let start = stripped.range(of: begin),
           let finish = stripped.range(of: end, range: start.upperBound..<stripped.endIndex) {
            stripped.removeSubrange(start.lowerBound..<finish.upperBound)
        }
        let block = """
        \(begin)
        Host \(alias)
          HostName \(host)
          User \(user)
          Port 2222
          IdentityFile \(keyPath)
          IdentitiesOnly yes
          AddKeysToAgent yes
          UseKeychain yes
        \(end)
        """
        let joined = stripped.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + block + "\n"
        try Data(joined.utf8).write(to: configURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    func findTargetIPv4(alias: String) throws -> String? {
        let statusText = try ProcessRunner.checked(try tailscaleCLI(), ["status", "--json"])
        guard let data = statusText.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let peers = json["Peer"] as? [String: [String: Any]] else { return nil }
        for peer in peers.values {
            let host = (peer["HostName"] as? String) ?? ""
            let dns = (peer["DNSName"] as? String) ?? ""
            guard host.caseInsensitiveCompare(alias) == .orderedSame || dns.lowercased().hasPrefix(alias.lowercased() + ".") else { continue }
            let addresses = peer["TailscaleIPs"] as? [String] ?? []
            return addresses.first(where: Self.validIPv4)
        }
        return nil
    }

    func verifySSH(alias: String, expectedUser: String) throws -> String {
        let output = try ProcessRunner.checked("/usr/bin/ssh", [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-o", "StrictHostKeyChecking=yes",
            alias,
            "whoami"
        ])
        guard output.lowercased().hasSuffix(expectedUser.lowercased()) else {
            throw Desk2ShellError.commandFailed(BilingualText(
                "SSH 已连接，但远端身份为 \(output)，不是 \(expectedUser)。",
                "SSH connected, but the remote identity is \(output), not \(expectedUser)."
            ))
        }
        return output
    }

    func receiveTargetResult(enrollmentId: String) throws -> TargetResult? {
        let incoming = applicationSupport.appendingPathComponent("incoming", isDirectory: true)
        try fileManager.createDirectory(at: incoming, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        _ = try ProcessRunner.run(try tailscaleCLI(), ["file", "get", "--conflict=rename", incoming.path])
        let files = try fileManager.contentsOfDirectory(at: incoming, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let result = try? JSONDecoder.desk2Shell.decode(TargetResult.self, from: data),
                  result.enrollmentId == enrollmentId else { continue }
            return result
        }
        return nil
    }

    func readTargetResult(url: URL, enrollmentId: String) throws -> TargetResult {
        let result = try JSONDecoder.desk2Shell.decode(TargetResult.self, from: Data(contentsOf: url))
        guard result.schemaVersion == 1, result.enrollmentId == enrollmentId,
              result.sshPort == 2222, Self.validIPv4(result.tailscaleIPv4),
              !result.windowsUser.isEmpty else {
            throw Desk2ShellError.commandFailed(BilingualText(
                "Windows 结果文件与当前 enrollment 不匹配。",
                "The Windows result file does not match the current enrollment."
            ))
        }
        return result
    }

    func pinHostKey(host: String, port: Int, expectedFingerprint: String) throws {
        let scan = try ProcessRunner.checked("/usr/bin/ssh-keyscan", ["-T", "8", "-p", String(port), "-t", "ed25519", host])
        guard !scan.isEmpty else {
            throw Desk2ShellError.commandFailed(BilingualText(
                "目标 SSH 服务没有返回主机密钥。",
                "The target SSH service did not return a host key."
            ))
        }
        let temporary = fileManager.temporaryDirectory.appendingPathComponent("desk2shell-host-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporary) }
        try Data((scan + "\n").utf8).write(to: temporary, options: .atomic)
        let detail = try ProcessRunner.checked("/usr/bin/ssh-keygen", ["-lf", temporary.path, "-E", "sha256"])
        let actual = detail.split(whereSeparator: \Character.isWhitespace).dropFirst().first.map(String.init) ?? ""
        guard actual == expectedFingerprint else {
            throw Desk2ShellError.commandFailed(BilingualText(
                "目标主机密钥不匹配；未写入 known_hosts。",
                "The target host key does not match; known_hosts was not modified."
            ))
        }

        let sshDirectory = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".ssh", isDirectory: true)
        try fileManager.createDirectory(at: sshDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let knownHosts = sshDirectory.appendingPathComponent("known_hosts")
        var existing = (try? String(contentsOf: knownHosts, encoding: .utf8)) ?? ""
        let prefix = "[\(host)]:\(port) "
        if !existing.split(separator: "\n").contains(where: { $0.hasPrefix(prefix) }) {
            if !existing.isEmpty && !existing.hasSuffix("\n") { existing += "\n" }
            existing += scan + "\n"
            try Data(existing.utf8).write(to: knownHosts, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: knownHosts.path)
        }
    }

    func loadKeyIntoAgent(enrollmentId: String, keyPath: String) throws {
        let passphraseData = try KeychainStore.load(account: enrollmentId)
        guard let passphrase = String(data: passphraseData, encoding: .utf8) else {
            throw Desk2ShellError.commandFailed(BilingualText(
                "无法准备 SSH Keychain 凭据。",
                "Unable to prepare the SSH Keychain credential."
            ))
        }
        let askpass = try askpassURL()
        let result = try ProcessRunner.run(
            "/usr/bin/ssh-add",
            ["--apple-use-keychain", keyPath],
            environment: [
                "SSH_ASKPASS": askpass.path,
                "SSH_ASKPASS_REQUIRE": "force",
                "DISPLAY": "desk2shell",
                "DESK2SHELL_KEY_PASSPHRASE": passphrase
            ]
        )
        guard result.exitCode == 0 else {
            throw Desk2ShellError.commandFailed(BilingualText(
                "无法把设备密钥载入 ssh-agent：\(result.stderr)",
                "Unable to load the device key into ssh-agent: \(result.stderr)"
            ))
        }
    }

    static func validAlias(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$"#, options: .regularExpression) != nil
    }

    static func validIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }

    private func tailscaleCLI() throws -> String {
        let candidates = [
            "/usr/local/bin/tailscale",
            "/opt/homebrew/bin/tailscale",
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
        ]
        guard let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            throw Desk2ShellError.tailscaleUnavailable(BilingualText("未找到 Tailscale CLI", "Tailscale CLI was not found"))
        }
        return path
    }

    private func askpassURL() throws -> URL {
        guard let url = Bundle.module.resourceURL?
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("desk2shell-askpass.sh"),
              fileManager.fileExists(atPath: url.path) else {
            throw Desk2ShellError.commandFailed(BilingualText(
                "Desk2Shell askpass helper 缺失。",
                "The Desk2Shell askpass helper is missing."
            ))
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
