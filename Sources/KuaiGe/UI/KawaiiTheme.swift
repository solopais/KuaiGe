import SwiftUI

// MARK: - 卡哇伊动漫风设计系统

enum KawaiiTheme {

    // MARK: 配色
    enum Color {
        /// 樱花粉 — 主色（按钮、Tab 选中、强调）
        static let sakuraPink = SwiftUI.Color(red: 1.0, green: 0.718, blue: 0.773)
        /// 薰衣草紫 — 次要色
        static let lavender = SwiftUI.Color(red: 0.902, green: 0.902, blue: 0.98)
        /// 薄荷绿 — 成功/下载完成
        static let mint = SwiftUI.Color(red: 0.71, green: 0.918, blue: 0.843)
        /// 奶油底色
        static let cream = SwiftUI.Color(red: 1.0, green: 0.973, blue: 0.906)
        /// 文字深棕
        static let textDark = SwiftUI.Color(red: 0.282, green: 0.216, blue: 0.157)
        /// 文字浅灰
        static let textLight = SwiftUI.Color(red: 0.55, green: 0.5, blue: 0.45)
        /// 珊瑚橙 — CTA 按钮
        static let coral = SwiftUI.Color(red: 1.0, green: 0.435, blue: 0.38)
        /// 天空蓝 — 链接/信息
        static let skyBlue = SwiftUI.Color(red: 0.529, green: 0.808, blue: 0.922)
        /// 卡片白
        static let cardWhite = SwiftUI.Color.white
        /// 分割线
        static let divider = SwiftUI.Color.black.opacity(0.06)

        // 暗色模式对应
        enum Dark {
            static let background = SwiftUI.Color(red: 0.14, green: 0.12, blue: 0.18)
            static let card = SwiftUI.Color(red: 0.2, green: 0.18, blue: 0.26)
            static let text = SwiftUI.Color(red: 0.92, green: 0.9, blue: 0.88)
            static let textSecondary = SwiftUI.Color(red: 0.65, green: 0.62, blue: 0.68)
            static let sakuraPink = SwiftUI.Color(red: 0.9, green: 0.5, blue: 0.6)
            static let mint = SwiftUI.Color(red: 0.4, green: 0.75, blue: 0.6)
        }
    }

    // MARK: 圆��
    enum Radius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 18
        static let large: CGFloat = 24
        static let pill: CGFloat = 999
    }

    // MARK: 阴影
    struct Shadow {
        static let card = SwiftUI.Color.black.opacity(0.06)
        static let button = KawaiiTheme.Color.sakuraPink.opacity(0.3)
        static let floating = SwiftUI.Color.black.opacity(0.12)
    }
}

// MARK: - 卡哇伊按钮样式
struct KawaiiButtonStyle: ButtonStyle {
    var isPrimary: Bool = true
    @Environment(\.isEnabled) var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(isPrimary ? .white : KawaiiTheme.Color.sakuraPink)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(
                Group {
                    if isPrimary {
                        KawaiiTheme.Color.sakuraPink
                    } else {
                        KawaiiTheme.Color.sakuraPink.opacity(0.12)
                    }
                }
            )
            .cornerRadius(KawaiiTheme.Radius.pill)
            .shadow(color: KawaiiTheme.Shadow.button, radius: 6, y: 3)
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - 卡哇伊卡片容器
struct KawaiiCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 16

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .background(KawaiiTheme.Color.cardWhite)
            .cornerRadius(KawaiiTheme.Radius.medium)
            .shadow(color: KawaiiTheme.Shadow.card, radius: 8, y: 4)
    }
}

// MARK: - 可爱标签
struct KawaiiTag: View {
    let text: String
    var color: Color = KawaiiTheme.Color.lavender

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(KawaiiTheme.Color.textDark.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(KawaiiTheme.Radius.pill)
    }
}
