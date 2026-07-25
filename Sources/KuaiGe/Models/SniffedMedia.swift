import Foundation

/// 媒体类型（用于区分音频 / 视频，决定归属「音频提取」还是「视频提取」页）
enum MediaKind: String, Codable, Hashable {
    case audio
    case video
    case other
}

/// 嗅探到的媒体资源（音频 / 视频 直链）
struct SniffedMedia: Identifiable, Hashable {
    let id = UUID()
    let url: String
    /// 捕获来源：media-src / fetch / fetch-resp / xhr / media-element / nested-source / source-attr / blob-audio / blob-video
    let source: String
    let referer: String?
    let mediaType: MediaKind
    let detectedAt: Date
    var downloadedLocalPath: String? = nil

    init(url: String, source: String, referer: String?, mediaType: MediaKind, detectedAt: Date = Date()) {
        self.url = url
        self.source = source
        self.referer = referer
        self.mediaType = mediaType
        self.detectedAt = detectedAt
    }

    // MARK: - 智能文件名提取

    /// 媒体扩展名集合（用于从 URL path 中识别真实文件名）
    private static let mediaExtensions: Set<String> = [
        "mp3", "m4a", "flac", "wav", "ogg", "aac", "wma", "ape",
        "mp4", "m4v", "mkv", "avi", "mov", "webm", "flv", "3gp",
        "m3u8", "ts", "f4v"
    ]

    /// 从 URL 提取可读的文件名（优先找带媒体扩展名的段，避免 hash 串）
    var fileName: String {
        let pathOnly = url.split(separator: "?").first ?? ""

        // 1. 按 / 分割，倒序查找第一个带已知媒体扩展名的段
        let segments = pathOnly.split(separator: "/").reversed()
        for segment in segments {
            let s = String(segment)
            let ext = extensionFromPath(s)
            if !SniffedMedia.mediaExtensions.contains(ext) { continue }
            // 找到了带 .mp3/.mp4 等的段——这就是真实文件名
            return decoded(s)
        }

        // 2. 没有找到媒体扩展名 → 取最后一段，但限制长度并清理
        let last = segments.first.map(String.init) ?? ""
        let cleaned = decoded(last)

        // 如果看起来像 hash（纯字母数字且 >16 字符），用语义化名称替代
        if cleaned.count > 18 && cleaned.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
            return mediaType == .audio ? "音频资源" : "视频资源"
        }

        return cleaned.isEmpty ? (mediaType == .audio ? "音频资源" : "视频资源") : cleaned
    }

    /// 文件扩展名
    var fileExtension: String {
        let pathOnly = url.split(separator: "?").first ?? ""
        let lastSegment = pathOnly.split(separator: "/").last ?? ""
        let ext = extensionFromPath(String(lastSegment))
        return SniffedMedia.mediaExtensions.contains(ext) ? ext : (mediaType == .audio ? "mp3" : "mp4")
    }

    /// 来源域名（用于副标题展示）
    var displayDomain: String {
        guard let u = URL(string: url) else { return "" }
        return u.host ?? ""
    }

    /// 来源的中文描述
    var sourceLabel: String {
        switch source {
        case "media-src":      return "媒体元素"
        case "fetch":          return "网络请求"
        case "fetch-resp":     return "响应内容"
        case "xhr":            return "XHR 请求"
        case "media-element-scan": return "页面扫描"
        case "nested-source":  return "嵌套源"
        case "source-attr":    return "属性拦截"
        case "blob-audio":     return "Blob 音频流"
        case "blob-video":     return "Blob 视频流"
        case "dom-scan":       return "DOM 扫描"
        case "performance-api": return "性能 API"
        case "network-layer":  return "网络层拦截"
        case "hls-segment":    return "HLS 分片"
        case "hls-manifest":   return "HLS 清单"
        default:               return source
        }
    }

    // MARK: - 内部工具

    private func extensionFromPath(_ path: String) -> String {
        guard let dotIndex = path.lastIndex(of: ".") else { return "" }
        return String(path[path.index(after: dotIndex)...]).lowercased()
    }

    private func decoded(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }
}
