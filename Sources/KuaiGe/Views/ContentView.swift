import SwiftUI

struct ContentView: View {
    @StateObject private var store = SniffStore()
    @ObservedObject private var downloader = DownloadManager.shared
    @State private var selectedTab: Int = 0
    @State private var showUpgrade = false

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

            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person")
                }
                .tag(3)
        }
        .tint(AppTheme.Color.primary)
        .onAppear { applyGlobalAppearance() }
        .onReceive(NotificationCenter.default.publisher(for: .kuaiGeRequirePro)) { _ in
            showUpgrade = true
        }
        .sheet(isPresented: $showUpgrade) {
            UpgradeView()
        }
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
        navAppearance.shadowColor = .clear          // 移除底部 hairline 分割线
        navAppearance.shadowImage = UIImage()
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
    @ObservedObject private var license = LicenseManager.shared

    @State private var urlText: String = ""
    @State private var loadURL: URL? = nil
    @State private var isLoading: Bool = false
    @State private var progress: Double = 0
    @State private var playingURL: String? = nil
    @State private var pageError: String? = nil  // 页面加载错误（如 Access Denied）

    private var filtered: [SniffedMedia] {
        mode == .audio ? store.audioItems : store.videoItems
    }

    var body: some View {
        AppNav {
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

                // 专业版锁定横幅（免费版显示，激活后实时消失）
                if !license.isPro {
                    proLockBanner
                }

                // 当前加载地址（便于确认「粘贴是否生效 / WebView 是否在加载」）
                if let url = loadURL {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 10))
                        Text(url.host ?? url.absoluteString)
                            .lineLimit(1)
                    }
                    .font(AppTheme.Font.caption2())
                    .foregroundColor(AppTheme.Color.textTertiary)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.bottom, AppTheme.Spacing.xs)
                }

                // 浏览器 + 结果列表（分屏布局）
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        // 浏览器区域（占主要空间）
                        BrowserView(
                            store: store,
                            loadURL: $loadURL,
                            isLoading: $isLoading,
                            estimatedProgress: $progress,
                            pageError: $pageError
                        )
                        .frame(height: geo.size.height * (filtered.isEmpty ? 1.0 : 0.5))
                        .onDisappear {
                            // 切换 Tab / 返回时停止 WebView 中的媒体播放
                            NotificationCenter.default.post(name: .kuaiGeStopMedia, object: nil)
                        }

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
            if !isLoading && loadURL == nil && filtered.isEmpty && pageError == nil {
                emptyGuide
                    .allowsHitTesting(false)
            }

            // 覆盖层：页面加载错误提示（Access Denied 等）
            if let error = pageError, !isLoading {
                errorOverlay(message: error)
                    .allowsHitTesting(true)
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
                    .weightCompat(.semibold)
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
        // 免费版拦截：任何功能都需专业版
        guard LicenseManager.shared.isPro else {
            NotificationCenter.default.post(name: .kuaiGeRequirePro, object: nil)
            return
        }
        var trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 链接兜底：无 scheme 时自动补 https://，否则 URL(string:) 解析失败导致「没反应」
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }
        guard let u = URL(string: trimmed) else { return }
        pageError = nil  // 重置错误状态
        loadURL = u
    }

    // MARK: - 专业版锁定横幅
    private var proLockBanner: some View {
        Button {
            NotificationCenter.default.post(name: .kuaiGeRequirePro, object: nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                Text("专业版功能：粘贴链接前往前，请先到「我的」激活")
                    .font(AppTheme.Font.caption())
                    .lineLimit(1)
                Spacer()
                Text("去激活")
                    .font(AppTheme.Font.caption().weight(.semibold))
            }
            .foregroundColor(AppTheme.Color.primary)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppTheme.Color.primaryLight)
        }
    }

    // MARK: - 页面加载错误提示
    private func errorOverlay(message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer().frame(height: 60)

            // 警告图标
            ZStack {
                Circle()
                    .fill(AppTheme.Color.errorLight)
                    .frame(width: 72, height: 72)

                Image(systemName: "shield.slash")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(AppTheme.Color.error)
            }

            VStack(spacing: AppTheme.Spacing.md) {
                Text("该网站拒绝访问")
                    .font(AppTheme.Font.title2())

                Text(message)
                    .font(AppTheme.Font.body())
                    .foregroundColor(AppTheme.Color.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Label("部分平台（抖音、TikTok 等）有强反爬保护", systemImage: "info.circle")
                    Label("建议：在 Safari 浏览器打开链接，提取视频直链后粘贴到此处", systemImage: "arrow.right.circle")
                    Label("或尝试其他可直接访问的音视频网站", systemImage: "globe")
                }
                .font(AppTheme.Font.caption())
                .foregroundColor(AppTheme.Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(AppTheme.Color.surface)
                .cornerRadius(AppTheme.Radius.md)
            }

            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
    }
}
