import Foundation
import Combine

/// 全局嗅探结果容器（UI 与 WebView 注入脚本共享）
final class SniffStore: ObservableObject {
    @Published var items: [SniffedMedia] = []

    /// 由 JS 注入脚本回调：捕获到一个媒体 URL
    func add(url: String, source: String, referer: String?, mediaType: MediaKind) {
        guard let u = URL(string: url), !(u.scheme?.isEmpty ?? true) else { return }
        if items.contains(where: { $0.url == url }) { return }
        DispatchQueue.main.async {
            self.items.append(
                SniffedMedia(url: url, source: source, referer: referer, mediaType: mediaType)
            )
        }
    }

    /// 音频提取页展示：除视频以外的全部（含类型未知的 other）
    var audioItems: [SniffedMedia] { items.filter { $0.mediaType != .video } }

    /// 视频提取页展示：除音频以外的全部（含类型未知的 other）
    var videoItems: [SniffedMedia] { items.filter { $0.mediaType != .audio } }

    func markDownloaded(url: String, path: String) {
        DispatchQueue.main.async {
            if let idx = self.items.firstIndex(where: { $0.url == url }) {
                self.items[idx].downloadedLocalPath = path
            }
        }
    }

    func remove(url: String) {
        DispatchQueue.main.async {
            self.items.removeAll { $0.url == url }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.items.removeAll()
        }
    }
}
