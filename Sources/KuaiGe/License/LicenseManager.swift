import Foundation
import CryptoKit
import Security
import UIKit

/// 离线授权管理器（专业版激活码）
///
/// 设计：
/// - 激活码 = base64(payloadJson) + "." + base64(ed25519签名)
/// - payload: { "v":1, "plan":"pro", "exp":0, "dev":"", "nonce":"..." }
///     - exp=0 表示永久；否则为 Unix 到期时间戳（秒）
///     - dev 为空 → 首次激活时绑定到当前设备（一张码只能在一台设备激活）
/// - 验签用内嵌公钥（与 scripts/gen_license.py 的私钥配对），整个过程不联网。
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    @Published private(set) var isPro: Bool = false
    @Published private(set) var licenseInfo: LicensePayload?
    @Published var errorMessage: String?

    /// 内嵌公钥（原始 32 字节 base64）。切勿替换为他人密钥，否则激活体系失控。
    private let publicKeyB64 = "lEl3eKv2Yr/Gz7ilOtTnLrHirfAr176T0vh8hNQIHuI="

    private let service = "com.mvextractor.app.license"

    // MARK: - 激活码载荷
    struct LicensePayload: Codable {
        var v: Int = 1
        var plan: String = "pro"
        var exp: Int = 0      // 0 = 永久
        var dev: String = ""  // 设备绑定，空=首次激活时绑定
        var nonce: String = ""
    }

    init() { restore() }

    // MARK: - 设备指纹（Keychain 持久 UUID，重装不丢）
    var deviceId: String {
        if let existing = readKeychain(key: "deviceId") { return existing }
        let newId = UIDevice.current.identifierForVendor?.uuidString
            ?? UUID().uuidString
        _ = saveKeychain(key: "deviceId", value: newId)
        return newId
    }

    // MARK: - 激活
    func activate(code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let payload = verifyAndParse(code: trimmed) else {
            errorMessage = "激活码无效，或签名校验失败"
            return false
        }
        if payload.plan != "pro" {
            errorMessage = "该激活码不是专业版"
            return false
        }
        if payload.exp != 0 && payload.exp < Int(Date().timeIntervalSince1970) {
            errorMessage = "激活码已过期"
            return false
        }
        // 设备绑定：payload.dev 为空则绑定当前设备（一张码单设备）
        let effectiveDev = payload.dev.isEmpty ? deviceId : payload.dev
        if effectiveDev != deviceId {
            errorMessage = "激活码已绑定到其他设备"
            return false
        }
        _ = saveKeychain(key: "licenseCode", value: trimmed)
        _ = saveKeychain(key: "licenseDev", value: deviceId)
        isPro = true
        licenseInfo = payload
        errorMessage = nil
        return true
    }

    // MARK: - 启动时恢复
    func restore() {
        guard let code = readKeychain(key: "licenseCode"),
              let boundDev = readKeychain(key: "licenseDev") else {
            isPro = false
            return
        }
        guard let payload = verifyAndParse(code: code) else {
            isPro = false
            return
        }
        if payload.exp != 0 && payload.exp < Int(Date().timeIntervalSince1970) {
            isPro = false
            return
        }
        if boundDev != deviceId {
            isPro = false
            return
        }
        isPro = true
        licenseInfo = payload
    }

    func deactivate() {
        _ = deleteKeychain(key: "licenseCode")
        _ = deleteKeychain(key: "licenseDev")
        isPro = false
        licenseInfo = nil
        errorMessage = nil
    }

    /// 到期描述（用于「我的」页展示）
    var expireText: String {
        guard let p = licenseInfo else { return "未激活" }
        if p.exp == 0 { return "永久有效" }
        let d = Date(timeIntervalSince1970: TimeInterval(p.exp))
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/MM/dd"
        return "有效期至 \(fmt.string(from: d))"
    }

    // MARK: - 验签核心
    private func verifyAndParse(code: String) -> LicensePayload? {
        let parts = code.split(separator: ".", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        guard let payloadData = Data(base64Encoded: String(parts[0])),
              let sigData = Data(base64Encoded: String(parts[1])) else { return nil }
        guard let raw = Data(base64Encoded: publicKeyB64),
              let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              pub.isValidSignature(sigData, for: payloadData) else { return nil }
        guard let payload = try? JSONDecoder().decode(LicensePayload.self, from: payloadData) else { return nil }
        return payload
    }

    // MARK: - Keychain 封装
    private func saveKeychain(key: String, value: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func readKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychain(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
