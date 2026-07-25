import SwiftUI

/// 首页：欢迎 + 快速粘贴 + 最近嗅探
struct HomeView: View {
    @ObservedObject var store: SniffStore
    @ObservedObject var downloader: DownloadManager
    var onOpenSniff: () -> Void

    @State private var urlText: String = ""
    @State private var showPasteAnim = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // ---- 头部装饰区 ----
                headerSection
                    .padding(.top, 10)

                // ---- 快速粘贴区 ----
                quickPasteSection

                // ---- 最近嗅探（如果有）----
                if !store.items.isEmpty {
                    recentSniffsSection
                }

                // ---- 使用提示 ----
                tipsSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(KawaiiTheme.Color.cream.ignoresSafeArea())
    }

    // MARK: - 头部
    private var headerSection: some View {
        VStack(spacing: 12) {
            // 装饰性 emoji/图标
            Text("🎵")
                .font(.system(size: 52))

            Text("快歌 · 嗅探")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(KawaiiTheme.Color.textDark)

            Text("粘贴任意音乐链接，一键抓取音频")
                .font(.subheadline)
                .foregroundColor(KawaiiTheme.Color.textLight)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - 快速粘贴
    private var quickPasteSection: some View {
        KawaiiCard {
            VStack(spacing: 12) {
                TextField("🔗 粘贴分享链接…", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .font(.system(size: 15))

                HStack(spacing: 12) {
                    Button("📋 粘贴") {
                        if let s = UIPasteboard.general.string {
                            withAnimation(.spring(response: 0.3)) {
                                urlText = s
                                showPasteAnim = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                showPasteAnim = false
                            }
                        }
                    }
                    .buttonStyle(KawaiiButtonStyle(isPrimary: false))
                    .scaleEffect(showPasteAnim ? 1.08 : 1.0)

                    Button("🔍 去嗅探") {
                        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onOpenSniff()
                        }
                    }
                    .buttonStyle(KawaiiButtonStyle())
                }
            }
        }
    }

    // MARK: - 最近嗅探
    private var recentSniffsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("✨ 最近嗅探")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(KawaiiTheme.Color.textDark)
                Spacer()
                Text("\(store.items.count) 条")
                    .font(.caption)
                    .foregroundColor(KawaiiTheme.Color.textLight)
            }

            ForEach(store.items.prefix(3)) { item in
                sniffRow(item)
            }

            if store.items.count > 3 {
                Button("查看全部 \(store.items.count) 条 →") {
                    onOpenSniff()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(KawaiiTheme.Color.sakuraPink)
            }
        }
    }

    private func sniffRow(_ item: SniffedMedia) -> some View {
        KawaiiCard(padding: 12) {
            HStack(spacing: 10) {
                // 图标
                Image(systemName: iconForSource(item.source))
                    .font(.title2)
                    .foregroundColor(KawaiiTheme.Color.sakuraPink)
                    .frame(width: 36, height: 36)
                    .background(KawaiiTheme.Color.sakuraPink.opacity(0.1))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.fileName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(KawaiiTheme.Color.textDark)
                        .lineLimit(1)

                    Text(item.source)
                        .font(.caption2)
                        .foregroundColor(KawaiiTheme.Color.textLight)

                    Text(item.url)
                        .font(.caption2)
                        .foregroundColor(KawaiiTheme.Color.textLight.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer()

                // 复制按钮
                Button {
                    UIPasteboard.general.string = item.url
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 18))
                        .foregroundColor(KawaiiTheme.Color.skyBlue)
                }
            }
        }
    }

    // MARK: - 提示
    private var tipsSection: some View {
        VStack(spacing: 8) {
            Text("💡 支持的平台")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(KawaiiTheme.Color.textDark)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                KawaiiTag(text: "快歌", color: KawaiiTheme.Color.coral.opacity(0.15))
                KawaiiTag(text: "网易云", color: KawaiiTheme.Color.mint.opacity(0.4))
                KawaiiTag(text: "QQ音乐", color: KawaiiTheme.Color.skyBlue.opacity(0.2))
                KawaiiTag(text: "酷狗", color: KawaiiTheme.Color.lavender)
                KawaiiTag(text: "酷我", color: KawaiiTheme.Color.cream)
                KawaiiTag(text: "B站", color: KawaiiTheme.Color.sakuraPink.opacity(0.15))
            }
        }
        .padding(.top, 8)
    }

    private func iconForSource(_ source: String) -> String {
        switch source {
        case "media-src", "media-element-scan", "nested-source": "waveform"
        case "fetch", "fetch-resp": "arrow.down.circle"
        case "xhr": "network"
        case "blob-audio", "blob-video": "circle.dotted"
        default: "music.note"
        }
    }
}
