import SwiftUI
import UIKit

/// 我的：专业版激活 + 购买联系
struct ProfileView: View {
    @ObservedObject private var license = LicenseManager.shared
    @State private var codeText: String = ""
    @State private var copiedField: String? = nil
    @State private var showSuccess: Bool = false

    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.xl) {
                        headerCard

                        if license.isPro {
                            activatedCard
                                .transition(.scale(scale: 0.92).combined(with: .opacity))
                        } else {
                            activateCard
                                .transition(.opacity)
                        }

                        contactCard

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.lg)
                }
                .background(AppTheme.Color.background.ignoresSafeArea())
                .navigationTitle("我的")
                .navigationBarTitleDisplayMode(.inline)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: license.isPro)
            }

            if showSuccess {
                SuccessBurst()
            }
        }
    }

    // MARK: - 顶部品牌卡
    private var headerCard: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(AppTheme.Color.primary)
                    .frame(width: 52, height: 52)
                Image("AppLogo")
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("MV Extractor")
                    .font(AppTheme.Font.title2())
                    .foregroundColor(AppTheme.Color.textPrimary)
                Text("AI 音乐视频提取助手")
                    .font(AppTheme.Font.caption())
                    .foregroundColor(AppTheme.Color.textSecondary)
            }

            Spacer()

            TagView(text: license.isPro ? "专业版" : "免费版",
                    style: license.isPro ? .success : .neutral)
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Color.card)
        .cornerRadius(AppTheme.Radius.lg)
        .shadow(color: AppTheme.Shadow.card, radius: 6, x: 0, y: 2)
    }

    // MARK: - 激活输入卡
    private var activateCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "key.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.Color.primary)
                Text("开通专业版")
                    .font(AppTheme.Font.title2())
                    .foregroundColor(AppTheme.Color.textPrimary)
            }

            Text("输入激活码即可免费使用全部功能")
                .font(AppTheme.Font.caption())
                .foregroundColor(AppTheme.Color.textSecondary)

            VStack(spacing: AppTheme.Spacing.sm) {
                TextField("在此粘贴激活码", text: $codeText)
                    .textFieldStyle(.plain)
                    .font(AppTheme.Font.mono(13))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .background(AppTheme.Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .stroke(AppTheme.Color.borderStrong, lineWidth: 0.5)
                    )
                    .cornerRadius(AppTheme.Radius.md)

                Button {
                    let ok = license.activate(code: codeText)
                    if ok {
                        codeText = ""
                        showSuccess = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { showSuccess = false }
                    } else {
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                } label: {
                    Text("激活")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.Color.textOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(codeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? AppTheme.Color.textTertiary
                                    : AppTheme.Color.primary)
                        .cornerRadius(AppTheme.Radius.md)
                }
                .disabled(codeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let err = license.errorMessage {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Color.error)
                    Text(err)
                        .font(AppTheme.Font.caption())
                        .foregroundColor(AppTheme.Color.error)
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Color.card)
        .cornerRadius(AppTheme.Radius.lg)
        .shadow(color: AppTheme.Shadow.card, radius: 6, x: 0, y: 2)
    }

    // MARK: - 已激活卡（黑金扫光）
    private var activatedCard: some View {
        ShimmerCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(goldGradient)
                    Text("专业版已激活")
                        .font(AppTheme.Font.title2())
                        .foregroundStyle(goldGradient)
                }

                HStack {
                    Text("状态")
                        .font(AppTheme.Font.caption())
                        .foregroundColor(goldDim)
                    Spacer()
                    Text(license.expireText)
                        .font(AppTheme.Font.caption())
                        .foregroundColor(goldBright)
                }

                Text("全部功能已解锁")
                    .font(AppTheme.Font.caption())
                    .foregroundColor(goldBright)
            }
            .padding(AppTheme.Spacing.lg)
        }
    }

    // MARK: - 购买联系卡
    private var contactCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(contactBlue)
                Text("激活码购买联系")
                    .font(AppTheme.Font.title2())
                    .foregroundColor(AppTheme.Color.textPrimary)
            }

            contactRow(icon: "number", label: "QQ", value: "2260354231")
            Divider().background(AppTheme.Color.divider)
            contactRow(icon: "message.fill", label: "微信", value: "ponboor")
            Divider().background(AppTheme.Color.divider)
            Button {
                if let url = URL(string: "https://www.goofish.com/personal?userId=2901672735") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "bag.fill")
                        .font(.system(size: 13))
                        .foregroundColor(contactBlue)
                        .frame(width: 18)
                    Text("闲鱼店铺")
                        .font(AppTheme.Font.caption())
                        .foregroundColor(AppTheme.Color.textSecondary)
                        .frame(width: 60, alignment: .leading)
                    Text("点击前往店铺")
                        .font(AppTheme.Font.bodyMedium())
                        .foregroundColor(AppTheme.Color.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.Color.textTertiary)
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Color.card)
        .cornerRadius(AppTheme.Radius.lg)
        .shadow(color: AppTheme.Shadow.card, radius: 6, x: 0, y: 2)
    }

    private func contactRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(contactBlue)
                .frame(width: 18)
            Text(label)
                .font(AppTheme.Font.caption())
                .foregroundColor(AppTheme.Color.textSecondary)
                .frame(width: 36, alignment: .leading)
            Text(value)
                .font(AppTheme.Font.bodyMedium())
                .foregroundColor(AppTheme.Color.textPrimary)
            Spacer()
            Button {
                UIPasteboard.general.string = value
                copiedField = label
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if copiedField == label { copiedField = nil }
                }
            } label: {
                Text(copiedField == label ? "已复制" : "复制")
                    .font(AppTheme.Font.caption())
                    .foregroundColor(copiedField == label ? AppTheme.Color.success : AppTheme.Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(copiedField == label ? AppTheme.Color.successLight : AppTheme.Color.primaryLight)
                    .cornerRadius(AppTheme.Radius.pill)
            }
        }
    }
}

