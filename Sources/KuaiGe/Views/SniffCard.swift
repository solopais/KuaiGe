import SwiftUI
import AVKit

/// 嗅探结果卡片（音频提取页 / 视频提取页 / 历史页 共用）
/// 提供：复制直链、播放（内嵌播放器）、下载、分享、下载状态展示
struct SniffCard: View {
    let item: SniffedMedia
    @ObservedObject var store: SniffStore
    @Binding var playingURL: String?

    @State private var showShareSheet = false
    @State private var shareItem: URL? = nil

    var body: some View {
        KawaiiCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                // 顶部：文件名 + 来源标签
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.fileName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(KawaiiTheme.Color.textDark)
                            .lineLimit(2)

                        Text(sourceLabel(item.source))
                            .font(.caption2)
                            .foregroundColor(KawaiiTheme.Color.textLight.opacity(0.8))
                    }

                    Spacer()

                    KawaiiTag(text: sourceTag(item.source), color: tagColor(item.source))
                }

                // URL（可折叠直链）
                Text(item.url)
                    .font(.caption)
                    .foregroundColor(KawaiiTheme.Color.textLight.opacity(0.6))
                    .lineLimit(2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(KawaiiTheme.Color.cream)
                    .cornerRadius(KawaiiTheme.Radius.small)

                // 操作按钮行
                HStack(spacing: 10) {
                    actionButton(
                        icon: "doc.on.doc",
                        label: "复制",
                        color: KawaiiTheme.Color.skyBlue
                    ) {
                        UIPasteboard.general.string = item.url
                    }

                    actionButton(
                        icon: playingURL == item.url ? "pause.circle.fill" : "play.circle.fill",
                        label: playingURL == item.url ? "暂停" : "播放",
                        color: KawaiiTheme.Color.sakuraPink
                    ) {
                        playingURL = (playingURL == item.url) ? nil : item.url
                    }

                    actionButton(
                        icon: "arrow.down.circle.fill",
                        label: "下载",
                        color: KawaiiTheme.Color.mint
                    ) {
                        DownloadManager.shared.download(item, store: store) { _ in }
                    }

                    if let path = item.downloadedLocalPath {
                        actionButton(
                            icon: "square.and.arrow.up",
                            label: "分享",
                            color: KawaiiTheme.Color.lavender
                        ) {
                            shareItem = URL(fileURLWithPath: path)
                            showShareSheet = true
                        }
                    }
                }

                // 下载状态
                if let st = DownloadManager.shared.status[item.url] {
                    HStack(spacing: 4) {
                        Image(systemName: st.contains("失败") || st.contains("无效") ? "xmark.circle" :
                              st.contains("已保存") ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                            .font(.caption2)
                        Text(st)
                            .font(.caption2)
                    }
                    .foregroundColor(statusColor(st))
                    .padding(.top, 2)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareItem {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - 操作按钮组件
    private func actionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color.opacity(0.12))
            .cornerRadius(KawaiiTheme.Radius.pill)
        }
    }

    // MARK: - 辅助方法
    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "media-src": return "媒体元素 src"
        case "fetch": return "Fetch 请求"
        case "fetch-resp": return "Fetch 响应（媒体）"
        case "xhr": return "XHR 请求"
        case "media-element-scan": return "页面扫描发现"
        case "nested-source": return "嵌套 <source>"
        case "source-attr": return "属性赋值拦截"
        case "blob-audio": return "Blob 音频流"
        case "blob-video": return "Blob 视频流"
        default: return source
        }
    }

    private func sourceTag(_ source: String) -> String {
        if source.contains("blob") { return "Blob" }
        if source.contains("media") { return "媒体" }
        if source.contains("fetch") { return "Fetch" }
        if source.contains("xhr") { return "XHR" }
        return "其他"
    }

    private func tagColor(_ source: String) -> Color {
        if source.contains("blob") { return KawaiiTheme.Color.mint.opacity(0.4) }
        if source.contains("media") { return KawaiiTheme.Color.sakuraPink.opacity(0.15) }
        if source.contains("fetch") { return KawaiiTheme.Color.skyBlue.opacity(0.2) }
        if source.contains("xhr") { return KawaiiTheme.Color.lavender }
        return KawaiiTheme.Color.cream
    }

    private func statusColor(_ status: String) -> Color {
        if status.contains("失败") || status.contains("无效") { return KawaiiTheme.Color.coral }
        if status.contains("已保存") { return KawaiiTheme.Color.mint }
        return KawaiiTheme.Color.textLight
    }
}

// MARK: - 系统分享面板封装
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 内嵌播放器（音频 / 视频通用）
struct MediaPlayerView: View {
    let url: URL

    var body: some View {
        VideoPlayer(player: AVPlayer(url: url))
            .edgesIgnoringSafeArea(.all)
    }
}
