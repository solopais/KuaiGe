import WebKit

/// 接收 WKWebView 注入脚本回传的音频 URL，写入 SniffStore
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
        guard message.name == SniffScript.handlerName,
              let dict = message.body as? [String: Any],
              let url = dict["url"] as? String else { return }
        let source = (dict["source"] as? String) ?? "unknown"
        let referer = dict["referer"] as? String
        store?.add(url: url, source: source, referer: referer)
    }
}
