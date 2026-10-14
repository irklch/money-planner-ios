// DesignSystemPreviews.swift
// Previews для визуальной проверки токенов дизайн-системы: цвета, палитра, типографика, иконки, отступы.
// Подписи — имена токенов для разработчика, поэтому выводятся через `Text(verbatim:)`
// и не попадают в String Catalog.

#if DEBUG // Previews нужны только в отладочной сборке.
// SwiftUI нужен для View и #Preview.
import SwiftUI

/// Список семантических цветов и палитры категорий.
private struct ColorTokensPreview: View {
    /// Пары «имя токена — цвет» для отображения.
    private let tokens: [(String, Color)] = [
        ("background", AppColor.background), // Фон экрана.
        ("surface", AppColor.surface), // Фон поверхностей.
        ("textPrimary", AppColor.textPrimary), // Основной текст.
        ("textSecondary", AppColor.textSecondary), // Вторичный текст.
        ("accent", AppColor.accent), // Акцент.
        ("separator", AppColor.separator), // Разделитель.
        ("error", AppColor.error), // Ошибка.
        ("success", AppColor.success), // Успех.
    ]

    /// Содержимое preview цветов.
    var body: some View {
        List { // Нативный список секций.
            Section { // Секция семантических цветов.
                ForEach(tokens, id: \.0) { name, color in // Строка на каждый токен; имя уникально.
                    HStack(spacing: AppSpacing.small) { // Образец цвета и имя рядом.
                        RoundedRectangle(cornerRadius: AppRadius.small) // Образец цвета.
                            .fill(color) // Заливка проверяемым цветом.
                            .stroke(AppColor.separator) // Граница, чтобы был виден светлый цвет.
                            .frame(width: AppSize.minimumTapTarget, height: AppSize.minimumTapTarget) // Квадрат 44 pt.
                        Text(verbatim: name).textStyle(.body) // Имя токена.
                    }
                }
            } header: {
                Text(verbatim: "AppColor") // Заголовок секции.
            }
            Section { // Секция палитры категорий.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: AppSize.minimumTapTarget))], spacing: AppSpacing.xSmall) { // Сетка образцов.
                    ForEach(CategoryPalette.colors.indices, id: \.self) { index in // Образец на каждый индекс палитры.
                        RoundedRectangle(cornerRadius: AppRadius.small) // Образец цвета категории.
                            .fill(CategoryPalette.color(at: index)) // Заливка цветом по индексу.
                            .frame(height: AppSize.minimumTapTarget) // Высота образца 44 pt.
                            .overlay { // Номер индекса поверх образца.
                                Text(verbatim: "\(index)").textStyle(.caption) // Индекс палитры.
                            }
                    }
                }
            } header: {
                Text(verbatim: "CategoryPalette") // Заголовок секции.
            }
        }
        .scrollContentBackground(.hidden) // Убираем системный фон списка.
        .background(AppColor.background) // Фон экрана из дизайн-системы.
    }
}

/// Все роли текста, сумма и дата в текущей локали.
private struct TypographyPreview: View {
    /// Содержимое preview типографики.
    var body: some View {
        ScrollView { // Прокрутка для крупного Dynamic Type.
            VStack(alignment: .leading, spacing: AppSpacing.medium) { // Роли текста друг под другом.
                Text(verbatim: "screenTitle").textStyle(.screenTitle) // Заголовок экрана.
                Text(verbatim: "sectionTitle").textStyle(.sectionTitle) // Заголовок секции.
                Text(verbatim: "body — основной текст, который переносится на несколько строк при крупном шрифте") // Длинный текст для проверки переноса.
                    .textStyle(.body) // Роль основного текста.
                Text(verbatim: "caption").textStyle(.caption) // Подпись.
                Text(Decimal(string: "1250.50") ?? 0, format: .currency(code: "RUB")).textStyle(.amount) // Сумма в рублях с учётом локали.
                Text(Date.now, format: .dateTime.day().month(.wide).year()).textStyle(.body) // Дата с учётом локали.
                Text(verbatim: "button").textStyle(.button) // Текст кнопки.
            }
            .frame(maxWidth: .infinity, alignment: .leading) // Выравнивание по левому краю на всю ширину.
            .padding(AppSpacing.medium) // Стандартный отступ экрана.
        }
        .background(AppColor.background) // Фон экрана из дизайн-системы.
    }
}

/// Каталог иконок и шкала отступов.
private struct MetricsAndIconsPreview: View {
    /// Размер иконки, масштабируемый вместе с текстом.
    @ScaledMetric(relativeTo: .body) private var iconSize = AppIconSize.small

    /// Содержимое preview иконок и отступов.
    var body: some View {
        List { // Нативный список секций.
            Section { // Секция иконок.
                ForEach(AppIcon.allCases, id: \.self) { icon in // Строка на каждую иконку каталога.
                    Label { // Имя и изображение иконки.
                        Text(verbatim: "\(icon)").textStyle(.body) // Имя кейса AppIcon.
                    } icon: {
                        icon.image // Изображение SF Symbol.
                            .resizable() // Разрешаем менять размер.
                            .scaledToFit() // Сохраняем пропорции.
                            .frame(width: iconSize, height: iconSize) // Масштабируемый размер иконки.
                            .foregroundStyle(AppColor.accent) // Акцентный цвет.
                    }
                }
            } header: {
                Text(verbatim: "AppIcon") // Заголовок секции.
            }
            Section { // Секция шкалы отступов.
                ForEach([ // Пары «имя — значение» шкалы.
                    ("xxSmall", AppSpacing.xxSmall), ("xSmall", AppSpacing.xSmall), ("small", AppSpacing.small), // Малые отступы.
                    ("medium", AppSpacing.medium), ("large", AppSpacing.large), ("xLarge", AppSpacing.xLarge), // Средние и крупные отступы.
                ], id: \.0) { name, value in // Строка на каждый токен.
                    HStack { // Полоса и подпись рядом.
                        Rectangle().fill(AppColor.accent).frame(width: value, height: AppSpacing.medium) // Полоса шириной в значение отступа.
                        Text(verbatim: "\(name) = \(Int(value))").textStyle(.caption) // Имя и значение токена.
                    }
                }
            } header: {
                Text(verbatim: "AppSpacing") // Заголовок секции.
            }
        }
        .scrollContentBackground(.hidden) // Убираем системный фон списка.
        .background(AppColor.background) // Фон экрана из дизайн-системы.
    }
}

/// Preview цветов.
#Preview("Цвета") { ColorTokensPreview() }
/// Preview типографики при обычном размере текста.
#Preview("Типографика") { TypographyPreview() }
/// Preview типографики при максимальном размере Dynamic Type.
#Preview("Типографика, AX5") {
    TypographyPreview().environment(\.dynamicTypeSize, .accessibility5) // Максимальный размер специальных возможностей.
}
/// Preview иконок и отступов.
#Preview("Иконки и отступы") { MetricsAndIconsPreview() }
#endif // Конец отладочного блока previews.
