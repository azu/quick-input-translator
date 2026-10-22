import CryptoKit
import Foundation

// Sparkle accepts the base64-encoded 32-byte Ed25519 seed. Keep the private
// material in a file rather than in argv, stdout, or the login Keychain.
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
try key.publicKey.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
