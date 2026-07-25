import SwiftUI
import UIKit

@main
struct KuaiGeApp: App {
    init() {
        configureNavigationBar()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { triggerNetworkPermission() }
        }
    }

    /// 移除导航栏底部的 hairline 分割线（「历史记录」「我的」标题下方的黑线）
    private func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.shadowColor = .clear
        appearance.shadowImage = UIImage()
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
    }

    /// 进入 App 立即发起一次轻量网络请求，触发 iOS「无线数据」权限弹窗。
    /// 系统会在 App 首次联网时自动询问是否允许使用无线数据；这里主动预热，
    /// 确保弹窗尽早出现（否则 WKWebView 的首次请求有时不会触发宿主 App 的权限弹窗）。
    private func triggerNetworkPermission() {
        guard let url = URL(string: "https://captive.apple.com/hotspot-detect.html") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }
}
