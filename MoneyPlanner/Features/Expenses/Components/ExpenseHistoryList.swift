// ExpenseHistoryList.swift
// История расходов за период по дням (Figma E4 `304:11771`): заголовок дня и группа строк.

// SwiftUI нужен для View и ForEach.
import SwiftUI

/// Дни истории. Встраивается в `LazyVStack` экрана: дни создаются по мере прокрутки.
struct ExpenseHistoryDays: View {
    /// Дни истории, новые выше.
    let days: [HistoryDay]
    /// «Сегодня» — чтобы не писать текущий год в датах.
    let today: CalendarDate
    /// Показывать категорию у расходов (история всех категорий).
    let showsCategory: Bool
    /// Открыть категорию расхода; `nil` — строки без перехода.
    let openCategory: ((CategoryReference) -> Void)?

    /// Дни истории.
    var body: some View {
        ForEach(days) { day in // День за днём.
            VStack(alignment: .leading, spacing: AppSpacing.small) { // Заголовок дня и группа.
                Text(.historyDayHeader( // «25 сентября, чт».
                    ExpenseFormatting.dayAndMonth(day.date, today: today), // День и месяц.
                    ExpenseFormatting.weekday(day.date) // День недели.
                ))
                .textStyle(.captionEmphasized) // 13 Semibold, вторичный цвет.
                .accessibilityAddTraits(.isHeader) // Заголовок для навигации VoiceOver.
                VStack(spacing: 0) { // Группа строк дня.
                    ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in // Расходы дня.
                        if index > 0 { // Разделитель между строками.
                            Rectangle().fill(AppColor.separator).frame(height: AppSize.hairline) // Линия 0.5 pt.
                        }
                        ExpenseHistoryRow(entry: entry, showsCategory: showsCategory, open: openCategory) // Строка расхода.
                    }
                }
                .padding(.horizontal, AppSpacing.medium) // Поля 16 pt внутри группы.
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)) // Карточка 16 pt.
            }
            .padding(.horizontal, AppSpacing.medium) // Поля экрана 16 pt.
            .padding(.bottom, AppSpacing.medium) // Отступ до следующего дня.
        }
    }
}

/// Строка расхода: эмодзи категории, заголовок, сумма.
///
/// Заголовок — комментарий или, если его нет, название категории (Figma K1: «заголовок =
/// комментарий или категория»). В истории всех категорий под комментарием показывается категория;
/// без комментария второй строки нет и пустого места не остаётся.
struct ExpenseHistoryRow: View {
    /// Расход с категорией.
    let entry: HistoryEntry
    /// Показывать название категории под комментарием.
    let showsCategory: Bool
    /// Открыть категорию; `nil` — строка без перехода.
    let open: ((CategoryReference) -> Void)?

    /// Размер шрифта среды для раскладки.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Содержимое строки.
    var body: some View {
        if let open { // Строка с переходом.
            Button { open(entry.category) } label: { content(disclosure: true) } // Переход к категории.
                .buttonStyle(.plain) // Без подсветки текста.
                .accessibilityHint(Text(.historyRowHint)) // «Открывает расходы категории за период».
        } else {
            content(disclosure: false) // Только просмотр.
        }
    }

