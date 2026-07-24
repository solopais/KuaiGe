import Foundation
import Combine

/// 把嗅探到的音频下载到 App 沙盒 Documents/Downloads，供「分享到文件」使用
final class DownloadManager: ObservableObject {
    /// url -> 状态文案
    @Published var status: [String: String] = [:]

    func download(_ media: SniffedMedia, store: SniffStore, completion: @escaping (URL?) -> Void) {
        guard let url = URL(string: media.url) else {
            status[media.url] = "链接无效"
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        if let referer = media.referer, !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }

        status[media.url] = "下载中…"
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { self.status[media.url] = "失败：\(error.localizedDescription)" }
                completion(nil)
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { self.status[media.url] = "空内容" }
                completion(nil)
                return
            }

            let fm = FileManager.default
            let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Downloads", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

            let ext = media.fileExtension
            let name = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(4)).\(ext)"
            let dest = dir.appendingPathComponent(name)

            do {
                try data.write(to: dest)
                store.markDownloaded(url: media.url, path: dest.path)
                DispatchQueue.main.async { self.status[media.url] = "已保存 · 可分享" }
                completion(dest)
            } catch {
                DispatchQueue.main.async { self.status[media.url] = "写文件失败" }
                completion(nil)
            }
        }
        task.resume()
    }
}
