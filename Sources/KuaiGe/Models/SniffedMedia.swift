import Foundation

/// 嗅探到的媒体资源（音频文件 / COS 远程链接）
struct SniffedMedia: Identifiable, Hashable {
    let id = UUID()
    let url: String
    /// 捕获来源：media-src / fetch / fetch-resp / xhr / media-element
    let source: String
    let referer: String?
    let detectedAt: Date
    var downloadedLocalPath: String? = nil

    /// 从 URL 推断一个可读的文件名
    var fileName: String {
        let pathOnly = url.split(separator: "?").first ?? ""
        let last = pathOnly.split(separator: "/").last ?? "audio"
        return last.isEmpty ? "audio" : String(last)
    }

    var fileExtension: String {
        let pathOnly = url.split(separator: "?").first ?? ""
        let parts = pathOnly.split(separator: ".")
        guard parts.count > 1 else { return "mp3" }
        return String(parts.last ?? "mp3").lowercased()
    }
}
