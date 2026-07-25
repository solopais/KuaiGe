import SwiftUI
import AVKit

/// 嗅探结果卡片（音频提取页 / 视频提取页 / 历史页 共用）
/// 发行级极简风格：清晰层级、精致按钮、专业排版
struct SniffCard: View {
    let item: SniffedMedia
    @ObservedObject var store: SniffStore
    @ObservedObject private var downloader = DownloadManager.shared
    @Binding var playingURL: String?

    @State private var showShareSheet = false
    @State private var shareItem: URL? = nil
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // ---- 第一行：文件名 + 类型标签 ----
            headerRow

            // ---- 域名 + 来源 ----
            subtitleRow

            // ---- URL 直链（等宽字体，可复制） ----
            urlBar

            // ---- 操作按钮组 ----
            actionRow

            // ---- 下载状态 ----
            statusRow
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Color.card)
        .cornerRadius(AppTheme.Radius.lg)
        .shadow(color: AppTheme.Shadow.card, radius: 6, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .stroke(AppTheme.Color.border, lineWidth: 0.5)
        )
        .sheet(isPresented: $showShareSheet) {
            if let url = shareItem {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - 头部：文件名 + 类型标签
    private var headerRow: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            // 媒体类型图标
            Image(systemName: item.mediaType == .audio ? "waveform" : "video.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.Color.primary)
                .frame(width: 28, height: 28)
                .background(AppTheme.Color.primaryLight)
                .cornerRadius(AppTheme.Radius.sm)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(AppTheme.Font.title2())
                    .foregroundColor(AppTheme.Color.textPrimary)
                    .lineLimit(2)

                HStack(spacing: AppTheme.Spacing.xs) {
                    TagView(text: item.mediaType == .audio ? "音频" : "视频",
                            style: item.mediaType == .audio ? .primary : .success)
                }
            }

            Spacer()
        }
    }

    // MARK: - 副标题：域名 + 来源 + 时间
    private var subtitleRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if !item.displayDomain.isEmpty {
                Image(systemName: "globe")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.Color.textTertiary)
                Text(item.displayDomain)
                    .font(AppTheme.Font.caption2())
                    .foregroundColor(AppTheme.Color.textTertiary)
                    .lineLimit(1)
            }

            Text("·")
                .foregroundColor(AppTheme.Color.textTertiary)

            Text(item.sourceLabel)
                .font(AppTheme.Font.caption2())
                .foregroundColor(AppTheme.Color.textTertiary)

            Text("·")
                .foregroundColor(AppTheme.Color.textTertiary)

            Text(item.detectedAtFormatted)
                .font(AppTheme.Font.caption2())
                .foregroundColor(AppTheme.Color.textTertiary)

            Spacer()
        }
    }

    // MARK: - URL 栏（点击可复制）
    private var urlBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .foregroundColor(copied ? AppTheme.Color.success : AppTheme.Color.textTertiary)

            Text(truncateURL(item.url, maxChars: 60))
                .font(AppTheme.Font.mono(11))
                .foregroundColor(AppTheme.Color.textSecondary)
                .lineLimit(1)

            Spacer()

            Button { copyURL() } label: {
                Text(copied ? "已复制" : "复制")
                    .font(AppTheme.Font.caption())
                    .foregroundColor(copied ? AppTheme.Color.success : AppTheme.Color.primary)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Color.surface)
        .cornerRadius(AppTheme.Radius.sm)
        // 删掉 .onTapGesture { copyURL() } —— 改用上方显式「复制」Button，防止整行点击都触发复制
    }

    // MARK: - 操作按钮行
    private var isDownloading: Bool { downloader.isDownloading(item.url) }
    private var isDownloaded: Bool { downloader.isDownloaded(item) }

    private var actionRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            // 播放 / 暂停
            compactAction(
                icon: playingURL == item.url ? "pause.fill" : "play.fill",
                label: playingURL == item.url ? "暂停" : "播放",
                tint: AppTheme.Color.primary
            ) {
                guard LicenseManager.shared.isPro else {
                    NotificationCenter.default.post(name: .kuaiGeRequirePro, object: nil)
                    return
                }
                playingURL = (playingURL == item.url) ? nil : item.url
            }

            // 下载 / 下载中 / 已下载（三态，避免重复下载）
            if isDownloaded {
                compactAction(
                    icon: "checkmark.circle.fill",
                    label: "已下载",
                    tint: AppTheme.Color.success
                ) { /* 已下载，不再触发下载 */ }
            } else if isDownloading {
                compactAction(
                    icon: "arrow.down.circle",
                    label: "下载中",
                    tint: AppTheme.Color.textTertiary
                ) { /* 下载中，忽略点击 */ }
            } else {
                compactAction(
                    icon: "arrow.down.to.line",
                    label: "下载",
                    tint: AppTheme.Color.textSecondary
                ) {
                    guard LicenseManager.shared.isPro else {
                        NotificationCenter.default.post(name: .kuaiGeRequirePro, object: nil)
                        return
                    }
                    downloader.download(item, store: store) { _ in }
                }
            }

            Spacer()

            // 分享（已下载时显示）→ 拉起系统分享面板（存到文件/分享到其他 App）
            if let path = item.downloadedLocalPath, downloader.isDownloaded(item) {
                compactAction(
                    icon: "square.and.arrow.up",
                    label: "分享",
                    tint: AppTheme.Color.success
                ) {
                    shareItem = URL(fileURLWithPath: path)
                    showShareSheet = true
                }
            }
        }
    }

    // MARK: - 下载状态（含进度条）
    private var statusRow: some View {
        Group {
            if let prog = downloader.progress[item.url] {
                // 下载中：进度条 + 百分比
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(value: prog)
                        .progressViewStyle(.linear)
                        .tint(AppTheme.Color.primary)
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 11))
                        Text("下载中 \(Int(prog * 100))%")
                            .font(AppTheme.Font.caption2())
                        Spacer()
                    }
                    .foregroundColor(AppTheme.Color.primary)
                }
                .padding(.top, AppTheme.Spacing.xs)
            } else if let st = downloader.status[item.url] {
                // 完成 / 失败：文案 + 图标
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: statusIcon(st))
                        .font(.system(size: 11))
                    Text(st)
                        .font(AppTheme.Font.caption2())
                }
                .foregroundColor(statusColor(st))
                .padding(.top, AppTheme.Spacing.xs)
            }
        }
    }

    // MARK: - 紧凑操作按钮（精确 hit area，防重叠）
    private func compactAction(icon: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(AppTheme.Font.caption())
            }
            .foregroundColor(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(tint.opacity(0.08))
            .cornerRadius(AppTheme.Radius.sm)
        }
        .buttonStyle(.plain)          // 去掉默认 Button 放大效果
        .contentShape(Rectangle())    // 精确命中：只响应视觉区域内的点击
    }

    // MARK: - 工具方法
    private func copyURL() {
        guard LicenseManager.shared.isPro else {
            NotificationCenter.default.post(name: .kuaiGeRequirePro, object: nil)
            return
        }
        UIPasteboard.general.string = item.url
        withAnimation(.easeInOut(duration: 0.15)) {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.15)) { copied = false }
        }
    }

    private func truncateURL(_ url: String, maxChars: Int) -> String {
        guard url.count > maxChars else { return url }
        return String(url.prefix(maxChars / 2)) + "…" + String(url.suffix(maxChars / 4))
    }

    private func statusIcon(_ st: String) -> String {
        if st.contains("失败") || st.contains("无效") || st.contains("错误") { return "xmark.circle.fill" }
        if st.contains("已保存") { return "checkmark.circle.fill" }
        if st.contains("下载中") { return "arrow.triangle.2.circlepath" }
        return "info.circle"
    }

    private func statusColor(_ st: String) -> Color {
        if st.contains("失败") || st.contains("无效") || st.contains("错误") { return AppTheme.Color.error }
        if st.contains("已保存") { return AppTheme.Color.success }
        return AppTheme.Color.textTertiary
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
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VideoPlayer(player: AVPlayer(url: url))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") { dismiss() }
                            .fontWeight(.medium)
                            .foregroundColor(AppTheme.Color.primary)
                    }
                }
        }
    }
}
