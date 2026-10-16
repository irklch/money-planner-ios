// PeriodViews.swift
// Подписи периода, капсула выбора периода и sheet «Период» (Figma D3 `295:6198`).

// SwiftUI нужен для View, sheet и кнопок.
import SwiftUI

/// Подписи периода в интерфейсе.
extension ExpensePeriod {
    /// Подпись капсулы: «Сентябрь», «Прошлый месяц», «30 дней» (Figma D1, H9, 02.05).
    var menuTitle: String {
        switch preset { // Подпись по варианту.
        case .currentMonth: ExpenseFormatting.monthTitle(interval.lowerBound) // Название текущего месяца.
        case .previousMonth: String(localized: .periodPresetPreviousMonth) // «Прошлый месяц».
        case .last30Days, .last90Days: String(localized: .periodPresetDays(preset.rollingDayCount!)) // «30 дней».
        }
    }

    /// Название варианта в списке выбора: «Текущий месяц», «30 дней».
    var optionTitle: String {
        switch preset { // Название варианта.
        case .currentMonth: String(localized: .periodPresetCurrentMonth) // «Текущий месяц».
        case .previousMonth: String(localized: .periodPresetPreviousMonth) // «Прошлый месяц».
        case .last30Days, .last90Days: String(localized: .periodPresetDays(preset.rollingDayCount!)) // «30 дней».
        }
    }

    /// Пояснение варианта: месяц или сокращённый диапазон дат («Август», «3 июл. – 30 сент.»).
    func optionDetail(today: CalendarDate) -> String {
        isMonth
            ? ExpenseFormatting.monthTitle(interval.lowerBound) // Название месяца.
            : ExpenseFormatting.range(interval, abbreviated: true, today: today) // Даты окна.
    }

    /// Период в тексте «за …»: «сентябрь» или «30 дней» — для заголовков и пояснений.
    func phrase(month: (String) -> LocalizedStringResource, days: (Int) -> LocalizedStringResource) -> LocalizedStringResource {
        isMonth ? month(ExpenseFormatting.monthName(interval.lowerBound)) : days(preset.rollingDayCount!) // Ключ по виду периода.
    }
}

/// Капсула выбора периода под заголовком экрана: «Сентябрь ⌃⌄».
///
/// Контентная капсула — сплошная (`surface/primary`); стекло — только у компактной кнопки в toolbar.
struct PeriodMenuButton: View {
    /// Выбранный период.
    let period: ExpensePeriod
    /// Открыть выбор периода.
    let action: () -> Void

    /// Размер символа, масштабируемый вместе с текстом.
    @ScaledMetric(relativeTo: .subheadline) private var chevron = AppIconSize.chevron
    /// Высота капсулы, масштабируемая вместе с текстом.
    @ScaledMetric(relativeTo: .subheadline) private var height = AppSize.periodMenu

    /// Содержимое капсулы.
    var body: some View {
        Button(action: action) { // Открывает sheet.
            HStack(spacing: AppSpacing.xxSmall) { // Подпись и символ.
                Text(verbatim: period.menuTitle).textStyle(.subheadlineEmphasized) // «Сентябрь».
                AppIcon.selector.image // chevron.up.chevron.down.
                    .font(.system(size: chevron * 0.85, weight: .semibold)) // Компактный символ.
                    .foregroundStyle(AppColor.textPrimary) // Основной цвет.
            }
            .padding(.leading, AppSpacing.cozy) // 14 pt слева.
            .padding(.trailing, AppSpacing.snug) // 10 pt справа.
            .frame(minHeight: max(height, AppSize.minimumTapTarget - AppSpacing.xSmall)) // 36 pt.
            .background(AppColor.surface, in: Capsule()) // Сплошная капсула.
            .contentShape(Capsule()) // Область нажатия — вся капсула.
        }
        .buttonStyle(.plain) // Без системной подсветки текста.
        .frame(minHeight: AppSize.minimumTapTarget) // Область нажатия не меньше 44 pt.
        .accessibilityLabel(Text(.periodMenuAccessibility(period.menuTitle))) // «Период: Сентябрь».
        .accessibilityHint(Text(.periodMenuHint)) // «Открывает выбор периода».
        .accessibilityIdentifier("period.menu") // Идентификатор для UI-тестов.
    }
}

/// Компактная кнопка периода в toolbar, когда капсула ушла за верх экрана (Figma D1s `295:6110`).
struct PeriodToolbarButton: View {
    /// Выбранный период.
    let period: ExpensePeriod
    /// Открыть выбор периода.
    let action: () -> Void

    /// Содержимое кнопки; стекло рисует система.
    var body: some View {
        Button(action: action) { // Тот же sheet.
            HStack(spacing: AppSpacing.xxSmall) { // Подпись и символ.
                Text(verbatim: period.menuTitle).textStyle(.subheadlineEmphasized) // «Сентябрь».
                AppIcon.selector.image.imageScale(.small) // chevron.up.chevron.down.
            }
        }
        .accessibilityLabel(Text(.periodMenuAccessibility(period.menuTitle))) // «Период: Сентябрь».
        .accessibilityHint(Text(.periodMenuHint)) // «Открывает выбор периода».
        .accessibilityIdentifier("period.toolbarMenu") // Идентификатор для UI-тестов.
    }
}

