import CryptoKit
import Foundation

enum EnrollmentCrypto {
    static let schemaVersion = 1
    static let aadPrefix = "Desk2Shell.Enrollment.v1:"

    static func seal(payload: EnrollmentPayload, keyData: Data, createdAt: String) throws -> EnrollmentEnvelope {
        guard keyData.count == 32 else { throw Desk2ShellError.invalidPairingCode }
        let encoded = try JSONEncoder.desk2Shell.encode(payload)
        let nonce = AES.GCM.Nonce()
        let aad = Data((aadPrefix + payload.enrollmentId).utf8)
        let sealed = try AES.GCM.seal(
            encoded,
            using: SymmetricKey(data: keyData),
            nonce: nonce,
            authenticating: aad
        )
        return EnrollmentEnvelope(
            schemaVersion: schemaVersion,
            enrollmentId: payload.enrollmentId,
            createdAt: createdAt,
            nonce: Data(nonce).base64EncodedString(),
            ciphertext: sealed.ciphertext.base64EncodedString(),
            tag: sealed.tag.base64EncodedString()
        )
    }

    static func open(envelope: EnrollmentEnvelope, pairingCode: String) throws -> EnrollmentPayload {
        let keyData = try decodePairingCode(pairingCode)
        guard envelope.schemaVersion == schemaVersion,
              let nonceData = Data(base64Encoded: envelope.nonce),
              let ciphertext = Data(base64Encoded: envelope.ciphertext),
              let tag = Data(base64Encoded: envelope.tag),
              nonceData.count == 12,
              tag.count == 16
        else { throw Desk2ShellError.invalidEnvelope }

        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonceData),
            ciphertext: ciphertext,
            tag: tag
        )
        let cleartext = try AES.GCM.open(
            box,
            using: SymmetricKey(data: keyData),
            authenticating: Data((aadPrefix + envelope.enrollmentId).utf8)
        )
        let payload = try JSONDecoder.desk2Shell.decode(EnrollmentPayload.self, from: cleartext)
        guard payload.enrollmentId == envelope.enrollmentId,
              payload.schemaVersion == schemaVersion
        else { throw Desk2ShellError.invalidEnvelope }
        return payload
    }

    static func makePairingCode() throws -> (key: Data, display: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw Desk2ShellError.commandFailed("无法生成安全随机配对码。")
        }
        let compact = bytes.map { String(format: "%02X", $0) }.joined()
        let grouped = stride(from: 0, to: compact.count, by: 8).map { offset -> String in
            let start = compact.index(compact.startIndex, offsetBy: offset)
            let end = compact.index(start, offsetBy: min(8, compact.count - offset))
            return String(compact[start..<end])
        }.joined(separator: "-")
        return (Data(bytes), grouped)
    }

    static func decodePairingCode(_ value: String) throws -> Data {
        let compact = value.filter { $0.isHexDigit }
        guard compact.count == 64 else { throw Desk2ShellError.invalidPairingCode }
        var bytes = [UInt8]()
        bytes.reserveCapacity(32)
        var index = compact.startIndex
        for _ in 0..<32 {
            let next = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index..<next], radix: 16) else {
                throw Desk2ShellError.invalidPairingCode
            }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }
}

extension JSONEncoder {
    static var desk2Shell: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    static var desk2Shell: JSONDecoder { JSONDecoder() }
}
