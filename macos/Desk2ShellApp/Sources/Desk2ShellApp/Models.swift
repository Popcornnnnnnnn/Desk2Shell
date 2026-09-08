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
    case tailscaleUnavailable(String)
    case bootstrapMissing
    case commandFailed(String)
    case invalidPairingCode
    case invalidEnvelope

    var errorDescription: String? {
        switch self {
        case .invalidAlias:
            return "设备名只能包含字母、数字和连字符，长度 1–63。"
        case .invalidAuthKey:
            return "请输入一次性 Tailscale Auth Key。"
        case .tailscaleUnavailable(let reason):
            return "Tailscale 尚未就绪：\(reason)"
        case .bootstrapMissing:
            return "缺少 Windows Bootstrap。请先运行 scripts/package-release.sh。"
        case .commandFailed(let message):
            return message
        case .invalidPairingCode:
            return "配对码格式无效。"
        case .invalidEnvelope:
            return "Enrollment 文件无效。"
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
