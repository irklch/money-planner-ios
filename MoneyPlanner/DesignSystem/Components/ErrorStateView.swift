import SwiftUI

/// Состояние ошибки с действием «Повторить».
///
/// Основа — системный `ContentUnavailableView`, кнопка — нативный стиль Liquid Glass.
/// Тексты передаются локализованными ресурсами из String Catalog.
struct ErrorStateView: View {
    let icon: AppIcon
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title).textStyle(.sectionTitle)
            } icon: {
                icon.image
                    .foregroundStyle(AppColor.error)
                    .accessibilityHidden(true)
            }
        } description: {
            Text(message).textStyle(.body)
        } actions: {
            Button(action: retry) {
                Label {
                    Text(.actionRetry)
                } icon: {
                    AppIcon.retry.image
                }
                .font(AppTextStyle.button.font)
                .frame(minHeight: AppSize.minimumTapTarget)
            }
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("errorState.retry")
        }
        .accessibilityIdentifier("errorState")
    }
}

#Preview("Ошибка") {
    ErrorStateView(
        icon: .noConnection,
        title: .errorNoConnectionTitle,
        message: .errorNoConnectionMessage,
        retry: {}
    )
    .background(AppColor.background)
}

#Preview("Ошибка, крупный текст") {
    ErrorStateView(
        icon: .error,
        title: .errorStorageTitle,
        message: .errorStorageMessage,
        retry: {}
    )
    .background(AppColor.background)
    .environment(\.dynamicTypeSize, .accessibility3)
}
