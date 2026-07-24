import Foundation
import Combine

/// 全局嗅探结果容器（UI 与 WebView 注入脚本共享）
final class SniffStore: ObservableObject {
    @Published var items: [SniffedMedia] = []

    /// 由 JS 注入脚本回调：捕获到一个音频 URL
    func add(url: String, source: String, referer: String?) {
        guard let u = URL(string: url), !u.scheme.isEmpty else { return }
        let deduped = url
        if items.contains(where: { $0.url == deduped }) { return }
        DispatchQueue.main.async {
            self.items.append(
                SniffedMedia(url: deduped, source: source, referer: referer, detectedAt: Date())
            )
        }
    }

    func markDownloaded(url: String, path: String) {
        DispatchQueue.main.async {
            if let idx = self.items.firstIndex(where: { $0.url == url }) {
                self.items[idx].downloadedLocalPath = path
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.items.removeAll()
        }
    }
}