    /// Раскладка строки.
    private func content(disclosure: Bool) -> some View {
        HStack(spacing: AppSpacing.small) { // Бейдж, текст, переход.
            CategoryBadge(category: entry.category, style: .filled) // Эмодзи категории.
            AdaptiveRowLayout(dynamicTypeSize: dynamicTypeSize).layout { // Текст и сумма.
                VStack(alignment: .leading, spacing: AppSpacing.tiny) { // Заголовок и категория.
                    if let comment = entry.expense.comment { // Есть комментарий.
                        Text(verbatim: comment).textStyle(.body) // Комментарий не локализуется.
                        if showsCategory { entry.category.title.textStyle(.caption) } // Категория под комментарием.
                    } else {
                        entry.category.title.textStyle(.body) // Без комментария — название категории.
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading) // Текст занимает остаток и переносится.
                Text(verbatim: ExpenseFormatting.money(entry.expense.amount)) // «3 200 ₽».
                    .textStyle(.amount) // 17 Medium, цифры одинаковой ширины.
                    .fixedSize() // Сумма не переносится.
            }
            if disclosure { DisclosureChevron() } // Шеврон перехода.
        }
        .padding(.vertical, AppSpacing.small) // 12 pt сверху и снизу.
        .frame(minHeight: AppSize.minimumTapTarget) // Область нажатия не меньше 44 pt.
        .contentShape(Rectangle()) // Нажатие по всей строке.
        .accessibilityElement(children: .combine) // Строка — один элемент VoiceOver.
        .accessibilityIdentifier("history.row") // Идентификатор для UI-тестов.
    }
}

/// Пустой период (Figma H9 `295:6633`): иконка, заголовок, пояснение, «Выбрать период».
///
/// Кнопка «Добавить расходы» из макета не показывается: ввод расходов — следующий этап.
struct EmptyPeriodView: View {
    /// Пустой период.
    let period: ExpensePeriod
    /// Самая ранняя дата расхода; `nil`, если расходов нет совсем.
    let earliestExpenseDate: CalendarDate?
    /// «Сегодня» для формата дат.
    let today: CalendarDate
    /// Открыть выбор периода.
    let choosePeriod: () -> Void

    /// Сторона подложки, масштабируемая вместе с текстом.
    @ScaledMetric(relativeTo: .title2) private var badge = AppSize.emptyStateBadge
    /// Размер символа, масштабируемый вместе с текстом.
    @ScaledMetric(relativeTo: .title2) private var glyph = AppIconSize.emptyState

    /// Содержимое пустого состояния.
    var body: some View {
        VStack(spacing: AppSpacing.small) { // Элементы по центру.
            AppIcon.calendar.image // Календарь.
                .font(.system(size: glyph * 0.8)) // Символ 24 pt.
                .foregroundStyle(AppColor.textSecondary) // Вторичный цвет.
                .frame(width: badge, height: badge) // Подложка 64 pt.
                .background(AppColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)) // Мягкая подложка.
                .accessibilityHidden(true) // Декоративная иконка.
            Text(period.phrase(month: LocalizedStringResource.emptyTitleMonth, days: LocalizedStringResource.emptyTitleDays)) // «Нет расходов за август».
                .textStyle(.stateTitle) // 22 Bold.
                .multilineTextAlignment(.center) // По центру.
                .padding(.top, AppSpacing.xSmall) // Отступ от иконки.
            if let message { // Пояснение есть, только если расходы есть в других периодах.
                Text(message) // Пояснение.
                    .textStyle(.subheadline) // 15, вторичный цвет.
                    .multilineTextAlignment(.center) // По центру.
                Button(action: choosePeriod) { // Открывает выбор периода.
                    Text(.emptyChoosePeriod).textStyle(.button) // «Выбрать период».
                        .frame(minHeight: AppSize.minimumTapTarget) // Область нажатия 44 pt.
                }
                .buttonStyle(.borderless) // Текстовая кнопка внутри контента.
                .padding(.top, AppSpacing.small) // Отступ от пояснения.
                .accessibilityIdentifier("empty.choosePeriod") // Идентификатор для UI-тестов.
            }
        }
        .padding(.horizontal, AppSpacing.xLarge) // Поля 32 pt.
        .frame(maxWidth: .infinity) // По центру по горизонтали.
        .accessibilityElement(children: .contain) // Контейнер: элементы внутри остаются доступными.
        .accessibilityIdentifier("empty.state") // Идентификатор для UI-тестов.
    }

    /// Пояснение: расходы начинаются позже периода — с какой даты; есть в других периодах — выбрать другой.
    private var message: LocalizedStringResource? {
        guard let earliestExpenseDate else { return nil } // Расходов нет совсем: подсказывать нечего.
        if earliestExpenseDate > period.elapsed.upperBound { // Все расходы позже периода.
            return .emptySince(ExpenseFormatting.dayAndMonth(earliestExpenseDate, today: today)) // «Расходы есть с 1 сентября…».
        }
        return .emptyOtherPeriod // «Выберите другой период.»
    }
}
