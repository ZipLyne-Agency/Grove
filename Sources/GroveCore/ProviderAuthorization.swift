import Foundation
import Security
import CryptoKit

public actor ProviderAuthorizer {
    private struct Token { let value: String; let expires: Date }
    private var tokens: [String: Token] = [:]
    private let transport: any ProviderTransport
    public init(transport: any ProviderTransport = ProviderHTTP()) { self.transport = transport }
    public func invalidate(_ id: UUID) { tokens = tokens.filter { !$0.key.hasPrefix(id.uuidString + ":") } }
    public func bearer(account: ProviderAccount, credential: Data) async throws -> String {
        guard credential.count <= 100_000, let text = String(data: credential, encoding: .utf8), !text.isEmpty else { throw WorkspaceError.missingCredential }
        switch account.provider {
        case .searchConsole, .analytics, .googlePlay:
            let cacheKey = account.id.uuidString + ":" + account.provider.rawValue + ":" + (account.googleSubject ?? "") + ":" + SHA256.hash(data: credential).description
            if let cached = tokens[cacheKey], cached.expires.timeIntervalSinceNow > 120 { return cached.value }
            let token = try await google(account: account, credential: credential)
            tokens[cacheKey] = token; return token.value
        case .appStore: return try apple(credential)
        default:
            let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.contains(where: { $0.isWhitespace }), token.count <= 10_000 else { throw WorkspaceError.invalidInput("Enter the API token without spaces.") }
            return token
        }
    }
    private struct GoogleCredential: Decodable {
        let client_id: String?
        let client_secret: String?
        let refresh_token: String?
        let client_email: String?
        let private_key: String?
    }
    private func google(account: ProviderAccount, credential: Data) async throws -> Token {
        guard let key = try? JSONDecoder().decode(GoogleCredential.self, from: credential) else {
            throw WorkspaceError.invalidInput("Enter valid Google OAuth or service account credentials JSON.")
        }
        var fields: [String: String]
        if let refresh = key.refresh_token, let clientID = key.client_id, let secret = key.client_secret {
            fields = ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID, "client_secret": secret]
        } else if let email = key.client_email, let pem = key.private_key {
            let scope: String
            switch account.provider {
            case .searchConsole: scope = "https://www.googleapis.com/auth/webmasters.readonly"
            case .analytics: scope = "https://www.googleapis.com/auth/analytics.readonly"
            case .googlePlay: scope = "https://www.googleapis.com/auth/androidpublisher"
            default: throw WorkspaceError.unsupported
            }
            var claims: [String: String] = ["iss": email, "scope": scope, "aud": "https://oauth2.googleapis.com/token"]
            if let subject = account.googleSubject, !subject.isEmpty { claims["sub"] = subject }
            let assertion = try JWT.rsa(pem: pem, claims: claims)
            fields = ["grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion]
        } else { throw WorkspaceError.invalidInput("Google credentials need refresh_token/client_id/client_secret, or client_email/private_key.") }
        var form = URLComponents(); form.queryItems = fields.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        let body = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let url = try ProviderAPI.endpoint("oauth2.googleapis.com", "/token")
        let response = try await transport.send(ProviderRequest(url: url, method: "POST", headers: ["Content-Type": "application/x-www-form-urlencoded"], body: body))
        if response.status == 400 { throw WorkspaceError.authorization }
        let json = try ProviderAPI.json(response)
        return Token(value: try json.requiredString("access_token"), expires: Date().addingTimeInterval(json["expires_in"].number ?? 300))
    }
    private struct AppleCredential: Decodable { let issuer_id: String; let key_id: String; let private_key: String }
    private func apple(_ credential: Data) throws -> String {
        guard let key = try? JSONDecoder().decode(AppleCredential.self, from: credential) else {
            throw WorkspaceError.invalidInput("Enter App Store Connect credentials JSON with issuer_id, key_id, and private_key.")
        }
        return try JWT.apple(pem: key.private_key, issuer: key.issuer_id, keyID: key.key_id)
    }
}

enum JWT {
    private static func base64(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    private struct Claims: Encodable {
        let iss: String; let aud: String; let scope: String?; let sub: String?; let iat: Int; let exp: Int
    }
    static func rsa(pem: String, claims: [String: String]) throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let payload = Claims(iss: claims["iss"] ?? "", aud: claims["aud"] ?? "", scope: claims["scope"], sub: claims["sub"], iat: now, exp: now + 3600)
        let input = base64(try JSONEncoder().encode(["alg": "RS256", "typ": "JWT"])) + "." + base64(try JSONEncoder().encode(payload))
        let raw = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        guard let data = Data(base64Encoded: raw), let der = rsaDER(data) else { throw WorkspaceError.invalidInput("The service account private key could not be read.") }
        let attrs = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate] as CFDictionary
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attrs, &error),
              let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(input.utf8) as CFData, &error) else {
            throw WorkspaceError.invalidInput("The service account private key is not a supported RSA key.")
        }
        return input + "." + base64(signature as Data)
    }
    static func apple(pem: String, issuer: String, keyID: String) throws -> String {
        do {
            let now = Int(Date().timeIntervalSince1970)
            let header = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
            let claims = Claims(iss: issuer, aud: "appstoreconnect-v1", scope: nil, sub: nil, iat: now, exp: now + 900)
            let input = base64(try JSONEncoder().encode(header)) + "." + base64(try JSONEncoder().encode(claims))
            let signature = try P256.Signing.PrivateKey(pemRepresentation: pem).signature(for: Data(input.utf8))
            return input + "." + base64(signature.rawRepresentation)
        } catch { throw WorkspaceError.invalidInput("The App Store Connect signing key could not be read.") }
    }
    /// Extract the RSA octet string from PKCS#8, accepting PKCS#1 as well. Lengths are bounds checked.
    static func rsaDER(_ data: Data) -> Data? {
        let bytes = Array(data)
        func item(_ offset: inout Int) -> (UInt8, Range<Int>)? {
            guard offset + 2 <= bytes.count else { return nil }
            let tag = bytes[offset]; offset += 1
            var length = Int(bytes[offset]); offset += 1
            if length & 128 != 0 {
                let count = length & 127; guard (1...4).contains(count), offset + count <= bytes.count else { return nil }
                length = 0
                for _ in 0..<count { length = length * 256 + Int(bytes[offset]); offset += 1 }
            }
            guard length <= bytes.count - offset else { return nil }
            let range = offset..<(offset + length); offset += length; return (tag, range)
        }
        var offset = 0
        guard let outer = item(&offset), outer.0 == 0x30, offset == bytes.count else { return nil }
        offset = outer.1.lowerBound
        guard let version = item(&offset), version.0 == 0x02, let algorithm = item(&offset) else { return nil }
        if algorithm.0 == 0x02 { return data }
        guard algorithm.0 == 0x30, let key = item(&offset), key.0 == 0x04, key.1.upperBound <= outer.1.upperBound else { return nil }
        return Data(bytes[key.1])
    }
}