// MARK: - 黑金扫光配色与组件
private let goldGradient = LinearGradient(
    colors: [
        Color(red: 1.0, green: 0.92, blue: 0.66),
        Color(red: 1.0, green: 0.843, blue: 0.0),
        Color(red: 0.72, green: 0.525, blue: 0.043),
        Color(red: 1.0, green: 0.843, blue: 0.0)
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
private let goldBright = Color(red: 1.0, green: 0.9, blue: 0.62)
private let goldDim = Color(red: 0.78, green: 0.7, blue: 0.45)

/// 统一深蓝色（联系方式图标，与闲鱼店铺风格一致）
private let contactBlue = Color(red: 0.0, green: 0.184, blue: 0.655) // #002FA7 克莱因蓝

/// 黑金扫光卡片：纯黑底 + 金色描边 + 细窄循环扫光（自然质感）
struct ShimmerCard<Content: View>: View {
    let content: Content
    @State private var sweep = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    .fill(Color.black)
            )
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.08),
                            Color(red: 1, green: 0.92, blue: 0.55).opacity(0.12),
                            Color.white.opacity(0.08),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.22)
                    .rotationEffect(.degrees(12))
                    .offset(x: sweep ? geo.size.width * 1.3 : -geo.size.width * 0.5)
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    .stroke(goldGradient, lineWidth: 1.5)
            )
            .onAppear {
                withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
    }
}

/// 激活成功动效：金色对勾弹簧放大 + 停留 + 缓慢淡出，让用户充分感受激活成功的满足感
struct SuccessBurst: View {
    @State private var scale: CGFloat = 0.2
    @State private var opacity: Double = 0
    @State private var glowOpacity: Double = 0

    var body: some View {
        ZStack {
            // 半透明压暗背景
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .opacity(opacity * 0.6)

            // 光晕扩散层
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1, green: 0.84, blue: 0).opacity(glowOpacity * 0.35),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 120
                    )
                )
                .frame(width: 200, height: 200)

            // 金色对勾主体
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 90, weight: .bold))
                .foregroundStyle(goldGradient)
                .shadow(color: Color(red: 1, green: 0.84, blue: 0).opacity(0.9), radius: 28, x: 0, y: 0)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .allowsHitTesting(false)
        .onAppear {
            // 阶段1：弹性放大弹出
            withAnimation(.spring(response: 0.7, dampingFraction: 0.5)) {
                scale = 1.05
                opacity = 1
                glowOpacity = 1
            }
            // 阶段2：轻微回弹到自然大小
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.55)) {
                scale = 1.0
            }
            // 阶段3：缓慢淡出（用户看清后才开始消失）
            withAnimation(.easeOut(duration: 0.8).delay(2.0)) {
                opacity = 0
                glowOpacity = 0
            }
        }
    }
}
