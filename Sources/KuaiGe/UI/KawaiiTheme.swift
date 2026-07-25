import SwiftUI

// MARK: - 发行级极简设计系统（画廊风格 · 克莱因蓝 + 纯白）

enum AppTheme {

    // MARK: - 色板（注意：嵌套 enum 名为 Color，内部必须用 SwiftUI.Color 完全限定，否则会遮蔽）
    enum Color {
        // ---- 主色：国际克莱因蓝 (#002FA7) ----
        static let primary = SwiftUI.Color(red: 0, green: 0.184, blue: 0.651)
        static let primaryLight = SwiftUI.Color(red: 0, green: 0.184, blue: 0.651).opacity(0.08)
        static let primaryPressed = SwiftUI.Color(red: 0, green: 0.12, blue: 0.5)

        // ---- 中性色 ----
        static let background = SwiftUI.Color.white
        static let surface = SwiftUI.Color(red: 0.973, green: 0.976, blue: 0.98)
        static let card = SwiftUI.Color.white
        static let border = SwiftUI.Color.black.opacity(0.06)
        static let borderStrong = SwiftUI.Color.black.opacity(0.12)
        static let divider = SwiftUI.Color.black.opacity(0.05)

        // ---- 文字 ----
        static let textPrimary = SwiftUI.Color(red: 0.102, green: 0.102, blue: 0.18)
        static let textSecondary = SwiftUI.Color(red: 0.42, green: 0.447, blue: 0.502)
        static let textTertiary = SwiftUI.Color(red: 0.62, green: 0.635, blue: 0.671)
        static let textOnPrimary = SwiftUI.Color.white

        // ---- 语义色 ----
        static let success = SwiftUI.Color(red: 0.063, green: 0.725, blue: 0.506)
        static let successLight = SwiftUI.Color(red: 0.063, green: 0.725, blue: 0.506).opacity(0.1)
        static let error = SwiftUI.Color(red: 0.937, green: 0.267, blue: 0.267)
        static let errorLight = SwiftUI.Color(red: 0.937, green: 0.267, blue: 0.267).opacity(0.08)
        static let warning = SwiftUI.Color(red: 1.0, green: 0.686, blue: 0.059)

        // ---- 暗色模式 ----
        enum Dark {
            static let background = SwiftUI.Color(red: 0.086, green: 0.086, blue: 0.114)
            static let surface = SwiftUI.Color(red: 0.122, green: 0.122, blue: 0.157)
            static let card = SwiftUI.Color(red: 0.157, green: 0.157, blue: 0.204)
            static let textPrimary = SwiftUI.Color(red: 0.957, green: 0.957, blue: 0.969)
            static let textSecondary = SwiftUI.Color(red: 0.659, green: 0.659, blue: 0.702)
            static let border = SwiftUI.Color.white.opacity(0.06)
            static let primary = SwiftUI.Color(red: 0.373, green: 0.451, blue: 0.941)
        }
    }

    // MARK: - 字号
    enum Font {
        static func largeTitle() -> SwiftUI.Font { .system(size: 28, weight: .bold) }
        static func title1() -> SwiftUI.Font { .system(size: 20, weight: .bold) }
        static func title2() -> SwiftUI.Font { .system(size: 17, weight: .semibold) }
        static func body() -> SwiftUI.Font { .system(size: 15, weight: .regular) }
        static func bodyMedium() -> SwiftUI.Font { .system(size: 15, weight: .medium) }
        static func caption() -> SwiftUI.Font { .system(size: 13, weight: .medium) }
        static func caption2() -> SwiftUI.Font { .system(size: 11, weight: .regular) }
        static func mono(_ size: CGFloat = 12) -> SwiftUI.Font {
            .system(size: size, design: .monospaced)
        }
    }

    // MARK: - 间距
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    // MARK: - 圆角
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let pill: CGFloat = 999
    }

    // MARK: - 阴影
    enum Shadow {
        static let card = SwiftUI.Color.black.opacity(0.04)
        static let elevated = SwiftUI.Color.black.opacity(0.08)
        static let modal = SwiftUI.Color.black.opacity(0.25)
    }
}

// MARK: - 兼容旧引用（逐步迁移中）
typealias KawaiiTheme = AppTheme

// MARK: - 发行级卡片容器
struct AppCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = AppTheme.Spacing.lg

    init(padding: CGFloat = AppTheme.Spacing.lg, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .background(AppTheme.Color.card)
            .cornerRadius(AppTheme.Radius.lg)
            .shadow(color: AppTheme.Shadow.card, radius: 6, x: 0, y: 2)
    }
}

// MARK: - 兼容旧名
typealias KawaiiCard = AppCard

// MARK: - 发行级主按钮
struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: { action() }) {
            HStack(spacing: AppTheme.Spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(AppTheme.Color.textOnPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isPressed ? AppTheme.Color.primaryPressed : AppTheme.Color.primary)
            .cornerRadius(AppTheme.Radius.md)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isPressed)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - 发行级次按钮（描边样式）
struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: { action() }) {
            HStack(spacing: AppTheme.Spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(AppTheme.Color.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.Color.primaryLight)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(AppTheme.Color.primary.opacity(0.2), lineWidth: 0.5)
            )
            .cornerRadius(AppTheme.Radius.md)
        }
    }
}

// MARK: - 标签组件
struct TagView: View {
    let text: String
    var style: TagStyle = .neutral

    enum TagStyle {
        case primary, success, error, neutral
    }

    var body: some View {
        Text(text)
            .font(AppTheme.Font.caption())
            .foregroundColor(tagForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tagBackground)
            .cornerRadius(AppTheme.Radius.pill)
    }

    private var tagForeground: Color {
        switch style {
        case .primary: return AppTheme.Color.primary
        case .success: return AppTheme.Color.success
        case .error:   return AppTheme.Color.error
        case .neutral: return AppTheme.Color.textSecondary
        }
    }

    private var tagBackground: Color {
        switch style {
        case .primary: return AppTheme.Color.primaryLight
        case .success: return AppTheme.Color.successLight
        case .error:   return AppTheme.Color.errorLight
        case .neutral: return AppTheme.Color.surface
        }
    }
}
