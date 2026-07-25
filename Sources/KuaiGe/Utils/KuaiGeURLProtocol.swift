import Foundation

/// 网络层媒体嗅探引擎 —— 对标浏览器扩展的 `chrome.webRequest` / `devtools.network` API
///
/// 核心优势（JS 注入无法做到的）：
/// 1. 在 network 层看到**所有** HTTP 请求/响应，不受 JS 执行环境限制
/// 2. 即使目标页面有反自动化检测导致 JS 脚本不执行，network layer 照样能抓到媒体
/// 3. 能读取完整的 Content-Type + 响应体 magic bytes 做精确识别
/// 4. 不依赖 DOM、不受 CSP/ CORS 策略影响
///
/// 使用方式：在 BrowserView.makeUIView 中调用 `KuaiGeURLProtocol.register(store:)`
class KuaiGeURLProtocol: URLProtocol {

    // MARK: - 常量定义

    /// 媒体相关的 Content-Type 关键词
    static let mediaContentTypes: [String: String] = [
        "video/": "video",
        "audio/": "audio",
        "mpegurl": "video",        // HLS/m3u8
        "m3u8": "video",
        "x-mpegurl": "video",
        "mpd+xml": "video",        // DASH
        "dash+xml": "video",
        // 容器格式 MIME
        "mp4": "video",
        "quicktime": "video",
        "webm": "video",
        "ogg": "video",            // ogg 可能是视频也可能是音频
        // 音频格式 MIME
        "x-m4a": "audio",
        "flac": "audio",
        "wav": "audio",
        "aac": "audio",
        "mp3": "audio",
        "aiff": "audio",
        "ms-wma": "audio",
        // 二进制流（需要 magic bytes 二次确认）
        "octet-stream": "unknown",
    ]

    /// 明确是媒体的文件扩展名 → 类型映射
    static let mediaExtensions: [String: String] = [
        // 视频
        "mp4": "video", "webm": "video", "mkv": "video", "avi": "video",
        "mov": "video", "ts": "video", "m3u8": "video", "m3u": "video",
        "mpd": "video", "f4m": "video", "ogv": "video",
        // 音频
        "mp3": "audio", "m4a": "audio", "aac": "audio", "wav": "audio",
        "flac": "audio", "ogg": "audio", "opus": "audio", "wma": "audio",
        "ape": "audio", "amr": "audio", "aiff": "audio", "au": "audio", "ra": "audio",
    ]

    /// 明确跳过的非媒体扩展名（静态资源/文档/字体等）
    private static let skipExtensions: Set<String> = [
        "js", "mjs", "css", "html", "htm", "json", "php", "asp", "aspx", "jsp",
        "woff", "woff2", "ttf", "otf", "eot",
        "png", "jpeg", "jpg", "gif", "svg", "ico", "webp", "avif",
        "xml", "wasm", "map", "txt", "md", "manifest",
        "swf", "pdf", "doc", "docx", "xls", "xlsx"
    ]

    /// URL 中包含这些关键词时值得检查（即使扩展名不匹配）
    private static let suspiciousKeywords: Set<String> = [
        "/play", "/stream", "/media", "/download", "/video", "/audio",
        ".mp4?", ".m3u8?", ".flv?", "/hls/", "/dash/",
        "cdn", "vod", "cos.", "oss-", "obs.",
        "playwm", "playaddr", "videoplayback"
    ]

    // MARK: - 回调

    /// 检测到媒体资源时的回调：(url, source, mediaTypeString)
    static var onMediaDetected: ((String, String, String) -> Void)?

    // MARK: - NSURLProtocol 重载

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url,
              let scheme = url.scheme?.lowercased() else { return false }

        // 只拦截 http/https
        guard scheme == "http" || scheme == "https" else { return false }

        // 防止递归：已标记的请求不再处理
        if property(forKey: "KuaiGeHandled", in: request) != nil { return false }

        // ===== 快速预筛 =====

        let ext = url.pathExtension.lowercased()

        // 1) 明确跳过的扩展名 → 直接放行
        if !ext.isEmpty && skipExtensions.contains(ext) { return false }

        // 2) 明确是媒体扩展名 → 拦截！
        if !ext.isEmpty && mediaExtensions[ext] != nil { return true }

        // 3) URL 中含可疑关键词 → 拦截（稍后在 response 中确认）
        let urlString = url.absoluteString.lowercased()
        for keyword in suspiciousKeywords where urlString.contains(keyword) {
            return true
        }

        return false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    // MARK: - 请求处理

