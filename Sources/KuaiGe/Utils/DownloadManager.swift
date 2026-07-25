import Foundation
import Combine

// MARK: - 下载代理（进度回调 + 完成落盘）
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var onProgress: ((String, Double) -> Void)?
    var onFinish: ((String, URL, URLResponse?) -> Void)?
    var onError: ((String, URLResponse?, Error?) -> Void)?

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64)
    {
        let key = downloadTask.originalRequest?.url?.absoluteString ?? ""
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.onProgress?(key, p) }
    }

    // 下载成功：系统把文件放在临时 location，必须在此回调内同步搬走
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL)
    {
        let key = downloadTask.originalRequest?.url?.absoluteString ?? ""
        let response = downloadTask.response
        // 立刻把临时文件移到安全位置（仍在回调线程，location 随后即失效）
        let tmpSafe = FileManager.default.temporaryDirectory
            .appendingPathComponent("kg_\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: tmpSafe)
            DispatchQueue.main.async { self.onFinish?(key, tmpSafe, response) }
        } catch {
            DispatchQueue.main.async { self.onError?(key, response, error) }
        }
    }

    // 失败（网络错误等）；成功时 error 为 nil，交给 didFinishDownloadingTo 处理
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        let key = task.originalRequest?.url?.absoluteString ?? ""
        let response = task.response
        DispatchQueue.main.async { self.onError?(key, response, error) }
    }
}

/// 把嗅探到的音频/视频下载到 App 沙盒 Documents/KuaiGeDownloads，供「分享」使用
/// 使用 URLSessionDownloadTask 流式下载（不占内存 + 实时进度），支持大视频文件
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    /// url -> 状态文案（"下载中 42%" / "已保存 (12.3 MB)" / "网络错误：…"）
    @Published var status: [String: String] = [:]
    /// url -> 下载进度 0.0~1.0（仅下载中时有值，完成/失败后移除）
    @Published var progress: [String: Double] = [:]

    private let downloadsDir: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KuaiGeDownloads", isDirectory: true)
    }()

    private let delegate = DownloadDelegate()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30      // 单次响应等待
        config.timeoutIntervalForResource = 600    // 整体传输上限（大视频给足 10 分钟）
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()

    /// 正在下载的 url 集合（去重，避免重复点击重复下载）
    private var activeURLs = Set<String>()
    private var activeMedia: [String: SniffedMedia] = [:]
    private var activeStores: [String: SniffStore] = [:]
    private var activeCompletions: [String: (URL?) -> Void] = [:]

    init() {
        ensureDirectory()
        wireDelegate()
    }

    // MARK: - 是否已下载（本地文件仍存在）
    func isDownloaded(_ media: SniffedMedia) -> Bool {
        guard let path = media.downloadedLocalPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// 是否正在下载
    func isDownloading(_ url: String) -> Bool {
        activeURLs.contains(url)
    }

    // MARK: - 开始下载
    func download(_ media: SniffedMedia, store: SniffStore, completion: @escaping (URL?) -> Void) {
        let key = media.url

        // 去重①：已经有本地文件 → 直接当作已完成，不重复下载
        if isDownloaded(media), let path = media.downloadedLocalPath {
            status[key] = fileSizeLabel(path: path)
            completion(URL(fileURLWithPath: path))
            return
        }

        // 去重②：正在下载中 → 忽略本次点击
        if activeURLs.contains(key) {
            return
        }

        guard let url = URL(string: key) else {
            status[key] = "链接无效"
            completion(nil)
            return
        }

        guard ensureDirectory() else {
            status[key] = "无法创建下载目录"
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

        activeURLs.insert(key)
        activeMedia[key] = media
        activeStores[key] = store
        activeCompletions[key] = completion
        status[key] = "下载中 0%"
        progress[key] = 0

        let task = session.downloadTask(with: request)
        task.resume()
    }

    // MARK: - 代理回调接线
    private func wireDelegate() {
        delegate.onProgress = { [weak self] key, p in
            guard let self = self else { return }
            self.progress[key] = p
            self.status[key] = "下载中 \(Int(p * 100))%"
        }

        delegate.onError = { [weak self] key, response, error in
            guard let self = self else { return }
            self.finishCleanup(key)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                self.status[key] = "服务器返回 \(http.statusCode)"
            } else if let error = error {
                self.status[key] = "网络错误：\(error.localizedDescription)"
            } else {
                self.status[key] = "下载失败"
            }
            let completion = self.activeCompletions.removeValue(forKey: key)
            self.clearContext(key)
            completion?(nil)
        }

        delegate.onFinish = { [weak self] key, tmpURL, response in
            guard let self = self else { return }
            self.finishCleanup(key)

            // 校验 HTTP 状态
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                self.status[key] = "服务器返回 \(http.statusCode)"
                try? FileManager.default.removeItem(at: tmpURL)
                let completion = self.activeCompletions.removeValue(forKey: key)
                self.clearContext(key)
                completion?(nil)
                return
            }

            let media = self.activeMedia[key]
            let store = self.activeStores[key]
            let completion = self.activeCompletions.removeValue(forKey: key)

            let ext = media?.fileExtension ?? "dat"
            let timestamp = Int(Date().timeIntervalSince1970)
            let shortId = UUID().uuidString.prefix(6).lowercased()
            let name = "\(timestamp)_\(shortId).\(ext)"
            let dest = self.downloadsDir.appendingPathComponent(name)

            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: tmpURL, to: dest)
                store?.markDownloaded(url: key, path: dest.path)
                self.status[key] = self.fileSizeLabel(path: dest.path)
                self.clearContext(key)
                completion?(dest)
            } catch {
                self.status[key] = "保存失败：\(error.localizedDescription)"
                try? FileManager.default.removeItem(at: tmpURL)
                self.clearContext(key)
                completion?(nil)
            }
        }
    }

    private func finishCleanup(_ key: String) {
        activeURLs.remove(key)
        progress.removeValue(forKey: key)
    }

    private func clearContext(_ key: String) {
        activeMedia.removeValue(forKey: key)
        activeStores.removeValue(forKey: key)
    }

    private func fileSizeLabel(path: String) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? Int64) ?? 0
        let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        return "已保存 (\(sizeStr))"
    }

    // MARK: - 目录管理
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
}
