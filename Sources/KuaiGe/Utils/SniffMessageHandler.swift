import WebKit

/// 接收 WKWebView 注入脚本回传的媒体 URL，写入 SniffStore
///
/// 容错设计：
/// - message.body 可能是 String / NSDictionary / NSNumber 等多种类型
/// - 不做强制类型断言，逐级安全解析
/// - 非法消息静默丢弃，不影响 App 稳定性
final class SniffMessageHandler: NSObject, WKScriptMessageHandler {
    weak var store: SniffStore?

    init(store: SniffStore) {
        self.store = store
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // 只处理我们注册的 handler 消息
        guard message.name == SniffScript.handlerName else { return }

        let body = message.body

        // Swift 中 WKScriptMessage.body 的实际类型可能是：
        // • [String: Any] (NSDictionary) —— 正常 JS 对象
        // • String                    —— JS 基本类型
        // • NSArray                   —— JS 数组
        // • NSNumber                  —— JS 数字/布尔
        // • NSNull                    —— JS null

        guard let dict = body as? [String: Any] else {
            // body 不是字典类型——记录但不崩溃
            #if DEBUG
            print("[KuaiGe] 收到非字典消息体: \(type(of: body)) value=\(body)")
            #endif
            return
        }

        // 安全提取各字段（全部有默认值）
        let url = (dict["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !url.isEmpty else { return }

        // URL 必须是合法的 http(s)/blob 协议
        guard url.hasPrefix("http://") || url.hasPrefix("https://") || url.hasPrefix("blob:") else {
            return
        }

        let source = (dict["source"] as? String) ?? "unknown"
        let referer = (dict["referer"] as? String) ?? ""
        let mediaTypeRaw = (dict["mediaType"] as?. String) ?? "other"
        let mediaType = MediaKind(rawValue: mediaTypeRaw) ?? .other

        store?.add(url: url, source: source, referer: referer, mediaType: mediaType)
    }
}
