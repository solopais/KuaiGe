import SwiftUI
import WebKit

/// 包裹 WKWebView：加载分享链接，并通过注入脚本嗅探音频
struct BrowserView: UIViewRepresentable {
    @ObservedObject var store: SniffStore
    @Binding var loadURL: URL?
    @Binding var isLoading: Bool
    @Binding var estimatedProgress: Double

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()

        let handler = SniffMessageHandler(store: store)
        controller.add(handler, name: SniffScript.handlerName)

        let script = WKUserScript(
            source: SniffScript.build(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(script)

        config.userContentController = controller
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never

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
        if let url = loadURL, webView.url != url {
            let req = URLRequest(url: url)
            webView.load(req)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: BrowserView
        weak var webView: WKWebView?

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
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        // 处理 target=_blank：在当前 WebView 内打开
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

        deinit {
            webView?.removeObserver(self, forKeyPath: "estimatedProgress")
        }
    }
}
