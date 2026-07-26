import SwiftUI

/// 历史记录：展示所有嗅探到的音频/视频资源
struct HistoryView: View {
    @ObservedObject var store: SniffStore
    @ObservedObject var downloader: DownloadManager
    @ObservedObject private var license = LicenseManager.shared

    @State private var playingURL: String? = nil
    @State private var showClearAlert = false
    @State private var exported = false

    var body: some View {
        AppNav {
            Group {
                if store.items.isEmpty {
                    emptyView
                } else {
                    listView
                }
            }
            .background(AppTheme.Color.background.ignoresSafeArea())
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .if(!store.items.isEmpty) {
                $0.toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            if license.isPro {
                                exportAllLinks()
                            } else {
                                NotificationCenter.default.post(name: .kuaiGeRequirePro, object: nil)
                            }
                        } label: {
                            Label("导出直链", systemImage: "square.and.arrow.up")
                                .font(AppTheme.Font.caption())
                                .foregroundColor(license.isPro ? AppTheme.Color.primary : AppTheme.Color.textTertiary)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            if license.isPro {
                                showClearAlert = true
                            } else {
                                NotificationCenter.default.post(name: .kuaiGeRequirePro, object: nil)
                            }
                        } label: {
                            Text("清空")
                                .font(AppTheme.Font.caption())
                                .foregroundColor(AppTheme.Color.error)
                        }
                    }
                }
            }
            .alert("清空记录", isPresented: $showClearAlert) {
                Button("取消", role: .cancel) {}
                Button("清空全部", role: .destructive) {
                    // 清空所有已下载文件和缓存（释放手机存储）
                    downloader.clearAllDownloads()
                    // 同步清除 DownloadManager 内存中的状态
                    withAnimation(.easeInOut(duration: 0.25)) { store.clear() }
                }
            } message: {
                Text("确定要删除全部 \(store.items.count) 条嗅探记录吗？此操作不可撤销。")
            }
            .sheet(isPresented: Binding(
                get: { playingURL != nil },
                set: { if !$0 { playingURL = nil } }
            )) {
                if let u = playingURL, let url = URL(string: u) {
                    MediaPlayerView(url: url)
                }
            }
            .overlay(alignment: .bottom) {
                if exported {
                    Text("已复制 \(store.items.count) 条直链到剪贴板")
                        .font(AppTheme.Font.caption())
                        .foregroundColor(AppTheme.Color.textOnPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(AppTheme.Color.textPrimary.opacity(0.9))
                        .cornerRadius(AppTheme.Radius.pill)
                        .padding(.bottom, 24)
                        .transition(.opacity)
                        .animation(.easeInOut, value: exported)
                }
            }
        }
    }

    // MARK: - 专业版：导出全部直链
    private func exportAllLinks() {
        let links = store.items.map { $0.url }.joined(separator: "\n")
        UIPasteboard.general.string = links
        exported = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { exported = false }
    }

    // MARK: - 列表视图
    private var listView: some View {
        List {
            ForEach(store.items) { item in
                SniffCard(item: item, store: store, playingURL: $playingURL)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: AppTheme.Spacing.sm,
                        leading: AppTheme.Spacing.lg,
                        bottom: AppTheme.Spacing.sm,
                        trailing: AppTheme.Spacing.lg
                    ))
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                store.remove(url: item.url)
                            }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .hideScrollContentBackground()
    }

    // MARK: - 空状态
    private var emptyView: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppTheme.Color.surface)
                    .frame(width: 80, height: 80)

                Image(systemName: "clock.badge.xmark")
                    .font(.system(size: 30, weight: .light))
                    .foregroundColor(AppTheme.Color.textTertiary)
            }

            VStack(spacing: AppTheme.Spacing.sm) {
                Text("暂无记录")
                    .font(AppTheme.Font.title1())

                Text("在「音频」或「视频」页面打开链接后，\n嗅探到的资源会自动保存在这里")
                    .font(AppTheme.Font.body())
                    .foregroundColor(AppTheme.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
    }
}
