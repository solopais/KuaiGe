import Foundation
import Combine

/// 把嗅探到的音频/视频下载到 App 沙盒 Documents/Downloads，供「分享」使用
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    /// url -> 状态文案
    @Published var status: [String: String] = [:]

    private let downloadsDir: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KuaiGeDownloads", isDirectory: true)
    }()

    init() { ensureDirectory() }

    func download(_ media: SniffedMedia, store: SniffStore, completion: @escaping (URL?) -> Void) {
        guard let url = URL(string: media.url) else {
            status[media.url] = "链接无效"
            completion(nil)
            return
        }

        // 确保下载目录存在
        guard ensureDirectory() else {
            status[media.url] = "无法创建下载目录"
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        if let referer = media.referer, !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30

        status[media.url] = "下载中…"

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                let msg = error.localizedDescription
                DispatchQueue.main.async { self.status[media.url] = "网络错误：\(msg)" }
                completion(nil)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                DispatchQueue.main.async { self.status[media.url] = "服务器返回 \(code)" }
                completion(nil)
                return
            }

            guard let data = data, !data.isEmpty else {
                DispatchQueue.main.async { self.status[media.url] = "内容为空" }
                completion(nil)
                return
            }

            // 写入文件（带重试）
            let ext = media.fileExtension
            let timestamp = Int(Date().timeIntervalSince1970)
            let shortId = UUID().uuidString.prefix(6).lowercased()
            let name = "\(timestamp)_\(shortId).\(ext)"
            let dest = self.downloadsDir.appendingPathComponent(name)

            do {
                try data.write(to: dest, options: .atomic)
                store.markDownloaded(url: media.url, path: dest.path)
                let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                DispatchQueue.main.async { self.status[media.url] = "已保存 (\(sizeStr))" }
                completion(dest)
            } catch let writeError {
                // 重试一次：重新创建目录再写入
                _ = self.forceRecreateDirectory()
                do {
                    try data.write(to: dest, options: .atomic)
                    store.markDownloaded(url: media.url, path: dest.path)
                    let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                    DispatchQueue.main.async { self.status[media.url] = "已保存 (\(sizeStr))" }
                    completion(dest)
                } catch {
                    DispatchQueue.main.async {
                        self.status[media.url] = "写入失败：\(writeError.localizedDescription)"
                    }
                    completion(nil)
                }
            }
        }
        task.resume()
    }

    // MARK: - 目录管理

    /// 确保下载目录存在，返回是否成功
    @discardableResult
    private func ensureDirectory() -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: downloadsDir.path) { return true }
        do {
            try fm.createDirectory(at: downloadsDir, withIntermediateDirectories: true, attributes: nil)
            return true
        } catch {
            print("[DownloadManager] 创建目录失败: \(error)")
            return false
        }
    }

    /// 强制重建目录（用于重试逻辑）
    @discardableResult
    private func forceRecreateDirectory() -> Bool {
        let fm = FileManager.default
        try? fm.removeItem(atPath: downloadsDir.path)
        return ensureDirectory()
    }
}
