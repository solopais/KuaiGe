import SwiftUI

struct ContentView: View {
    @StateObject private var store = SniffStore()
    @StateObject private var downloader = DownloadManager()

    @State private var urlText: String = ""
    @State private var loadURL: URL? = nil
    @State private var isLoading: Bool = false
    @State private var progress: Double = 0
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // ---- Tab 0: 首页 ----
            HomeView(
                store: store,
                downloader: downloader,
                onOpenSniff: { selectedTab = 1 }
            )
            .tabItem {
                Image(systemName: "house.fill")
                Text("首页")
            }
            .tag(0)

            // ---- Tab 1: 嗅探（浏览器）----
            SniffBrowserView(
                store: store,
                urlText: $urlText,
                loadURL: $loadURL,
                isLoading: $isLoading,
                progress: $progress
            )
            .tabItem {
                Image(systemName: "magnifyingglass")
                Text("嗅探")
            }
            .tag(1)

            // ---- Tab 2: 历史 ----
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

// MARK: - 嗅探浏览器页（从原 ContentView 拆出）
struct SniffBrowserView: View {
    @ObservedObject var store: SniffStore
    @Binding var urlText: String
    @Binding var loadURL: URL?
    @Binding var isLoading: Bool
    @Binding var progress: Double

    @State private var showSniffResults = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 链接栏（卡哇伊风格）
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

                // 底部嗅探提示条
                if !store.items.isEmpty {
                    sniffHintBar
                }
            }
            .navigationTitle("🔍 嗅探")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showSniffResults) {
            SniffResultView(store: store, downloader: DownloadManager.shared)
        }
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

    // MARK: 嗅探提示条
    private var sniffHintBar: some View {
        Button {
            showSniffResults = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.caption)
                Text("已嗅探到 \(store.items.count) 条音频，点击查看 →")
                    .font(.system(size: 12, weight: .medium))
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
            .shadow(color: KawaiiTheme.Shadow.button, radius: 4, y: 2)
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
        .animation(.spring(response: 0.3), value: store.items.count)
    }

    private func go() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let u = URL(string: trimmed) else { return }
        loadURL = u
    }
}
