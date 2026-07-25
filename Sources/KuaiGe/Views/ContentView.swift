import SwiftUI

struct ContentView: View {
    @StateObject private var store = SniffStore()
    @StateObject private var downloader = DownloadManager()
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // ---- Tab 0: 音频资源提取 ----
            ExtractorView(mode: .audio, store: store)
                .tabItem {
                    Image(systemName: "music.note")
                    Text("音频提取")
                }
                .tag(0)

            // ---- Tab 1: 视频资源提取 ----
            ExtractorView(mode: .video, store: store)
                .tabItem {
                    Image(systemName: "film")
                    Text("视频提取")
                }
                .tag(1)

            // ---- Tab 2: 历史记录 ----
            HistoryView(store: store, downloader: downloader)
                .tabItem {
                    Image(systemName: "clock.fill")
                    Text("历史")
                }
                .tag(2)
        }
        .tint(KawaiiTheme.Color.sakuraPink)
        .onAppear {
            // 外观配置
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(KawaiiTheme.Color.cardWhite)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance

            let navAppearance = UINavigationBarAppearance()
            navAppearance.configureWithOpaqueBackground()
            navAppearance.backgroundColor = UIColor(KawaiiTheme.Color.cream)
            navAppearance.titleTextAttributes = [.foregroundColor: UIColor(KawaiiTheme.Color.textDark)]
            UINavigationBar.appearance().standardAppearance = navAppearance
            UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        }
    }
}

// MARK: - 提取页（音频 / 视频 共用）：链接栏 + 浏览器 + 内联结果
struct ExtractorView: View {
    let mode: MediaKind
    @ObservedObject var store: SniffStore

    @State private var urlText: String = ""
    @State private var loadURL: URL? = nil
    @State private var isLoading: Bool = false
    @State private var progress: Double = 0
    @State private var playingURL: String? = nil

    private var filtered: [SniffedMedia] {
        mode == .audio ? store.audioItems : store.videoItems
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 链接栏（与浏览器同页，粘贴即加载，无需跳转重贴）
                linkBar

                Divider()

                // 浏览器
                BrowserView(
                    store: store,
                    loadURL: $loadURL,
                    isLoading: $isLoading,
                    estimatedProgress: $progress
                )

                if isLoading {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: KawaiiTheme.Color.sakuraPink))
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }

                // 内联结果
                if !filtered.isEmpty {
                    resultsHeader
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filtered) { item in
                                SniffCard(item: item, store: store, playingURL: $playingURL)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle(mode == .audio ? "🎵 音频提取" : "🎬 视频提取")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .sheet(isPresented: Binding(
                get: { playingURL != nil },
                set: { if !$0 { playingURL = nil } }
            )) {
                if let u = playingURL, let url = URL(string: u) {
                    MediaPlayerView(url: url)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: 链接栏
    private var linkBar: some View {
        HStack(spacing: 8) {
            TextField("粘贴链接…", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.URL)

            Button("粘贴") {
                if let s = UIPasteboard.general.string {
                    urlText = s
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(KawaiiTheme.Color.sakuraPink)

            Button("前往") { go() }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(KawaiiTheme.Color.sakuraPink)
                .cornerRadius(KawaiiTheme.Radius.pill)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(KawaiiTheme.Color.cream)
    }

    // MARK: 结果头部条
    private var resultsHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: mode == .audio ? "music.note" : "film")
                .font(.caption)
            Text("已嗅探到 \(filtered.count) 条\(mode == .audio ? "音频" : "视频")，点击播放或下载 →")
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            Button("清空") { withAnimation { store.clear() } }
                .font(.caption)
                .foregroundColor(KawaiiTheme.Color.coral)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [KawaiiTheme.Color.sakuraPink, KawaiiTheme.Color.coral],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(KawaiiTheme.Radius.pill)
        .padding(.horizontal)
        .padding(.bottom, 6)
        .animation(.spring(response: 0.3), value: filtered.count)
    }

    private func go() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let u = URL(string: trimmed) else { return }
        loadURL = u
    }
}
