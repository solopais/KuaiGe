import SwiftUI
import WebKit

/// 包裹 WKWebView：双层嗅探（JS 注入 + Network Layer）
///
/// 架构对标浏览器扩展（如 AixDownloader）：
/// - Layer 1: JS 注入（SniffScript）→ DOM 层拦截 src/fetch/XHR/Performance API
/// - Layer 2: NSURLProtocol（KuaiGeURLProtocol）→ Network 层拦截所有 HTTP 请求/响应
///
/// 双层互为补充：即使 JS 被反自动化检测阻止，Network Layer 照样能抓到媒体资源。
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

        // ========== Layer 0: 反指纹脚本（增强版 15+ 项）==========
        let antiDetectScript = WKUserScript(
            source: AntiDetectScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(antiDetectScript)

        // ========== Layer 1: JS 嗅探引擎 ==========
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

        // 使用真实 iPhone Safari UA：移动端 WebView 用移动 UA 渲染最正常，
        // 且与下方反指纹脚本（platform=iPhone 等）保持一致，避免 UA/指纹冲突触发风控拒绝
        webView.customUserAgent = Self.mobileSafariUA

        context.coordinator.webView = webView
        webView.addObserver(context.coordinator, forKeyPath: "estimatedProgress", options: .new, context: nil)

        // ========== Layer 2: 注册网络层嗅探 Protocol ==========
        KuaiGeURLProtocol.register { url, source, mediaType in
            let kind: MediaKind = (mediaType == "video") ? .video : .audio
            DispatchQueue.main.async {
                self.store.add(url: url, source: source, referer: webView.url?.absoluteString, mediaType: kind)
            }
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let url = loadURL else { return }
        // 用 coordinator 记录「主动加载过的 URL」，避免依赖 webView.url 在 load 调用后
        // 立即变化而导致漏加载或重复加载
        guard context.coordinator.lastLoadedURL != url else { return }

        var request = URLRequest(url: url)
        // 完整模拟桌面浏览器的请求头
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate, br, zstd", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")

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
                #if DEBUG
                print("[KuaiGe] 导航失败: \(error.localizedDescription)")
                #endif
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            if (error as NSError).code != NSURLErrorCancelled {
                #if DEBUG
                print("[KuaiGe] 临时导航失败: \(error.localizedDescription)")
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

        deinit {
            webView?.removeObserver(self, forKeyPath: "estimatedProgress")
        }
    }
}

// MARK: - 反指纹脚本（独立枚举，方便维护和测试）

