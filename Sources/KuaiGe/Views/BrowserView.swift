import SwiftUI
import WebKit

/// 包裹 WKWebView：加载分享链接，并通过注入脚本嗅探媒体资源
///
/// 策略说明：
/// - 对于普通网站（音乐站、视频站、个人站点）：直接加载，嗅探引擎自动抓取媒体
/// - 对于强反爬平台（抖音/TikTok、部分短视频平台）：服务端会返回 403 Access Denied，
///   这类平台的视频提取建议使用第三方解析接口或桌面浏览器提取直链后粘贴到 App
/// - 本组件专注于「能正常访问的网页」中的媒体嗅探，不尝试对抗服务端级别的反爬
struct BrowserView: UIViewRepresentable {
    @ObservedObject var store: SniffStore
    @Binding var loadURL: URL?
    @Binding var isLoading: Bool
    @Binding var estimatedProgress: Double
    @Binding var pageError: String?  // 页面加载错误信息（如 Access Denied）

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// 真实 iPhone Safari UA（iOS 17.4.1 / iPhone 15 Pro）
    static let mobileSafariUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()

        // ========== 1) 反指纹脚本 ==========
        let antiDetectScript = WKUserScript(
            source: """
            // 反自动化检测 —— 让目标页面认为这是真实手机 Safari
            Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
            Object.defineProperty(navigator, 'plugins', {
                get: () => { const a=[]; a.length=0; return a; }
            });
            Object.defineProperty(navigator, 'languages', {
                get: () => ['zh-CN', 'zh-Hans', 'zh', 'en-US', 'en']
            });
            Object.defineProperty(navigator, 'platform', { get: () => 'iPhone' });
            Object.defineProperty(navigator, 'hardwareConcurrency', { get: () => 4 });
            Object.defineProperty(navigator, 'maxTouchPoints', { get: () => 5 });
            if (!window.chrome) window.chrome = { runtime:{}, loadTimes:function(){}, csi:function(){} };
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(antiDetectScript)

        // ========== 2) 嗅探脚本 ==========
        let handler = SniffMessageHandler(store: store)
        controller.add(handler, name: SniffScript.handlerName)
        let sniffScript = WKUserScript(
            source: SniffScript.build(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(sniffScript)

        config.userContentController = controller
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.customUserAgent = Self.mobileSafariUA

        context.coordinator.webView = webView
        webView.addObserver(context.coordinator, forKeyPath: "estimatedProgress", options: .new, context: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let url = loadURL else { return }
        // 避免重复加载同一 URL
        guard webView.url != url else { return }

        var request = URLRequest(url: url)
        // 模拟真实浏览器的请求头
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")

        webView.load(request)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: BrowserView
        weak var webView: WKWebView?

        init(_ parent: BrowserView) {
            self.parent = parent
            super.init()
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "estimatedProgress", let wv = object as? WKWebView {
                parent.estimatedProgress = wv.estimatedProgress
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        // MARK: - 导航决策
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel); return
            }
            guard url.scheme == "http" || url.scheme == "https" else {
                // 拦截 scheme 跳转（douyin:// 等），转为当前 WebView 加载
                if navigationAction.targetFrame == nil {
                    DispatchQueue.main.async { webView.load(URLRequest(url: url)) }
                }
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }

        // MARK: - 响应决策：检测 Access Denied 等错误页面
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let httpResponse = navigationResponse.response as? HTTPURLResponse {
                let code = httpResponse.statusCode
                if code == 403 || code == 406 || code == 451 {
                    let urlStr = navigationResponse.response.url?.absoluteString ?? ""
                    #if DEBUG
                    print("[KuaiGe] ⚠️ 服务端拒绝 (\(code)): \(urlStr)")
                    for (key, value) in httpResponse.allHeaderFields {
                        print("[KuaiGe]   \(key): \(value)")
                    }
                    #endif
                    // 检查是否为反爬拒绝（通过响应头特征判断）
                    let headers = httpResponse.allHeaderFields
                    let hasAntiBotHeaders = headers["X-TT-System-Error"] != nil ||
                                          headers["X-Douyin-Error"] != nil ||
                                          headers["X-Block"] != nil

                    if hasAntiBotHeaders || code == 403 {
                        DispatchQueue.main.async {
                            self.parent.pageError = "目标网站返回 \(code) 拒绝访问（\(urlStr.host ?? "")）"
                        }
                    }
                } else if code >= 200 && code < 400 {
                    // 成功响应，清除之前的错误状态
                    DispatchQueue.main.async { self.parent.pageError = nil }
                }
            }
            decisionHandler(.allow)
        }

        // MARK: - target=_blank
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // MARK: - JS 弹窗拦截
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) { completionHandler() }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) { completionHandler(false) }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) { completionHandler(nil) }

        deinit {
            webView?.removeObserver(self, forKeyPath: "estimatedProgress")
        }
    }
}
