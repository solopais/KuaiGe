import SwiftUI

/// 历史记录：展示所有嗅探到的音频/视频资源（可复制直链 / 播放 / 下载 / 左滑删除）
struct HistoryView: View {
    @ObservedObject var store: SniffStore
    @ObservedObject var downloader: DownloadManager

    @State private var playingURL: String? = nil

    var body: some View {
        NavigationView {
            Group {
                if store.items.isEmpty {
                    emptyView
                } else {
                    List {
                        ForEach(store.items) { item in
                            SniffCard(item: item, store: store, playingURL: $playingURL)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(KawaiiTheme.Color.cream)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        withAnimation {
                                            store.remove(url: item.url)
                                        }
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(KawaiiTheme.Color.cream.ignoresSafeArea())
            .navigationTitle("📚 历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !store.items.isEmpty {
                        Button("清空", role: .destructive) {
                            withAnimation { store.clear() }
                        }
                        .foregroundColor(KawaiiTheme.Color.coral)
                    }
                }
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

    // MARK: - 空状态
    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("📭")
                .font(.system(size: 56))
            Text("暂无记录")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(KawaiiTheme.Color.textDark)
            Text("在「音频提取 / 视频提取」里打开链接，\n嗅探到的资源会自动记录在这里")
                .font(.subheadline)
                .foregroundColor(KawaiiTheme.Color.textLight)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}
