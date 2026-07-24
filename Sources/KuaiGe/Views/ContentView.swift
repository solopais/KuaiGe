import SwiftUI

struct ContentView: View {
    @StateObject private var store = SniffStore()
    @StateObject private var downloader = DownloadManager()

    @State private var urlText: String = ""
    @State private var loadURL: URL? = nil
    @State private var isLoading: Bool = false
    @State private var progress: Double = 0
    @State private var showSniff: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 链接栏
                HStack(spacing: 8) {
                    TextField("粘贴分享链接，例如 m.kuaigeai.cn/...", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)

                    Button("粘贴") {
                        if let s = UIPasteboard.general.string {
                            urlText = s
                        }
                    }
                    .frame(minWidth: 44)

                    Button("前往") { go() }
                        .fontWeight(.semibold)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 6)

                Divider()

                // 浏览器
                BrowserView(
                    store: store,
                    loadURL: $loadURL,
                    isLoading: $isLoading,
                    estimatedProgress: $progress
                )
                .edgesIgnoringSafeArea(.bottom)

                if isLoading {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }
            }
            .navigationTitle("快歌 · 嗅探")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSniff = true
                    } label: {
                        Label("音频(\(store.items.count))", systemImage: "music.note.list")
                    }
                }
            }
            .sheet(isPresented: $showSniff) {
                SniffSheet(store: store, downloader: downloader)
            }
        }
        .navigationViewStyle(.stack)
    }

    private func go() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let u = URL(string: trimmed) else { return }
        loadURL = u
    }
}
