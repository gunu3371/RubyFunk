// This client's persistent punktfunk/1 identity: a self-signed certificate + key (PEM),
// generated once and stored in the data-protection Keychain, this-device-only (with a legacy
// file-keychain fallback for unsigned builds — see `query(dataProtection:)`). The certificate's
// fingerprint is how hosts recognize this client after PIN pairing — losing the key un-pairs this
// Mac from every host, so the pair is presented on every connect but never regenerated once
// stored (and never leaves this device: see `add`). That invariant drives the error handling
// below: a Keychain that *refuses access* (locked, ACL denied) is an error, not a first run —
// minting a replacement would silently shadow the durable identity and break every existing
// pairing.

import Foundation
import RubyFunkKit
import Security

final class ClientIdentityStore: @unchecked Sendable {
    static let shared = ClientIdentityStore()

    enum IdentityError: Error {
        /// The Keychain refused access (locked, ACL denied, …) — an identity may exist.
        case keychain(OSStatus)
        /// The identity lives only in memory (Keychain write failed); good enough to
        /// present on a connect, not good enough to pair against.
        case notPersisted
    }

    private let lock = NSLock()
    private var cached: (identity: ClientIdentity, persisted: Bool)?

    /// The identity to present when connecting, generating + persisting it on first run.
    /// `persisted == false` means the Keychain write failed and it lives only in memory —
    /// fine for a session, see `loadForPairing()` for the strict variant. Blocking
    /// (Keychain + key generation) — call off the main actor.
    func load() throws -> (identity: ClientIdentity, persisted: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }

        switch copyStored() {
        case .found(let identity):
            let hit = (identity, true)
            cached = hit
            return hit
        case .absent:
            break // genuine first run — mint below
        case .corrupt:
            // Our own item, undecodable: the pairings it backed are unusable either
            // way, so deliberately self-heal by replacing it (both keychains, best-effort).
            SecItemDelete(Self.query(dataProtection: true) as CFDictionary)
            SecItemDelete(Self.query(dataProtection: false) as CFDictionary)
        case .denied(let status):
            throw IdentityError.keychain(status)
        }

        let fresh = try generateIdentity()
        let entry: (ClientIdentity, Bool)
        switch add(fresh) {
        case errSecSuccess:
            entry = (fresh, true)
        case errSecDuplicateItem:
            // Lost a first-run race with another instance — the stored identity is the
            // durable one, never overwrite it.
            if case .found(let identity) = copyStored() {
                entry = (identity, true)
            } else {
                entry = (fresh, false)
            }
        default:
            entry = (fresh, false)
        }
        cached = entry
        return entry
    }

    /// Pairing variant: the host is about to durably trust this identity, so it must be
    /// durable on our side too — a memory-only identity would evaporate on relaunch and
    /// strand the pairing.
    func loadForPairing() throws -> ClientIdentity {
        let (identity, persisted) = try load()
        guard persisted else { throw IdentityError.notPersisted }
        return identity
    }

    private struct Stored: Codable {
        var certPEM: String
        var keyPEM: String
    }

    private enum ReadResult {
        case found(ClientIdentity)
        case absent
        case corrupt
        case denied(OSStatus)
    }

    /// Local ad-hoc builds use a separate login-keychain item. Distribution builds use
    /// the data-protection keychain, with a legacy fallback when its entitlement is absent.
    private static func query(dataProtection: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.github.gunu3371.rubyfunk",
            kSecAttrAccount as String: "client-identity",
        ]
        #if RUBYFUNK_LOCAL_KEYCHAIN
        q[kSecAttrService as String] = "io.github.gunu3371.rubyfunk.local"
        q[kSecUseDataProtectionKeychain as String] = false
        #else
        q[kSecUseDataProtectionKeychain as String] = dataProtection
        #endif
        return q
    }

    private func copyStored() -> ReadResult {
        let result = read(dataProtection: true)
        // No entitlement (ad-hoc / unsigned build): the data-protection keychain is
        // unavailable — read the legacy file keychain instead.
        if case .denied(errSecMissingEntitlement) = result {
            return read(dataProtection: false)
        }
        #if !RUBYFUNK_LOCAL_KEYCHAIN
        // Reapply device-only accessibility without replacing the paired identity.
        if case .found = result {
            SecItemUpdate(
                Self.query(dataProtection: true) as CFDictionary,
                [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
                    as CFDictionary)
        }
        #endif
        return result
    }

    private func read(dataProtection: Bool) -> ReadResult {
        var query = Self.query(dataProtection: dataProtection)
        query[kSecReturnData as String] = true
        var out: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &out) {
        case errSecSuccess:
            guard let data = out as? Data,
                  let stored = try? JSONDecoder().decode(Stored.self, from: data)
            else { return .corrupt }
            return .found(ClientIdentity(certPEM: stored.certPEM, keyPEM: stored.keyPEM))
        case errSecItemNotFound:
            return .absent
        case let status:
            return .denied(status)
        }
    }

    private func add(_ identity: ClientIdentity) -> OSStatus {
        guard let data = try? JSONEncoder().encode(
            Stored(certPEM: identity.certPEM, keyPEM: identity.keyPEM))
        else { return errSecParam }
        var add = Self.query(dataProtection: true)
        add[kSecValueData as String] = data
        // Background reconnects need access after unlock. Distribution credentials stay
        // on this device; login-keychain builds use that keychain's access controls.
        #if !RUBYFUNK_LOCAL_KEYCHAIN
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecMissingEntitlement else { return status }
        // Ad-hoc / unsigned build: persist to the legacy file keychain instead.
        var legacy = Self.query(dataProtection: false)
        legacy[kSecValueData as String] = data
        return SecItemAdd(legacy as CFDictionary, nil)
    }
}

extension MgmtTarget {
    /// `host`'s management API as this device's stored identity. Blocking Keychain work on the
    /// first load; the app warms both halves at launch.
    static func make(host: StoredHost, port: UInt16? = nil) -> Result<MgmtTarget, MgmtTargetMissing> {
        make(host: host, port: port, identity: (try? ClientIdentityStore.shared.load())?.identity)
    }
}