    private var dataTask: URLSessionDataTask?

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError:
                NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL))
            return
        }

        // 标记请求防止递归（URLProtocol.setProperty 类方法需传 NSMutableURLRequest）
        let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty("true", forKey: "KuaiGeHandled", in: mutableRequest)
        let finalReq: URLRequest = mutableRequest as URLRequest
        finalRequest = finalReq

        // 用原始请求的 headers 创建新任务
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = request.allHTTPHeaderFields ?? [:]
        let session = URLSession(configuration: config)

        dataTask = session.dataTask(with: finalReq) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }

            // ★ 核心：在 network 层检测媒体资源
            if let httpResponse = response as? HTTPURLResponse {
                self.inspectResponse(url: url, response: httpResponse, data: data)
            }

            // 转发响应给 WebView
            if let resp = response {
                self.client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            }
            if let body = data {
                self.client?.urlProtocol(self, didLoad: body)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        dataTask?.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
    }

    // MARK: - 私有

    /// 保存标记后的最终请求引用
    private var finalRequest: URLRequest?

    /// 核心：检测响应是否为媒体资源并上报
    private func inspectResponse(url: URL, response: HTTPURLResponse, data: Data?) {
        let contentType = (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let ext = url.pathExtension.lowercased()
        let contentLength = response.value(forHTTPHeaderField: "Content-Length")

        var detectedType: String? = nil

        // ===== 第一层：Content-Type 判断 =====
        for (keyword, type) in Self.mediaContentTypes where contentType.contains(keyword) {
            if keyword != "octet-stream" && keyword != "unknown" {
                detectedType = type
                break
            } else if keyword == "octet-stream" {
                // octet-stream 需要二次确认（见下面的 magic bytes 检测）
                break
            }
        }

        // ===== 第二层：扩展名判断（补充 Content-Type 缺失的情况）=====
        if detectedType == nil, let extType = Self.mediaExtensions[ext] {
            detectedType = extType
        }

        // ===== 第三层：Magic Bytes（文件头签名）判断 =====
        // 对 octet-stream 或无 Content-Type 的二进制响应做精确识别
        if detectedType == nil,
           contentType.isEmpty || contentType.contains("octet-stream") ||
           contentType.contains("binary"),
           let data = data, data.count >= 8 {
            detectedType = detectByMagicBytes(data)
        }

        // ===== 第四层：URL 特征启发式（最后兜底）=====
        if detectedType == nil {
            let urlString = url.absoluteString.lowercased()
            if urlString.contains(".mp4") || urlString.contains("playwm") ||
               urlString.contains("playaddr") || urlString.contains("videoplayback") {
                detectedType = "video"
            } else if urlString.contains(".mp3") || urlString.contains(".m4a") ||
                      urlString.contains(".flac") || urlString.contains(".aac") {
                detectedType = "audio"
            }
        }

        // ===== 上报检测结果 =====
        if let type = detectedType {
            #if DEBUG
            print("[KuaiGe-Net] \((type == "video" ? "🎬" : "🎵")) \(url.lastPathComponent)" +
                  " | CT:\(contentType.prefix(40)) | Size:\(contentLength ?? "?") | Source: network-layer")
            #endif
            Self.onMediaDetected?(url.absoluteString, "network-layer", type)
        }
    }

    /// 通过文件头 magic bytes 识别媒体类型
    private func detectByMagicBytes(_ data: Data) -> String? {
        guard data.count >= 8 else { return nil }
        let h = Array(data.prefix(16))

        // MP4 / QuickTime / M4A: ...ftyp (偏移 4 处)
        if h.count >= 8 &&
           h[4] == 0x66 && h[5] == 0x74 && h[6] == 0x79 && h[7] == 0x70 { // "ftyp"
            // 进一步区分 ftyp 后面的 brand
            if h.count >= 12 {
                let brand = String(bytes: h[8..<12], encoding: .ascii) ?? ""
                if brand.contains("M4A") || brand.contains("M4B") || brand.contains("mp42") ||
                   brand.contains("isom") || brand.contains("iso2") {
                    // M4A/mp42/isom 可能是音频或视频，按扩展名或默认 video
                    return "video" // 大多数 ftyp 是视频
                }
                if brand.contains("mp41") { return "video" }
                if brand.contains("3gp") || brand.contains("3g2") { return "video" }
            }
            return "video"
        }

        // ID3v2 (MP3): 49 44 33 ("ID3")
        if h[0] == 0x49 && h[1] == 0x44 && h[2] == 0x33 { return "audio" }

        // FLAC: 66 4C 61 43 ("fLaC")
        if h[0] == 0x66 && h[1] == 0x4C && h[2] == 0x61 && h[3] == 0x43 { return "audio" }

        // WebM: 1A 45 DF A3 (EBML header)
        if h[0] == 0x1A && h[1] == 0x45 && h[2] == 0xDF && h[3] == 0xA3 { return "video" }

        // Ogg: 4F 67 67 53 ("OggS")
        if h[0] == 0x4F && h[1] == 0x67 && h[2] == 0x67 && h[3] == 0x53 { return "audio" }

        // RIFF (WAV/AVI): 52 49 46 46
        if h[0] == 0x52 && h[1] == 0x49 && h[2] == 0x46 && h[3] == 0x46 {
            if h.count >= 12 {
                // WAVE = audio, AVI = video
                if h[8] == 0x57 && h[9] == 0x41 && h[10] == 0x56 && h[11] == 0x45 { return "audio" }
                if h[8] == 0x41 && h[9] == 0x56 && h[10] == 0x49 && h[11] == 0x20 { return "video" }
            }
        }

        // MPEG-TS (TS): 0x47 sync byte (每个包 188 字节开头)
        if h[0] == 0x47 { return "video" }

        return nil
    }

    // MARK: - 注册管理

    private static var isRegistered = false

    /// 注册 Protocol 并设置回调
    static func register(onMediaDetected: @escaping (String, String, String) -> Void) {
        guard !isRegistered else { return }
        self.onMediaDetected = onMediaDetected
        URLProtocol.registerClass(self)
        isRegistered = true
        #if DEBUG
        print("[KuaiGe-Net] ✅ 网络层嗅探引擎已注册")
        #endif
    }

    /// 注销 Protocol（在 WebView 销毁时调用）
    static func unregister() {
        guard isRegistered else { return }
        URLProtocol.unregisterClass(self)
        onMediaDetected = nil
        isRegistered = false
    }
}
