import SwiftUI

/// 历史记录：展示所有嗅探到的音频/视频资源
struct HistoryView: View {
    @ObservedObject var store: SniffStore
    @ObservedObject var downloader: DownloadManager

    @State private var playingURL: String? = nil
    @State private var showClearAlert = false

    var body: some View {
        NavigationStack {
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
            .toolbar {
                if !store.items.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showClearAlert = true } label: {
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
        }
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
        .scrollContentBackground(.hidden)
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
