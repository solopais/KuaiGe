import SwiftUI

/// 嗅探结果列表：复制链接 / 下载 / 分享到文件
struct SniffSheet: View {
    @ObservedObject var store: SniffStore
    @ObservedObject var downloader: DownloadManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if store.items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("还没有嗅探到音频")
                            .foregroundColor(.secondary)
                        Text("粘贴分享链接并打开页面，必要时点一下播放，音频链接会出现在这里。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                } else {
                    List {
                        ForEach(store.items) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(item.fileName)
                                        .font(.headline)
                                    Spacer()
                                    Text(item.source)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(4)
                                }

                                Text(item.url)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)

                                HStack(spacing: 10) {
                                    Button("复制链接") {
                                        UIPasteboard.general.string = item.url
                                    }
                                    .buttonStyle(.bordered)

                                    Button("下载") {
                                        downloader.download(item, store: store) { _ in }
                                    }
                                    .buttonStyle(.borderedProminent)

                                    if let path = item.downloadedLocalPath {
                                        Button("分享") {
                                            share(url: URL(fileURLWithPath: path))
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }

                                if let st = downloader.status[item.url] {
                                    Text(st)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("嗅探到的音频 (\(store.items.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !store.items.isEmpty {
                        Button("清空") { store.clear() }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func share(url: URL) {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(vc, animated: true)
        }
    }
}
