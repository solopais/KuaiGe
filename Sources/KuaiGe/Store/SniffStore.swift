import Foundation
import Combine

/// 全局嗅探结果容器（UI 与 WebView 注入脚本共享）
/// 历史记录持久化到 UserDefaults，杀 App 不丢失
final class SniffStore: ObservableObject {
    @Published var items: [SniffedMedia] = []

    private let historyKey = "com.mvextractor.app.history"

    init() {
        loadFromDisk()
    }

    /// 由 JS 注入脚本回调：捕获到一个媒体 URL
    func add(url: String, source: String, referer: String?, mediaType: MediaKind) {
        guard let u = URL(string: url), !(u.scheme?.isEmpty ?? true) else { return }
        if items.contains(where: { $0.url == url }) { return }
        DispatchQueue.main.async {
            self.items.append(
                SniffedMedia(url: url, source: source, referer: referer, mediaType: mediaType)
            )
            self.saveToDisk()
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
                self.saveToDisk()
            }
        }
    }

    func remove(url: String) {
        DispatchQueue.main.async {
            self.items.removeAll { $0.url == url }
            self.saveToDisk()
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.items.removeAll()
            self.saveToDisk()
        }
    }

    // MARK: - 磁盘持久化（UserDefaults + JSON）

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([SniffedMedia].self, from: data) else { return }
        items = decoded
    }
}