/// Sheet «Период»: четыре варианта, выбор применяется сразу и закрывает sheet.
struct PeriodPickerSheet: View {
    /// Выбранный вариант.
    let selected: PeriodPreset
    /// «Сегодня» для границ вариантов.
    let today: CalendarDate
    /// Применить вариант.
    let select: (PeriodPreset) -> Void

    /// Закрытие sheet.
    @Environment(\.dismiss) private var dismiss

    /// Размер галочки, масштабируемый вместе с текстом.
    @ScaledMetric(relativeTo: .body) private var checkmark = AppIconSize.small
    /// Высота содержимого: sheet подгоняется под неё, как в макете.
    @State private var contentHeight: CGFloat = AppSize.optionRow * 8

    /// Содержимое sheet.
    var body: some View {
        ScrollView { // Прокрутка при крупном Dynamic Type.
            VStack(spacing: 0) { // Заголовок, варианты, пояснение.
                Text(.periodTitle) // «Период».
                    .textStyle(.headline) // 17 Semibold.
                    .padding(.vertical, AppSpacing.cozy) // 14 pt сверху и снизу.
                    .accessibilityAddTraits(.isHeader) // Заголовок для VoiceOver.
                VStack(spacing: 0) { // Список inset grouped.
                    ForEach(Array(PeriodPreset.allCases.enumerated()), id: \.element) { index, preset in // Варианты по порядку макета.
                        if index > 0 { // Разделитель между вариантами.
                            Rectangle().fill(AppColor.separator).frame(height: AppSize.hairline).padding(.leading, AppSpacing.medium) // Линия 0.5 pt.
                        }
                        option(preset) // Строка варианта.
                    }
                }
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)) // Карточка 24 pt.
                .padding(.horizontal, AppSpacing.medium) // Поля 16 pt.
                Text(.periodFooter) // «Под суммой — точные даты.»
                    .textStyle(.caption) // 13, вторичный цвет.
                    .frame(maxWidth: .infinity, alignment: .leading) // По левому краю.
                    .padding(.horizontal, AppSpacing.xLarge) // Поля 32 pt.
                    .padding(.top, AppSpacing.xSmall) // 8 pt над пояснением.
            }
            .padding(.bottom, AppSpacing.section) // Нижний отступ.
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 } // Высота содержимого.
        }
        .scrollBounceBehavior(.basedOnSize) // Без «резинки», если всё помещается.
        .presentationDetents([.height(contentHeight + AppSpacing.medium), .large]) // По содержимому; large — для крупного текста.
        .presentationDragIndicator(.visible) // Системный grabber.
        .presentationBackground(AppColor.background) // Непрозрачный фон содержимого.
        .accessibilityIdentifier("period.sheet") // Идентификатор для UI-тестов.
    }

    /// Строка варианта: название, пояснение и галочка выбранного.
    private func option(_ preset: PeriodPreset) -> some View {
        // Период варианта на сегодня.
        let period = ExpensePeriod(preset: preset, today: today)
        // Вариант выбран.
        let isSelected = preset == selected
        return Button { // Выбор варианта.
            select(preset) // Применяем период.
            dismiss() // Закрываем sheet.
        } label: {
            HStack(spacing: AppSpacing.xSmall) { // Название, пояснение, галочка.
                Text(verbatim: period.optionTitle).textStyle(.body) // «Текущий месяц».
                    .frame(maxWidth: .infinity, alignment: .leading) // Название занимает остаток.
                Text(verbatim: period.optionDetail(today: today)) // «Сентябрь», «1–30 сент.».
                    .font(AppTextStyle.body.font) // 17 Regular.
                    .foregroundStyle(AppColor.textSecondary) // Вторичный цвет.
                    .multilineTextAlignment(.trailing) // Перенос — по правому краю.
                AppIcon.checkmark.image // Галочка.
                    .font(.system(size: checkmark * 0.8, weight: .semibold)) // 16 pt.
                    .foregroundStyle(AppColor.accent) // Акцентный цвет.
                    .opacity(isSelected ? 1 : 0) // Место под галочку сохраняется.
                    .accessibilityHidden(true) // Выбор объявляет признак isSelected.
            }
            .padding(.horizontal, AppSpacing.medium) // Поля 16 pt.
            .padding(.vertical, AppSpacing.small) // Вертикальные поля для переноса.
            .frame(minHeight: AppSize.optionRow) // Высота строки 50 pt.
            .contentShape(Rectangle()) // Нажатие по всей строке.
        }
        .buttonStyle(.plain) // Без системной подсветки текста.
        .accessibilityAddTraits(isSelected ? .isSelected : []) // Выбранный вариант для VoiceOver.
        .accessibilityIdentifier("period.option.\(preset.rawValue)") // Идентификатор для UI-тестов.
    }
}
