import Foundation
import Security
import CryptoKit

public protocol CredentialVault: Sendable {
    func read(_ id: String) throws -> Data?
    func write(_ value: Data, id: String) throws
    func delete(_ id: String) throws
}

public struct KeychainVault: CredentialVault {
    private let service: String
    public init(service: String = "agency.ziplyne.grove.credentials") { self.service = service }
    public static let usesDataProtection: Bool = {
        var code: SecCode?, staticCode: SecStaticCode?, information: CFDictionary?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code,
           SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
           SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
           let info = information as? [String: Any],
           let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
           entitlements["com.apple.application-identifier"] is String {
            return true
        }
        return false
    }()
    private var baseQuery: [CFString: Any] {
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service]
        if Self.usesDataProtection { query[kSecUseDataProtectionKeychain] = true }
        return query
    }
    public func read(_ id: String) throws -> Data? {
        var query = baseQuery
        query[kSecAttrAccount] = id; query[kSecReturnData] = true; query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw WorkspaceError.keychain }
        return data
    }
    public func write(_ value: Data, id: String) throws {
        var query = baseQuery; query[kSecAttrAccount] = id
        let changes = [kSecValueData: value] as CFDictionary
        let status = SecItemUpdate(query as CFDictionary, changes)
        if status == errSecItemNotFound {
            query[kSecValueData] = value; query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            query[kSecAttrSynchronizable] = false
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw WorkspaceError.keychain }
        } else if status != errSecSuccess { throw WorkspaceError.keychain }
    }
    public func delete(_ id: String) throws {
        var query = baseQuery; query[kSecAttrAccount] = id
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw WorkspaceError.keychain }
    }
}

public actor WorkspacePersistence {
    private let url: URL
    private let vault: any CredentialVault
    private let keyID = "workspace-encryption-v1"
    public init(url: URL? = nil, vault: any CredentialVault = KeychainVault()) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(KeychainVault.usesDataProtection ? "Grove/workspace.enc" : "Grove/workspace-development.enc")
        self.vault = vault
    }
    public func load() throws -> WorkspaceArchive {
        guard FileManager.default.fileExists(atPath: url.path) else { return WorkspaceArchive() }
        guard let stored = try vault.read(keyID) else { throw WorkspaceError.corruptArchive }
        do {
            let box = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
            let data = try AES.GCM.open(box, using: SymmetricKey(data: stored))
            struct Header: Decodable { let version: Int }
            guard try JSONDecoder().decode(Header.self, from: data).version == 1 else { throw WorkspaceError.archiveVersion }
            let archive = try JSONDecoder().decode(WorkspaceArchive.self, from: data)
            return archive
        } catch let error as WorkspaceError { throw error }
        catch { throw WorkspaceError.corruptArchive }
    }
    public func save(_ archive: WorkspaceArchive) throws {
        guard archive.version == 1 else { throw WorkspaceError.archiveVersion }
        let key: SymmetricKey
        if let data = try vault.read(keyID) { key = SymmetricKey(data: data) }
        else {
            key = SymmetricKey(size: .bits256)
            try vault.write(key.withUnsafeBytes { Data($0) }, id: keyID)
        }
        let data = try JSONEncoder().encode(archive)
        let encrypted = try AES.GCM.seal(data, using: key)
        guard let combined = encrypted.combined else { throw WorkspaceError.corruptArchive }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try combined.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
