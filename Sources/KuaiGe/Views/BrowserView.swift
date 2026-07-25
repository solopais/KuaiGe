import SwiftUI
import WebKit

/// 包裹 WKWebView：加载分享链接，并通过注入脚本嗅探媒体资源
///
/// 反爬措施：
/// 1. 桌面端 Chrome User-Agent（绕过移动端 WebView 检测）
/// 2. 注入反自动化检测脚本（navigator.webdriver / plugins / languages）
/// 3. 决策代理中限制同域重定向次数（防止无限跳转循环）
/// 4. 允许混合内容 + 禁用内容安全策略限制
struct BrowserView: UIViewRepresentable {
    @ObservedObject var store: SniffStore
    @Binding var loadURL: URL?
    @Binding var isLoading: Bool
    @Binding var estimatedProgress: Double

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// 桌面端 Chrome UA —— 大部分网站对桌面浏览器检测较松
    /// 使用较新的 Chrome 版本号以避免被版本过旧拦截
    static let desktopChromeUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/131.0.0.0 Safari/537.36"

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()

        // ========== 1) 反自动化检测脚本（在所有页面注入）==========
        let antiDetectScript = WKUserScript(
            source: """
            // 反爬：隐藏自动化特征
            Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
            // 伪造 plugins（真实浏览器有插件）
            Object.defineProperty(navigator, 'plugins', {
                get: () => {
                    const p = [
                        { name: 'Chrome PDF Plugin', filename: 'internal-pdf-viewer', description: 'Portable Document Format' },
                        { name: 'Chrome PDF Viewer', filename: 'mhjfbmdgcfjbbpaeojofohoefgiehjai', description: '' },
                        { name: 'Native Client', filename: 'internal-nacl-plugin', description: '' }
                    ];
                    p.length = 3;
                    return p;
                }
            });
            // 伪造 languages
            Object.defineProperty(navigator, 'languages', { get: () => ['zh-CN', 'zh', 'en'] });
            // 覆盖 chrome 对象（防止检测到缺失）
            window.chrome = { runtime: {}, loadTimes: function(){}, csi: function(){} };
            // 修改 permissions API
            if (navigator.permissions && navigator.permissions.query) {
                const origQuery = navigator.permissions.query.bind(navigator.permissions);
                navigator.permissions.query = (params) =>
                    (params.name === 'notifications') ?
                        Promise.resolve({ state: Notification.permission }) : origQuery(params);
            }
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

        // 设置桌面 UA
        webView.customUserAgent = Self.desktopChromeUA

        context.coordinator.webView = webView
        webView.addObserver(
            context.coordinator,
            forKeyPath: "estimatedProgress",
            options: .new,
            context: nil
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let url = loadURL {
            // 避免重复加载同一 URL（防止刷新循环）
            guard webView.url != url else { return }
            var request = URLRequest(url: url)
            // 设置 Accept-Language 为中文桌面浏览器
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
            webView.load(request)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: BrowserView
        weak var webView: WKWebView?

        /// 重定向计数器：记录同一域名下的连续重定向次数，超过阈值则阻止
        private var redirectCount: Int = 0
        private var lastDomain: String?
        private static let maxRedirectsPerDomain = 8

        init(_ parent: BrowserView) {
            self.parent = parent
            super.init()
        }

        // MARK: - 进度 / 加载状态
        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            if keyPath == "estimatedProgress", let wv = object as? WKWebView {
                parent.estimatedProgress = wv.estimatedProgress
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            // 页面加载完成，重置重定向计数
            redirectCount = 0
            lastDomain = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        // MARK: - 导航决策（核心：防重定向循环）
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel); return
            }

            let urlString = url.absoluteString

            // 只允许 http(s) 协议
            guard url.scheme == "http" || url.scheme == "https" else {
                decisionHandler(.cancel); return
            }

            // 同域重定向计数检查
            let domain = url.host ?? ""
            if lastDomain == domain {
                redirectCount += 1
                if redirectCount > Self.maxRedirectsPerDomain {
                    // 超过阈值，阻止本次导航（可能陷入重定向循环）
                    print("[KuaiGe] ⚠️ 域名 \(domain) 重定向次数超限(\(redirectCount))，阻止跳转")
                    decisionHandler(.cancel); return
                }
            } else {
                // 切换域名，重置计数
                redirectCount = 1
                lastDomain = domain
            }

            decisionHandler(.allow)
        }

        // MARK: - 响应决策：允许混合内容
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            // 允许 HTTPS 页面中的 HTTP 内容（很多视频站混用 HTTP CDN）
            decisionHandler(.allow)
        }

        // MARK: - target=_blank 在当前 WebView 打开
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil,
               let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // MARK: - 拦截 JS 弹窗（alert / confirm / prompt）
        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            completionHandler()
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(false)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            completionHandler(nil)
        }

        deinit {
            webView?.removeObserver(self, forKeyPath: "estimatedProgress")
        }
    }
}
