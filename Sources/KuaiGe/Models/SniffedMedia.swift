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

    /// 从 URL 推断一个可读的文件名
    var fileName: String {
        let pathOnly = url.split(separator: "?").first ?? ""
        let last = pathOnly.split(separator: "/").last ?? "media"
        return last.isEmpty ? "media" : String(last)
    }

    var fileExtension: String {
        let pathOnly = url.split(separator: "?").first ?? ""
        let parts = pathOnly.split(separator: ".")
        guard parts.count > 1 else { return "mp3" }
        return String(parts.last ?? "mp3").lowercased()
    }
}
