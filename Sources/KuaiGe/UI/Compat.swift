import SwiftUI

// MARK: - iOS 15 兼容层
// 部署目标降到 iOS 15.0 后，iOS 16+ 专属 API 统一在这里做版本分发。

/// 导航容器：iOS 16+ 用 NavigationStack，iOS 15 回退 NavigationView（stack 样式）
struct AppNav<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
                .navigationViewStyle(.stack)
        }
    }
}

extension View {
    /// .scrollContentBackground(.hidden) 的 iOS 15 兼容版本
    /// iOS 15 无此 API：List 背景通过 UITableView.appearance 全局透明处理
    @ViewBuilder
    func hideScrollContentBackground() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self.onAppear {
                UITableView.appearance().backgroundColor = .clear
            }
        }
    }

    /// View 层 .fontWeight() 是 iOS 16+；iOS 15 用 font 合成粗细
    @ViewBuilder
    func weightCompat(_ weight: Font.Weight) -> some View {
        if #available(iOS 16.0, *) {
            self.fontWeight(weight)
        } else {
            self
        }
    }

    /// .toolbarColorScheme(_:for:) 是 iOS 16+；iOS 15 下无此 API（导航栏配色由 UINavigationBarAppearance 控制），直接透传原 View。
    @ViewBuilder
    func compatibleToolbarColorScheme(_ scheme: ColorScheme, for bar: NavigationBarPlacement) -> some View {
        if #available(iOS 16.0, *) {
            self.toolbarColorScheme(scheme, for: bar)
        } else {
            self
        }
    }

    /// 条件应用修饰符（View.buildIf，iOS 13+ 可用）。用于在 iOS 15 下按条件挂载 .toolbar，
    /// 避免把 `if` 写进 .toolbar 闭包而触发 ToolbarContentBuilder.buildIf（iOS 16+）。
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}