import SwiftUI
import UIKit

// MARK: - 升级 / 激活 相关通知
extension Notification.Name {
    /// 任意功能被专业版拦截时，请求弹出「升级专业版」页
    static let kuaiGeRequirePro = Notification.Name("kuaiGeRequirePro")
    /// 从升级页请求跳转到「我的」Tab 去激活
    static let kuaiGeGoProfile = Notification.Name("kuaiGeGoProfile")
}

/// 升级专业版提示页（免费版拦截任何功能时弹出）
struct UpgradeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    lockHero
                        .padding(.top, AppTheme.Spacing.lg)

                    titleBlock

                    featuresCard

                    activateButton

                    contactCard

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
            }
            .background(AppTheme.Color.background.ignoresSafeArea())
            .navigationTitle("升级专业版")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(AppTheme.Color.primary)
                }
            }
        }
    }

    private var lockHero: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Color.primaryLight)
                .frame(width: 84, height: 84)
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(AppTheme.Color.primary)
        }
    }

    private var titleBlock: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Text("该功能需专业版")
                .font(AppTheme.Font.title1())
                .foregroundColor(AppTheme.Color.textPrimary)
            Text("输入激活码即可永久免费使用\n全部音频 / 视频提取功能")
                .font(AppTheme.Font.body())
                .foregroundColor(AppTheme.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            featureRow("音频 / 视频链接提取")
            featureRow("媒体直链自动嗅探")
            featureRow("历史记录无限保存")
            featureRow("全部直链一键导出")
        }
        .font(AppTheme.Font.body())
        .foregroundColor(AppTheme.Color.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Color.card)
        .cornerRadius(AppTheme.Radius.lg)
        .shadow(color: AppTheme.Shadow.card, radius: 6, x: 0, y: 2)
    }

    private func featureRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .foregroundColor(AppTheme.Color.primary)
    }

    private var activateButton: some View {
        Button {
            dismiss()
            NotificationCenter.default.post(name: .kuaiGeGoProfile, object: nil)
        } label: {
            Text("我已购买，去激活")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.Color.textOnPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AppTheme.Color.primary)
                .cornerRadius(AppTheme.Radius.md)
        }
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("未购买？联系获取激活码")
                .font(AppTheme.Font.caption())
                .foregroundColor(AppTheme.Color.textSecondary)

            HStack(spacing: AppTheme.Spacing.lg) {
                contactChip(icon: "number", label: "QQ", value: "2260354231")
                contactChip(icon: "message.fill", label: "微信", value: "ponboor")
            }

            Divider().background(AppTheme.Color.divider)
            Button {
                if let url = URL(string: "https://www.goofish.com/personal?userId=2901672735") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "bag.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.0, green: 0.184, blue: 0.655))
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Color.surface)
        .cornerRadius(AppTheme.Radius.lg)
    }

    private func contactChip(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(Color(red: 0.0, green: 0.184, blue: 0.655))
            Text(label)
                .font(AppTheme.Font.caption())
                .foregroundColor(AppTheme.Color.textSecondary)
            Text(value)
                .font(AppTheme.Font.bodyMedium())
                .foregroundColor(AppTheme.Color.textPrimary)
        }
    }
}
