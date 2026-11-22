import Foundation
import MtProtoKit

//fix: per-account server binding for the BaiGram deployment

public struct BaigramServerConfig {
    public static let datacenterId: Int = 2
    public static let defaultServerId = "baigram"

    public let id: String
    public let name: String
    public let ip: String
    public let port: Int
    public let pubkey: String

    public init(id: String, name: String, ip: String, port: Int, pubkey: String) {
        self.id = id
        self.name = name
        self.ip = ip
        self.port = port
        self.pubkey = pubkey
    }

    public var isValid: Bool {
        return !self.id.isEmpty && !self.ip.isEmpty && self.port > 0 && self.port <= 65535
    }

    public var hasPublicKey: Bool {
        return !self.pubkey.isEmpty && self.pubkey != "NULL"
    }

    public var displayName: String {
        if !self.name.isEmpty {
            return self.name
        }
        if !self.id.isEmpty {
            return self.id
        }
        return "Default"
    }

    //fix: identity of the endpoint the stored auth keys were made against
    public var fingerprint: String {
        return "\(self.id)|\(self.ip)|\(self.port)|\(self.pubkey)"
    }

    // Builtin copy of the "baigram" entry served by Server_Worker. The normal
    // path fetches it over HTTPS; this keeps first launch working when the
    // worker is unreachable.
    private static let builtinPublicKey = """
    -----BEGIN RSA PUBLIC KEY-----
    MIIBCgKCAQEAyvtCrgb/pUx09Bn4QHy1Fsz3F5EZe24GcjY8KziFzjhTOAkkDHeM
    aSBsCfiIChgzU9oJEWP2FPaFa4K2iiRbZNb1SktmA4w4FdNO/uIqo4i1emTrZT6l
    pC7sHED+ZKO8Iessoqt3NBE5oApuKbvtRvNRA+xn6EzvdupYzTIrghgaR+CzK1Cs
    63TK3uwCG+xWwfdK3U95cAB8U1bFeeE0gWguMT+zcYxFcWQCBxW/BYg2Piuuztie
    FJO7wFe6cuX4CaVlTorWet5/JlKzJz3MFGHRQHgRk1bixzFmc4z99UWG6G5Vpxhs
    TOlMx6qlFl8TNLPSEaSBPMp5gP1jnAtOtwIDAQAB
    -----END RSA PUBLIC KEY-----
    """

    public static func builtin(id: String) -> BaigramServerConfig? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() != self.defaultServerId {
            return nil
        }
        return BaigramServerConfig(id: self.defaultServerId, name: "Baigram", ip: "192.168.1.19", port: 9442, pubkey: self.builtinPublicKey)
    }

    private static var defaults: UserDefaults {
        return UserDefaults.standard
    }

    private static func savedKey(accountId: AccountRecordId) -> String {
        return "baigram.server.\(accountId.int64)"
    }

    private static func appliedKey(accountId: AccountRecordId) -> String {
        return "baigram.server.\(accountId.int64).applied"
    }

    public static func saved(accountId: AccountRecordId) -> BaigramServerConfig? {
        guard let data = self.defaults.data(forKey: self.savedKey(accountId: accountId)), let object = try? JSONSerialization.jsonObject(with: data), let dict = object as? [String: Any] else {
            return nil
        }
        let config = BaigramServerConfig(
            id: dict["id"] as? String ?? "",
            name: dict["name"] as? String ?? "",
            ip: dict["ip"] as? String ?? "",
            port: dict["port"] as? Int ?? 0,
            pubkey: dict["pubkey"] as? String ?? ""
        )
        return config.isValid ? config : nil
    }

    public static func current(accountId: AccountRecordId) -> BaigramServerConfig {
        if let saved = self.saved(accountId: accountId) {
            return saved
        }
        //fix: fresh install defaults to the built-in server, no forced selection
        if let builtin = self.builtin(id: self.defaultServerId) {
            return builtin
        }
        return BaigramServerConfig(id: self.defaultServerId, name: "Baigram", ip: "127.0.0.1", port: 9442, pubkey: "")
    }

    public static func save(_ config: BaigramServerConfig, accountId: AccountRecordId) {
        let dict: [String: Any] = [
            "id": config.id,
            "name": config.name,
            "ip": config.ip,
            "port": config.port,
            "pubkey": config.pubkey
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            self.defaults.set(data, forKey: self.savedKey(accountId: accountId))
        }
    }

    public static func clear(accountId: AccountRecordId) {
        self.defaults.removeObject(forKey: self.savedKey(accountId: accountId))
        self.defaults.removeObject(forKey: self.appliedKey(accountId: accountId))
    }

    public static func appliedFingerprint(accountId: AccountRecordId) -> String? {
        return self.defaults.string(forKey: self.appliedKey(accountId: accountId))
    }

    public static func markApplied(_ config: BaigramServerConfig, accountId: AccountRecordId) {
        self.defaults.set(config.fingerprint, forKey: self.appliedKey(accountId: accountId))
    }

    //fix: keys made against another endpoint must not be reused
    public static func shouldResetAuthKeys(for config: BaigramServerConfig, accountId: AccountRecordId) -> Bool {
        guard let previous = self.appliedFingerprint(accountId: accountId) else {
            return false
        }
        return previous != config.fingerprint
    }

    // Rebind the live network to a new endpoint. Used by the login screen after
    // the user picks a server, which happens before any auth key exists.
    public static func apply(_ config: BaigramServerConfig, to network: Network, accountId: AccountRecordId) {
        if !config.isValid {
            return
        }
        let dcId = self.datacenterId
        let address = MTDatacenterAddress(ip: config.ip, port: UInt16(config.port), preferForMedia: false, restrictToTcp: false, cdn: false, preferForProxy: false, secret: nil)
        network.context.updateAddressSetForDatacenter(withId: dcId, addressSet: MTDatacenterAddressSet(addressList: [address]), forceUpdateSchemes: true)
        if config.hasPublicKey {
            let publicKeys: [[AnyHashable: Any]] = [["key": config.pubkey]]
            network.context.updatePublicKeysForDatacenterWithId(dcId, publicKeys: publicKeys)
        }
        network.context.updateAuthInfoForDatacenter(withId: dcId, authInfo: nil, selector: .persistent)
        network.context.updateAuthInfoForDatacenter(withId: dcId, authInfo: nil, selector: .ephemeralMain)
        network.context.updateAuthInfoForDatacenter(withId: dcId, authInfo: nil, selector: .ephemeralMedia)
        self.save(config, accountId: accountId)
        self.markApplied(config, accountId: accountId)
    }
}
