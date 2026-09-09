import Foundation

struct EnrollmentEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let enrollmentId: String
    let createdAt: String
    let nonce: String
    let ciphertext: String
    let tag: String
}

struct EnrollmentPayload: Codable, Equatable {
    let schemaVersion: Int
    let enrollmentId: String
    let targetAlias: String
    let controllerPublicKey: String
    let controllerTailscaleIPv4: String
    let controllerNodeName: String
    let tailnetName: String
    let createdAt: String
    let expiresAt: String
    let tailscaleAuthKey: String
}

struct EnrollmentRecord: Codable, Identifiable, Equatable {
    let id: String
    let targetAlias: String
    let keyPath: String
    let createdAt: String
    var expiresAt: String
    var targetIPv4: String?
    var windowsUser: String?
}

struct TailscaleSnapshot: Equatable {
    let controllerIPv4: String
    let controllerNodeName: String
    let tailnetName: String
}

struct TargetResult: Codable, Equatable {
    let schemaVersion: Int
    let enrollmentId: String
    let targetAlias: String
    let windowsUser: String
    let tailscaleIPv4: String
    let sshPort: Int
    let hostKeyFingerprint: String
    let expiresAt: String
}

enum Desk2ShellError: LocalizedError {
    case invalidAlias
    case invalidAuthKey
    case tailscaleUnavailable(BilingualText)
    case bootstrapMissing
    case commandFailed(BilingualText)
    case invalidPairingCode
    case invalidEnvelope

    var errorDescription: String? {
        message.value(for: AppLanguage.preferred)
    }

    var message: BilingualText {
        switch self {
        case .invalidAlias:
            return BilingualText(
                "设备名只能包含字母、数字和连字符，长度 1–63。",
                "The device name must be 1–63 characters using only letters, numbers, and hyphens."
            )
        case .invalidAuthKey:
            return BilingualText("请输入一次性 Tailscale Auth Key。", "Enter a one-off Tailscale Auth Key.")
        case .tailscaleUnavailable(let reason):
            return BilingualText(
                "Tailscale 尚未就绪：\(reason.chinese)",
                "Tailscale is not ready: \(reason.english)"
            )
        case .bootstrapMissing:
            return BilingualText(
                "缺少 Windows Bootstrap。请先运行 scripts/package-release.sh。",
                "Windows Bootstrap is missing. Run scripts/package-release.sh first."
            )
        case .commandFailed(let message):
            return message
        case .invalidPairingCode:
            return BilingualText("配对码格式无效。", "The pairing code is invalid.")
        case .invalidEnvelope:
            return BilingualText("Enrollment 文件无效。", "The enrollment file is invalid.")
        }
    }
}

enum DateCodec {
    static func string(_ date: Date) -> String {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return value.string(from: date)
    }
}
