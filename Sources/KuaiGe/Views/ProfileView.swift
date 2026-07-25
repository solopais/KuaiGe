import SwiftUI
import UIKit

/// 我的：专业版激活 + 购买联系
struct ProfileView: View {
    @ObservedObject private var license = LicenseManager.shared
    @State private var codeText: String = ""
    @State private var copiedField: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    headerCard

                    if license.isPro {
                        activatedCard
                    } else {
                        activateCard
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
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
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

    // MARK: - 已激活卡
    private var activatedCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.Color.success)
                Text("专业版已激活")
                    .font(AppTheme.Font.title2())
                    .foregroundColor(AppTheme.Color.textPrimary)
            }

            HStack {
                Text("状态")
                    .font(AppTheme.Font.caption())
                    .foregroundColor(AppTheme.Color.textSecondary)
                Spacer()
                Text(license.expireText)
                    .font(AppTheme.Font.caption())
                    .foregroundColor(AppTheme.Color.textPrimary)
            }

            HStack {
                Text("全部功能已解锁")
                    .font(AppTheme.Font.caption())
                    .foregroundColor(AppTheme.Color.success)
                Spacer()
                Button {
                    withAnimation { license.deactivate() }
                } label: {
                    Text("注销")
                        .font(AppTheme.Font.caption())
                        .foregroundColor(AppTheme.Color.error)
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Color.card)
        .cornerRadius(AppTheme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .stroke(AppTheme.Color.success.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - 购买联系卡
    private var contactCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.Color.primary)
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
                        .foregroundColor(AppTheme.Color.primary)
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
                .foregroundColor(AppTheme.Color.textTertiary)
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
