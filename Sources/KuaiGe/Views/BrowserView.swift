import SwiftUI
import WebKit

/// 通知：停止 WebView 中所有正在播放的音视频
extension Notification.Name {
    static let kuaiGeStopMedia = Notification.Name("kuaiGeStopMedia")
}

/// 包裹 WKWebView：注入 JS 嗅探脚本，扫描页面上的音视频资源
/// （即「F12 抓媒体」的核心：DOM 扫描 + fetch/XHR 拦截 + Performance API）
struct BrowserView: UIViewRepresentable {
    @ObservedObject var store: SniffStore
    @Binding var loadURL: URL?
    @Binding var isLoading: Bool
    @Binding var estimatedProgress: Double
    @Binding var pageError: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - UA 配置

    /// 方案 A：桌面 Chrome UA（让抖音等返回桌面版，桌面版通常反爬比移动端弱）
    static let desktopChromeUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    /// 方案 B：真实 iPhone Safari UA（备选）
    static let mobileSafariUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()

        // 唯一的嗅探手段：注入 JS 扫描页面上的 audio/video、拦截 fetch/XHR、扫描 Performance API
        // —— 这就是「F12 抓媒体」的本质，简单直接，不依赖任何网络层黑魔法
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

        // 用真实的 iPhone Safari UA，不伪造任何指纹 —— 让网站认定是正常的手机浏览器
        webView.customUserAgent = Self.mobileSafariUA

        context.coordinator.webView = webView
        webView.addObserver(context.coordinator, forKeyPath: "estimatedProgress", options: .new, context: nil)

        // 监听「停止媒体」通知（切换页面/Tab 时触发，防止后台继续播放）
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.stopAllMedia(_:)),
            name: .kuaiGeStopMedia,
            object: nil
        )

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let url = loadURL else { return }
        // 用 coordinator 记录「主动加载过的 URL」，避免依赖 webView.url 在 load 调用后
        // 立即变化而导致漏加载或重复加载
        guard context.coordinator.lastLoadedURL != url else { return }

        var request = URLRequest(url: url)
        // 只补中文语言偏好，其余交给系统默认请求头（不再伪造任何浏览器指纹头）
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        isLoading = true
        pageError = nil
        context.coordinator.lastLoadedURL = url
        webView.load(request)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: BrowserView
        weak var webView: WKWebView?
        /// 记录「主动 load 过的 URL」，用于 updateUIView 防重复/防漏加载判断
        var lastLoadedURL: URL? = nil

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
            // 忽略取消错误（用户主动切换页面时会产生）
            if (error as NSError).code != NSURLErrorCancelled {
                let msg = (error as NSError).localizedDescription
                DispatchQueue.main.async {
                    self.parent.pageError = "页面加载失败：\n\(msg)\n\n请检查网络连接，或前往系统「设置」确认已允许本 App 使用无线数据。"
                }
                #if DEBUG
                print("[KuaiGe] 导航失败: \(msg)")
                #endif
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            if (error as NSError).code != NSURLErrorCancelled {
                let msg = (error as NSError).localizedDescription
                DispatchQueue.main.async {
                    self.parent.pageError = "页面加载失败：\n\(msg)\n\n请检查网络连接，或前往系统「设置」确认已允许本 App 使用无线数据。"
                }
                #if DEBUG
                print("[KuaiGe] 临时导航失败: \(msg)")
                #endif
            }
        }

        // MARK: - 导航决策

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel); return
            }

            guard url.scheme == "http" || url.scheme == "https" else {
                // 拦截非 HTTP scheme（douyin:// snssdk1128:// 等）
                if navigationAction.targetFrame == nil {
                    #if DEBUG
                    print("[KuaiGe] 拦截 scheme 跳转: \(url.scheme ?? "") → 转为 HTTP 加载")
                    #endif
                    // 尝试从 URL 中提取可能的 HTTP 链接
                    if let httpURL = extractHTTPUrl(from: url) {
                        DispatchQueue.main.async { webView.load(URLRequest(url: httpURL)) }
                    }
                }
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }

        /// 从自定义 scheme URL 中提取可能的 HTTP URL
        private func extractHTTPUrl(from url: URL) -> URL? {
            // douyin://?type=video&url=xxx 或类似格式
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let queryItems = components?.queryItems,
               let urlString = queryItems.first(where: { $0.name.lowercased().contains("url") })?.value,
               let httpURL = URL(string: urlString) {
                return httpURL
            }
            // 如果绝对路径看起来像 URL
            if let path = url.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               path.hasPrefix("http"), let httpURL = URL(string: path) {
                return httpURL
            }
            return nil
        }

        // MARK: - 响应决策：检测 Access Denied + 媒体响应

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let httpResponse = navigationResponse.response as? HTTPURLResponse {
                let code = httpResponse.statusCode
                let urlStr = navigationResponse.response.url?.absoluteString ?? ""

                if code == 403 || code == 406 || code == 451 {
                    let headers = httpResponse.allHeaderFields
                    let robotsTag = headers["X-Robots-Tag"] as? String
                    let isAntiBot = headers["X-TT-System-Error"] != nil ||
                                    headers["X-Douyin-Error"] != nil ||
                                    headers["X-Block"] != nil ||
                                    robotsTag?.contains("noindex") == true

                    #if DEBUG
                    print("[KuaiGe] ⚠️ 服务端拒绝 (\(code)): \(urlStr)")
                    if isAntiBot { print("[KuaiGe]   🔒 检测到反爬头") }
                    #endif

                    if isAntiBot || code == 403 {
                        DispatchQueue.main.async {
                            self.parent.pageError = """
                            该网站拒绝了访问（\(code)）

                            部分（抖音、TikTok 等）平台有强反爬保护。
                            建议：
                            1. 在 Safari 浏览器打开链接
                            2. 找到视频右键「检查元素」或复制视频地址
                            3. 将直链粘贴到上方链接栏
                            """
                        }
                    }
                } else if code >= 200 && code < 400 {
                    // 成功响应 → 清除错误状态
                    if parent.pageError != nil && !parent.pageError!.isEmpty {
                        DispatchQueue.main.async { self.parent.pageError = nil }
                    }
                }
            }
            decisionHandler(.allow)
        }

        // MARK: - target=_blank 处理

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // MARK: - JS 弹窗静默拦截

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            #if DEBUG
            print("[KuaiGe] [alert] \(message.prefix(100))")
            #endif
            completionHandler()
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) { completionHandler(false) }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) { completionHandler(nil) }

        /// 停止页面中所有正在播放的音视频（切换 Tab/返回时调用）
        @objc func stopAllMedia(_ notification: Notification) {
            guard let wv = webView else { return }
            wv.evaluateJavaScript("""
                (function(){
                    var els = document.querySelectorAll('audio, video');
                    els.forEach(function(el){
                        el.pause();
                        el.currentTime = 0;
                        el.removeAttribute('src');
                        el.load();
                    });
                    return els.length;
                })();
            """) { result, error in
                if let err = error {
                    #if DEBUG
                    print("[KuaiGe] 停止媒体失败: \(err.localizedDescription)")
                    #endif
                } else if let n = result as? Int, n > 0 {
                    #if DEBUG
                    print("[KuaiGe] 已停止 \(n) 个媒体元素")
                    #endif
                }
            }
        }

        deinit {
            webView?.removeObserver(self, forKeyPath: "estimatedProgress")
            NotificationCenter.default.removeObserver(self, name: .kuaiGeStopMedia, object: nil)
        }
    }
}

