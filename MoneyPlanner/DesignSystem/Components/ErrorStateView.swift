// ErrorStateView.swift
// Общий компонент состояния ошибки с кнопкой «Повторить».

// SwiftUI нужен для View и системных компонентов.
import SwiftUI

/// Состояние ошибки с действием «Повторить».
///
/// Основа — системный `ContentUnavailableView`, кнопка — нативный стиль Liquid Glass.
/// Тексты передаются локализованными ресурсами из String Catalog.
struct ErrorStateView: View {
    /// Иконка, поясняющая тип ошибки.
    let icon: AppIcon
    /// Заголовок ошибки из String Catalog.
    let title: LocalizedStringResource
    /// Пояснение и подсказка, что делать, из String Catalog.
    let message: LocalizedStringResource
    /// Действие по нажатию «Повторить».
    let retry: () -> Void

    /// Содержимое состояния ошибки.
    var body: some View {
        ContentUnavailableView { // Системный контейнер для пустых и ошибочных состояний.
            Label { // Заголовок с иконкой.
                Text(title).textStyle(.sectionTitle) // Заголовок ошибки в роли заголовка секции.
            } icon: {
                icon.image // Иконка типа ошибки.
                    .foregroundStyle(AppColor.error) // Окрашиваем иконку цветом ошибки.
                    .accessibilityHidden(true) // Иконка декоративная: VoiceOver читает только текст.
            }
        } description: {
            Text(message).textStyle(.body) // Пояснение основным текстом.
        } actions: {
            Button(action: retry) { // Кнопка повторной попытки.
                Label { // Текст и иконка кнопки.
                    Text(.actionRetry) // Локализованный текст «Повторить».
                } icon: {
                    AppIcon.retry.image // Иконка повтора.
                }
                .font(AppTextStyle.button.font) // Шрифт роли «кнопка».
                .frame(minHeight: AppSize.minimumTapTarget) // Минимальная область касания 44 pt.
            }
            .buttonStyle(.glassProminent) // Нативный акцентный стиль Liquid Glass.
            .accessibilityIdentifier("errorState.retry") // Идентификатор кнопки для UI-тестов.
        }
        .accessibilityIdentifier("errorState") // Идентификатор компонента для UI-тестов.
    }
}

/// Preview: ошибка соединения при обычном размере текста.
#Preview("Ошибка") {
    ErrorStateView( // Компонент с текстами ошибки соединения.
        icon: .noConnection, // Иконка отсутствия сети.
        title: .errorNoConnectionTitle, // «Нет соединения».
        message: .errorNoConnectionMessage, // Подсказка проверить подключение.
        retry: {} // В preview действие не нужно.
    )
    .background(AppColor.background) // Фон экрана из дизайн-системы.
}

/// Preview: ошибка открытия БД при крупном размере текста.
#Preview("Ошибка, крупный текст") {
    ErrorStateView( // Компонент с текстами ошибки хранилища.
        icon: .error, // Общая иконка ошибки.
        title: .errorStorageTitle, // «Не удалось открыть данные».
        message: .errorStorageMessage, // Пояснение про сохранность данных.
        retry: {} // В preview действие не нужно.
    )
    .background(AppColor.background) // Фон экрана из дизайн-системы.
    .environment(\.dynamicTypeSize, .accessibility3) // Проверка крупного Dynamic Type.
}
