import SwiftUI
import WebKit

/// 包裹 WKWebView：加载分享链接，并通过注入脚本嗅探媒体资源
///
/// 反爬策略（针对抖音/B站/快手等强检测平台）：
/// A. 真实 iPhone Safari UA（非桌面 Chrome）—— 让平台返回移动端适配页面
/// B. 短链接预解析 —— v.douyin.com 等 302 链在加载前先解到最终 URL
/// C. 注入反指纹脚本 —— 覆盖 navigator 多个属性、隐藏 WebView 特征
/// D. 导航决策中记录日志 + 智能重定向控制
struct BrowserView: UIViewRepresentable {
    @ObservedObject var store: SniffStore
    @Binding var loadURL: URL?
    @Binding var isLoading: Bool
    @Binding var estimatedProgress: Double

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// 真实 iPhone Safari UA（iOS 17.4.1 / iPhone 15 Pro）
    /// 关键：必须与真实设备一致，否则抖音等会检测 UA 版本过旧
    static let mobileSafariUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()

        // ========== 1) 反指纹脚本（atDocumentStart，所有 frame 执行）==========
        let antiDetectScript = WKUserScript(
            source: """
            // ====== 反自动化 / 反 WebView 检测 ======

            // ① navigator.webdriver → undefined（最关键）
            Object.defineProperty(navigator, 'webdriver', {
                get: () => undefined,
                configurable: true
            });

            // ② 伪造 plugins（Safari/iOS 实际无插件，但很多网站检查此属性是否存在）
            //    返回空类数组对象而非 null
            Object.defineProperty(navigator, 'plugins', {
                get: () => {
                    const arr = [];
                    arr.length = 0;
                    return arr;
                },
                configurable: true
            });

            // ③ 伪造 languages
            Object.defineProperty(navigator, 'languages', {
                get: () => ['zh-CN', 'zh-Hans', 'zh', 'en-US', 'en'],
                configurable: true
            });

            // ④ platform 必须是 iPhone（WKWebView 默认就是，但保险起见）
            Object.defineProperty(navigator, 'platform', {
                get: () => 'iPhone',
                configurable: true
            });

            // ⑤ hardwareConcurrency（iOS Safari 通常返回 4 或根据核心数）
            Object.defineProperty(navigator, 'hardwareConcurrency', {
                get: () => 4,
                configurable: true
            });

            // ⑥ deviceMemory（iOS Safari 不暴露此 API，但防止被 polyfill 检测）
            if (!navigator.deviceMemory) {
                Object.defineProperty(navigator, 'deviceMemory', {
                    get: () => 4,
                    configurable: true
                });
            }

            // ⑦ maxTouchPoints（iPhone = 5）
            Object.defineProperty(navigator, 'maxTouchPoints', {
                get: () => 5,
                configurable: true
            });

            // ⑧ 补充 chrome 对象（防止 JS 报错 "Cannot read properties of undefined"）
            if (!window.chrome) {
                window.chrome = {
                    runtime: {},
                    loadTimes: function(){},
                    csi: function(){}
                };
            }

            // ⑨ Permissions API 兼容
            try {
                if (navigator.permissions && navigator.permissions.query) {
                    const origQuery = navigator.permissions.query.bind(navigator.permissions);
                    navigator.permissions.query = function(params) {
                        if (params && params.name === 'notifications') {
                            return Promise.resolve({ state: Notification.permission, onchange: null });
                        }
                        return origQuery(params);
                    };
                }
            } catch(e) {}

            // ⑩ 覆盖 Connection API（防止网络类型检测）
            try {
                var conn = navigator.connection || navigator.mozConnection || navigator.webkitConnection;
                if (conn) {
                    Object.defineProperty(conn, 'effectiveType', { get: () => '4g' });
                    Object.defineProperty(conn, 'rtt', { get: () => 50 });
                    Object.defineProperty(conn, 'downlink', { get: () => 10 });
                }
            } catch(e) {}
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

        // 使用真实 iPhone Safari UA
        webView.customUserAgent = Self.mobileSafariUA

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
        guard let url = loadURL else { return }

        // 避免重复加载同一 URL
        if webView.url == url { return }

        let coordinator = context.coordinator

        // 检查是否为已知短链接域名 → 预解析 302 链
        let host = url.host?.lowercased() ?? ""
        let shortLinkHosts = [
            "v.douyin.com", "douyin.com", "iesdouyin.com",
            "b23.tv", "bilibili.com",
            "kuaishou.com", "v.kuaishou.com",
            "ixigua.com", "toutiao.com",
            "weibo.com", "weibo.cn",
            "zhihu.com", "zhuanlan.zhihu.com",
            "xiaohongshu.com", "xhslink.com"
        ]

        if shortLinkHosts.contains(where: { host.hasSuffix($0) || host == $0 }) {
            // 异步预解析短链接，拿到最终 URL 再加载
            isLoading = true
            coordinator.resolveShortURL(url) { [weak coordinator] finalURL in
                DispatchQueue.main.async {
                    guard let _ = coordinator else { return }
                    self.isLoading = false
                    let targetURL = finalURL ?? url
                    #if DEBUG
                    print("[KuaiGe] 短链接解析: \(url.host ?? "") → \(targetURL.host ?? "")")
                    #endif
                    var req = URLRequest(url: targetURL)
                    req.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
                    req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
                    webView.load(req)
                }
            }
        } else {
            // 普通链接直接加载
            var request = URLRequest(url: url)
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
            webView.load(request)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: BrowserView
        weak var webView: WKWebView?

        init(_ parent: BrowserView) {
            self.parent = parent
            super.init()
        }

        // MARK: - 进度监听
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

        // MARK: - 导航生命周期
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            #if DEBUG
            if let url = webView.url {
                print("[KuaiGe] 📍 开始导航: \(url.absoluteString)")
            }
            #endif
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            #if DEBUG
            print("[KuaiGe] ✅ 页面加载完成: \(webView.url?.absoluteString ?? "nil")")
            #endif
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            #if DEBUG
            print("[KuaiGe] ❌ 导航失败: \(error.localizedDescription)")
            #endif
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            #if DEBUG
            print("[KuaiGe] ❌ 临时导航失败: \(error.localizedDescription)")
            #endif
        }

        // MARK: - 导航决策
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel); return
            }

            // 只允许 http(s)
            guard url.scheme == "http" || url.scheme == "https" else {
                decisionHandler(.cancel); return
            }

            // 拦截 scheme 跳转（如 douyin:// 、snssdk1128:// 等 App Deep Link）
            if navigationAction.targetFrame == nil {
                // 新窗口打开的请求 → 在当前 WebView 加载（而不是跳转到外部 App）
                #if DEBUG
                print("[KuaiGe] 🔗 拦截新窗口跳转: \(url.absoluteString)")
                #endif
                // 不调用 decisionHandler(.allow)，而是手动在当前 WebView 加载
                decisionHandler(.cancel)
                DispatchQueue.main.async {
                    webView.load(URLRequest(url: url))
                }
                return
            }

            decisionHandler(.allow)
        }

        // MARK: - 响应决策
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            #if DEBUG
            if let response = navigationResponse.response as? HTTPURLResponse {
                print("[KuaiGe] 📥 响应: \(response.statusCode) \(navigationResponse.response.url?.absoluteString ?? "")")
            }
            #endif
            // 允许所有响应（包括混合内容）
            decisionHandler(.allow)
        }

        // MARK: - target=_blank 处理
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                #if DEBUG
                print("[KuaiGe] 🔗 createWebView: \(url.absoluteString)")
                #endif
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // MARK: - JS 弹窗拦截
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

        // MARK: - 短链接预解析（跟随 302 重定向链获取最终 URL）

        /// 解析短链接（如 v.douyin.com/xxx），跟随 302 链直到最终 URL
        /// - Parameters:
        ///   - url: 原始短链接
        ///   - completion: 最终 URL（可能仍为原始 URL 如果没有重定向）
        func resolveShortURL(_ url: URL, completion: @escaping (URL?) -> Void) {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"  // HEAD 方法只拿头不下载 body，更快
            request.timeoutInterval = 10
            request.setValue(BrowserView.mobileSafariUA, forHTTPHeaderField: "User-Agent")

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                // 取最终 URL（URLSession 自动跟随重定向）
                let finalURL = (response as? HTTPURLResponse)?.url ?? url
                completion(finalURL)
            }
            task.resume()
        }
    }
}
