import CryptoKit
import Foundation

// Verify using the public key embedded in the distributed app, independently of the signing key.
do {
    guard CommandLine.arguments.count == 4,
          let publicKeyData = Data(base64Encoded: CommandLine.arguments[1]),
          let signature = Data(base64Encoded: CommandLine.arguments[3]) else {
        throw NSError(domain: "UpdateVerification", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Expected public key, file path and signature"])
    }
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]), options: .mappedIfSafe)
    guard publicKey.isValidSignature(signature, for: data) else {
        throw NSError(domain: "UpdateVerification", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Update signature does not match the bundled public key"])
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
