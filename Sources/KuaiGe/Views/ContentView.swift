import SwiftUI

struct ContentView: View {
    @StateObject private var store = SniffStore()
    @StateObject private var downloader = DownloadManager()
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ExtractorView(mode: .audio, store: store)
                .tabItem {
                    Label("音频", systemImage: "waveform")
                }
                .tag(0)

            ExtractorView(mode: .video, store: store)
                .tabItem {
                    Label("视频", systemImage: "film")
                }
                .tag(1)

            HistoryView(store: store, downloader: downloader)
                .tabItem {
                    Label("历史", systemImage: "clock")
                }
                .tag(2)
        }
        .tint(AppTheme.Color.primary)
        .onAppear { applyGlobalAppearance() }
    }

    private func applyGlobalAppearance() {
        // TabBar
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        tabAppearance.backgroundColor = UIColor(AppTheme.Color.surface)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // NavigationBar
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(AppTheme.Color.background)
        navAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(AppTheme.Color.textPrimary),
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(AppTheme.Color.textPrimary)
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    }
}

// MARK: - 提取页（音频 / 视频 共用）
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
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索栏风格的链接输入
                searchBar

                // 进度条
                if isLoading {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: AppTheme.Color.primary))
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.vertical, AppTheme.Spacing.xs)
                }

                // 浏览器 + 结果列表（分屏布局）
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        // 浏览器区域（占主要空间）
                        BrowserView(
                            store: store,
                            loadURL: $loadURL,
                            isLoading: $isLoading,
                            estimatedProgress: $progress
                        )
                        .frame(height: geo.size.height * (filtered.isEmpty ? 1.0 : 0.5))

                        // 结果列表（有数据时显示）
                        if !filtered.isEmpty {
                            Divider()

                            ScrollView {
                                LazyVStack(spacing: AppTheme.Spacing.md) {
                                    ForEach(filtered) { item in
                                        SniffCard(item: item, store: store, playingURL: $playingURL)
                                    }
                                }
                                .padding(.horizontal, AppTheme.Spacing.lg)
                                .padding(.vertical, AppTheme.Spacing.md)
                            }
                            .frame(maxHeight: geo.size.height * 0.5)
                        }
                    }
                }
            }
            .background(AppTheme.Color.background.ignoresSafeArea())
            .navigationTitle(mode == .audio ? "音频提取" : "视频提取")
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

            // 覆盖层：空状态引导
            if !isLoading && loadURL == nil && filtered.isEmpty {
                emptyGuide
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - 搜索栏
    private var searchBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.Color.textTertiary)

            TextField("粘贴网页链接，在此页直接加载", text: $urlText)
                .textFieldStyle(.plain)
                .font(AppTheme.Font.body())
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.URL)
                .onSubmit { go() }

            if !urlText.isEmpty {
                Button { urlText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.Color.textTertiary)
                }
            }

            Button { go() } label: {
                Text("前往")
                    .font(AppTheme.Font.caption())
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.Color.textOnPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(AppTheme.Color.primary)
                    .cornerRadius(AppTheme.Radius.sm)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(AppTheme.Color.borderStrong, lineWidth: 0.5)
        )
        .cornerRadius(AppTheme.Radius.md)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.top, AppTheme.Spacing.sm)
        .padding(.bottom, AppTheme.Spacing.xs)
    }

    // MARK: - 空状态引导
    private var emptyGuide: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer().frame(height: 80)

            // 图标
            ZStack {
                Circle()
                    .fill(AppTheme.Color.primaryLight)
                    .frame(width: 72, height: 72)

                Image(systemName: mode == .audio ? "waveform" : "film")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(AppTheme.Color.primary)
            }

            VStack(spacing: AppTheme.Spacing.sm) {
                Text(mode == .audio ? "提取页面中的音频" : "提取页面中的视频")
                    .font(AppTheme.Font.title2())

                Text("粘贴包含音视频的网页链接，\n自动嗅探并获取直链")
                    .font(AppTheme.Font.body())
                    .foregroundColor(AppTheme.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
    }

    private func go() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let u = URL(string: trimmed) else { return }
        loadURL = u
    }
}
