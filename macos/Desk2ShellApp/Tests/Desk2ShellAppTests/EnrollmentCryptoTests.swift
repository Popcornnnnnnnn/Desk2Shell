import Foundation
import Testing
@testable import Desk2ShellApp

@Test func enrollmentRoundTripAndTamperDetection() throws {
    let id = "11111111-2222-3333-4444-555555555555"
    let payload = EnrollmentPayload(
        schemaVersion: 1,
        enrollmentId: id,
        targetAlias: "lab-win",
        controllerPublicKey: "ssh-ed25519 AAAAC3NzaTest desk2shell:test",
        controllerTailscaleIPv4: "100.64.10.20",
        controllerNodeName: "controller",
        tailnetName: "example.ts.net",
        createdAt: "2026-09-08T00:00:00.000Z",
        expiresAt: "2026-09-09T00:00:00.000Z",
        tailscaleAuthKey: "tskey-auth-test"
    )
    let key = Data(0..<32)
    let envelope = try EnrollmentCrypto.seal(payload: payload, keyData: key, createdAt: payload.createdAt)
    let transport = try JSONEncoder.desk2Shell.encode(envelope)
    #expect(!String(decoding: transport, as: UTF8.self).contains(payload.tailscaleAuthKey))
    let code = key.map { String(format: "%02X", $0) }.joined()
    #expect(try EnrollmentCrypto.open(envelope: envelope, pairingCode: code) == payload)

    let damaged = EnrollmentEnvelope(
        schemaVersion: envelope.schemaVersion,
        enrollmentId: UUID().uuidString,
        createdAt: envelope.createdAt,
        nonce: envelope.nonce,
        ciphertext: envelope.ciphertext,
        tag: envelope.tag
    )
    #expect(throws: (any Error).self) {
        try EnrollmentCrypto.open(envelope: damaged, pairingCode: code)
    }
}

@Test func validatesAliasesAndIPv4() {
    #expect(ControllerServices.validAlias("lab-win-01"))
    #expect(!ControllerServices.validAlias("bad name"))
    #expect(!ControllerServices.validAlias("-bad"))
    #expect(ControllerServices.validIPv4("100.64.10.20"))
    #expect(!ControllerServices.validIPv4("999.64.10.20"))
}
