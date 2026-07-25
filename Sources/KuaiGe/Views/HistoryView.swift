import SwiftUI

/// 下载历史 + 收藏页
struct HistoryView: View {
    @ObservedObject var store: SniffStore
    @ObservedObject var downloader: DownloadManager

    @State private var historyItems: [HistoryEntry] = []

    var body: some View {
        NavigationView {
            Group {
                if historyItems.isEmpty {
                    emptyView
                } else {
                    historyList
                }
            }
            .background(KawaiiTheme.Color.cream.ignoresSafeArea())
            .navigationTitle("📚 历史")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadHistory() }
        }
    }

    // MARK: - 空状态
    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("📭")
                .font(.system(size: 56))
            Text("暂无历史记录")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(KawaiiTheme.Color.textDark)
            Text("下载的音频会出现在这里")
                .font(.subheadline)
                .foregroundColor(KawaiiTheme.Color.textLight)
            Spacer()
        }
    }

    // MARK: - 历史列表
    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(historyItems) { entry in
                    historyCard(entry)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("清空", role: .destructive) {
                    withAnimation {
                        historyItems.removeAll()
                        saveHistory()
                    }
                }
                .foregroundColor(KawaiiTheme.Color.coral)
            }
        }
    }

    // MARK: - 历史卡片
    private func historyCard(_ entry: HistoryEntry) -> some View {
        KawaiiCard(padding: 14) {
            HStack(spacing: 12) {
                // 图标
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundColor(KawaiiTheme.Color.sakuraPink)
                    .frame(width: 40, height: 40)
                    .background(KawaiiTheme.Color.sakuraPink.opacity(0.1))
                    .cornerRadius(KawaiiTheme.Radius.medium)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.fileName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(KawaiiTheme.Color.textDark)
                        .lineLimit(1)

                    Text(formatDate(entry.savedAt))
                        .font(.caption2)
                        .foregroundColor(KawaiiTheme.Color.textLight)

                    if let localPath = entry.localPath {
                        Text("已下载")
                            .font(.caption2)
                            .foregroundColor(KawaiiTheme.Color.mint.opacity(0.8))
                    } else {
                        Text(entry.url.prefix(60) + (entry.url.count > 60 ? "…" : ""))
                            .font(.caption2)
                            .foregroundColor(KawaiiTheme.Color.textLight.opacity(0.6))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // 操作
                if let localPath = entry.localPath, FileManager.default.fileExists(atPath: localPath) {
                    Button {
                        shareFile(localPath)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18))
                            .foregroundColor(KawaiiTheme.Color.skyBlue)
                    }
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation {
                    historyItems.removeAll { $0.id == entry.id }
                    saveHistory()
                }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: - 持久化
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "kuaige_history"),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            return
        }
        historyItems = decoded.sorted { $0.savedAt > $1.savedAt }
    }

    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(historyItems) {
            UserDefaults.standard.set(encoded, forKey: "kuaige_history")
        }
    }

    private func addHistoryItem(_ item: SniffedMedia) {
        let entry = HistoryEntry(
            url: item.url,
            fileName: item.fileName,
            source: item.source,
            localPath: item.downloadedLocalPath,
            savedAt: Date()
        )
        // 去重
        if !historyItems.contains(where: { $0.url == entry.url }) {
            historyItems.insert(entry, at: 0)
            saveHistory()
        }
    }

    // MARK: - 工具
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func shareFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(vc, animated: true)
        }
    }
}

// MARK: - 历史条目模型
struct HistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let url: String
    let fileName: String
    let source: String
    var localPath: String?
    let savedAt: Date

    init(id: UUID = UUID(), url: String, fileName: String, source: String, localPath: String?, savedAt: Date) {
        self.id = id
        self.url = url
        self.fileName = fileName
        self.source = source
        self.localPath = localPath
        self.savedAt = savedAt
    }
}