/// 全面反自动化检测脚本 —— 伪装 15+ 个浏览器指纹维度
///
/// 参考：puppeteer-extra-plugin-stealth / navigator.webdriver 检测绕过
enum AntiDetectScript {
    static let source: String = #"""
    (function(){
      'use strict';

      // ===== 1. navigator.webdriver =====
      // 最基础的检测：Selenium/Puppeteer/WKWebView 会设为 true
      Object.defineProperty(navigator, 'webdriver', {
        get: () => undefined,
        configurable: true
      });

      // ===== 2. navigator.plugins =====
      // 真实浏览器有 PDF Flash 等插件，WebView 通常为空
      Object.defineProperty(navigator, 'plugins', {
        get: () => {
          const p = [
            { name: 'Chrome PDF Plugin', filename: 'internal-pdf-viewer', description: 'Portable Document Format' },
            { name: 'Chrome PDF Viewer', filename: 'mhjfbmdgcfjbbpaeojofohoefgiehjai', description: '' },
            { name: 'Native Client', filename: 'internal-nacl-plugin', description: '' },
          ];
          p.length = 3;
          return p;
        },
        configurable: true
      });

      // ===== 3. navigator.languages =====
      Object.defineProperty(navigator, 'languages', {
        get: () => ['zh-CN', 'zh', 'en'],
        configurable: true
      });

      // ===== 4. 平台与硬件信息 =====
      Object.defineProperty(navigator, 'platform', { get: () => 'iPhone', configurable: true });
      Object.defineProperty(navigator, 'hardwareConcurrency', { get: () => 4, configurable: true });
      Object.defineProperty(navigator, 'deviceMemory', { get: () => 4, configurable: true });
      Object.defineProperty(navigator, 'maxTouchPoints', { get: () => 5, configurable: true });
      Object.defineProperty(navigator, 'vendor', { get: () => 'Apple Computer, Inc.', configurable: true });

      // ===== 5. window.chrome 对象 =====
      // 真实 iPhone Safari 没有 window.chrome 对象。UA 已统一为 iPhone Safari，
      // 若在此伪造 window.chrome 反而与 UA 矛盾、更易被风控识别，故不设置。

      // ===== 6. Permissions API =====
      // 伪装 notifications 权限查询结果
      const origQuery = window.navigator.permissions.query;
      if (origQuery) {
        window.navigator.permissions.query = (params) => (
          params.name === 'notifications'
            ? Promise.resolve({ state: Notification.permission })
            : origQuery.call(window.navigator.permissions, params)
        );
      }

      // ===== 7. Connection API (NetworkInformation) =====
      // 伪造网络连接信息
      var conn = navigator.connection || navigator.mozConnection || navigator.webkitConnection;
      if (conn) {
        Object.defineProperty(conn, 'effectiveType', { get: () => '4g', configurable: true });
        Object.defineProperty(conn, 'rtt', { get: () => 50, configurable: true });
        Object.defineProperty(conn, 'downlink', { get: () => 10, configurable: true });
      }

      // ===== 8. WebGL 渲染器/供应商指纹伪装 =====
      try {
        var getParameter = WebGLRenderingContext.prototype.getParameter;
        WebGLRenderingContext.prototype.getParameter = function(param) {
          // UNMASKED_VENDOR_WEBGL = 37445
          if (param === 37445) return 'Google Inc. (Intel)';
          // UNMASKED_RENDERER_WEBGL = 37446
          if (param === 37446) return 'ANGLE (Intel, Intel(R) UHD Graphics 630 Direct3D11 vs_5_0 ps_5_0, D3D11)';
          return getParameter.call(this, param);
        };
      } catch(e) {}

      // ===== 9. Canvas 指纹噪声注入 =====
      // 在 canvas 输出中添加不可见的随机噪声，使每次绘制结果唯一
      try {
        var origToDataURL = HTMLCanvasElement.prototype.toDataURL;
        var origToBlob = HTMLCanvasElement.prototype.toBlob;
        var origGetImageData = CanvasRenderingContext2D.prototype.getImageData;

        // 对 getImageData 注入微小噪声
        CanvasRenderingContext2D.prototype.getImageData = function(x, y, w, h) {
          var data = origGetImageData.call(this, x, y, w, h);
          for (var i = 0; i < data.data.length; i += 4) {
            if (data.data[i+3] > 0) { // 只修改非透明像素
              data.data[i] ^= (Math.random() > 0.99 ? 1 : 0);   // R
              data.data[i+1] ^= (Math.random() > 0.99 ? 1 : 0); // G
              data.data[i+2] ^= (Math.random() > 0.99 ? 1 : 0); // B
            }
          }
          return data;
        };
      } catch(e) {}

      // ===== 10. AudioContext 指纹噪声 =====
      try {
        var origGetFloatData = AnalyserNode.prototype.getFloatFrequencyData;
        if (origGetFloatData) {
          AnalyserNode.prototype.getFloatFrequencyData = function(arr) {
            origGetFloatData.call(this, arr);
            for (var i = 0; i < arr.length; i++) {
              arr[i] += Math.random() * 0.0001; // 微小噪声
            }
          };
        }
      } catch(e) {}

      // ===== 11. Screen 信息一致性 =====
      // 确保 screen.width/height 与 window.innerWidth 匹配逻辑
      Object.defineProperty(screen, 'width', { get: () => window.screen.width || 393, configurable: true });
      Object.defineProperty(screen, 'height', { get: () => window.screen.height || 852, configurable: true });
      Object.defineProperty(screen, 'availWidth', { get: () => (window.screen.width || 393), configurable: true });
      Object.defineProperty(screen, 'availHeight', { get: () => ((window.screen.height || 852) - 47), configurable: true });
      Object.defineProperty(screen, 'colorDepth', { get: () => 32, configurable: true });
      Object.defineProperty(screen, 'pixelDepth', { get: () => 32, configurable: true });

      // ===== 12. 存储可用性 =====
      if (navigator.storage && navigator.storage.estimate) {
        var origEstimate = navigator.storage.estimate.bind(navigator.storage);
        navigator.storage.estimate = function() {
          return Promise.resolve({ quota: 2e11, usage: 5e7 }); // ~200GB / 50MB used
        };
      }

      console.log('[KuaiGe] 反指纹引擎已加载 (15项)');
    })();
    """#
}
