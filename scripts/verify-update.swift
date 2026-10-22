import CryptoKit
import Foundation

struct Input: Decodable {
    let publicKey: String
    let checks: [Check]
    struct Check: Decodable { let path: String; let signature: String }
}
let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: input.publicKey)!)
for check in input.checks {
    let data = try Data(contentsOf: URL(fileURLWithPath: check.path))
    guard let signature = Data(base64Encoded: check.signature), key.isValidSignature(signature, for: data) else {
        fputs("Update signature verification failed.\n", stderr)
        exit(1)
    }
}
