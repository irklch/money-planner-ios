// CategoryExpensesView.swift
// Экран категории: итог и вся история категории за выбранный период (Figma E4 `304:11771`).

// SwiftUI нужен для View, ScrollView и toolbar.
import SwiftUI

/// Расходы одной категории за тот же общий период.
///
/// Использует ту же ViewModel, сводку и компоненты истории, что и главный экран: отличается
/// только фильтр по категории. Архивная и неизвестная категории открываются так же.
struct CategoryExpensesView: View {
    /// Категория, по которой открыт экран (показывается до загрузки).
    let category: CategoryReference
    /// Общий выбранный период.
    let selection: PeriodSelection

    /// ViewModel экрана; живёт, пока экран в стеке навигации.
    @State private var model: ExpenseOverviewModel
    /// Показан ли sheet выбора периода.
    @State private var isPickingPeriod = false
    /// Заголовок категории ушёл за верх экрана: название показывается в toolbar.
    @State private var isHeaderHidden = false

    /// Создаёт экран с ViewModel по категории.
    init(category: CategoryReference, selection: PeriodSelection, repository: any ExpenseOverviewProviding, changes: any LedgerChangeObserving) {
        self.category = category // Категория.
        self.selection = selection // Общий период.
        _model = State(initialValue: ExpenseOverviewModel( // Та же ViewModel с фильтром.
            categoryID: category.id, selection: selection, repository: repository, changes: changes // Категория и зависимости.
        ))
    }

    /// Содержимое экрана.
    var body: some View {
        ScrollView { // Прокрутка всего экрана.
            LazyVStack(alignment: .leading, spacing: 0) { // История создаётся лениво.
                header // Эмодзи, название, период.
                content // Содержимое по состоянию.
            }
            .padding(.bottom, AppSpacing.xxLarge) // Отступ после истории.
        }
        .background(AppColor.background.ignoresSafeArea()) // Тёплый фон.
        .navigationTitle(isHeaderHidden ? displayedCategory.titleString : "") // Название в toolbar, когда заголовок скрыт.
        .navigationBarTitleDisplayMode(.inline) // Крупный заголовок — в содержимом.
        .overviewLifecycle(model: model, selection: selection, isPickingPeriod: $isPickingPeriod) // Загрузка, обновления, sheet.
        .accessibilityIdentifier("category") // Идентификатор для UI-тестов.
    }

    /// Категория из сводки (актуальное название после правки) или переданная при переходе.
    private var displayedCategory: CategoryReference {
        model.overview?.scope ?? category // Сводка знает текущее состояние категории.
    }

    /// Заголовок: эмодзи в карточке, название, капсула периода.
    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.snug) { // Название и период.
            HStack(spacing: AppSpacing.small) { // Эмодзи и название.
                CategoryHeaderEmoji(category: displayedCategory) // Эмодзи 28 pt.
                displayedCategory.title // Название категории.
                    .textStyle(.title) // 28 Bold.
                    .accessibilityAddTraits(.isHeader) // Заголовок экрана.
                    .accessibilityIdentifier("category.title") // Идентификатор для UI-тестов.
            }
            .onScrollVisibilityChange(threshold: 0.01) { isHeaderHidden = !$0 } // Название в toolbar при прокрутке.
            PeriodMenuButton(period: model.period) { isPickingPeriod = true } // «Сентябрь ⌃⌄».
        }
        .padding(.horizontal, AppSpacing.mediumLarge) // Поля 20 pt.
        .padding(.top, AppSpacing.tiny) // 2 pt сверху.
        .padding(.bottom, AppSpacing.xSmall) // 8 pt снизу.
    }

    /// Содержимое по состоянию загрузки.
    @ViewBuilder
    private var content: some View {
        switch model.phase { // Состояние ViewModel.
        case .loading: // Первая загрузка.
            OverviewLoadingView() // Индикатор.
        case .failed: // Ошибка чтения.
            OverviewErrorView(retry: model.retry) // Ошибка с повтором.
                .padding(.top, AppSpacing.xLarge) // Отступ от заголовка.
        case .loaded(let period, let overview): // Данные периода.
            if overview.isEmpty { // Нет расходов категории за период.
                EmptyPeriodView(period: period, earliestExpenseDate: overview.earliestExpenseDate, today: .today()) { isPickingPeriod = true } // H9.
                    .padding(.top, AppSpacing.xxLarge * 2) // Ближе к центру.
            } else {
                Text(verbatim: ExpenseFormatting.money(overview.total)) // «17 220 ₽».
                    .textStyle(.title) // 28 Bold.
                    .monospacedDigit() // Цифры одинаковой ширины.
                    .padding(.horizontal, AppSpacing.medium) // Поля 16 pt.
                    .padding(.top, AppSpacing.xxSmall) // 4 pt сверху.
                    .padding(.bottom, AppSpacing.medium) // 16 pt до истории.
                    .accessibilityIdentifier("category.total") // Идентификатор для UI-тестов.
                Text(period.phrase(month: LocalizedStringResource.historyTitleMonth, days: LocalizedStringResource.historyTitleDays)) // «История · сентябрь».
                    .textStyle(.sectionTitle) // 20 Semibold.
                    .accessibilityAddTraits(.isHeader) // Заголовок секции.
                    .padding(.horizontal, AppSpacing.medium) // Поля 16 pt.
                    .padding(.bottom, AppSpacing.medium) // 16 pt до первого дня.
                ExpenseHistoryDays(days: overview.days, today: .today(), showsCategory: false, openCategory: nil) // Дни истории категории.
                footer(period: period) // «Это все записи категории за сентябрь…».
            }
        }
    }

    /// Пояснение под историей: это вся история за период; как сменить период.
    private func footer(period: ExpensePeriod) -> some View {
        VStack(alignment: .leading, spacing: 0) { // Два предложения подряд.
            Text(period.phrase(month: LocalizedStringResource.categoryFooterMonth, days: LocalizedStringResource.categoryFooterDays)) // «Это все записи категории за сентябрь.»
            Text(.categoryFooterChangePeriod(period.menuTitle)) // «Сменить период — «Сентябрь» вверху.»
        }
        .textStyle(.captionEmphasized) // 13 Semibold, вторичный цвет.
        .padding(.horizontal, AppSpacing.medium) // Поля 16 pt.
    }
}

/// Эмодзи категории в заголовке экрана: белая карточка 16 pt (Figma E4, «Category header»).
private struct CategoryHeaderEmoji: View {
    /// Категория.
    let category: CategoryReference

    /// Размер эмодзи, масштабируемый вместе с заголовком.
    @ScaledMetric(relativeTo: .title) private var glyph = AppIconSize.medium

    /// Содержимое эмодзи.
    var body: some View {
        Group { // Эмодзи или символ неизвестной категории.
            if let emoji = category.emoji { // Эмодзи — данные категории.
                Text(verbatim: emoji).font(.system(size: glyph)) // 28 pt.
            } else {
                AppIcon.unknownCategory.image // Символ «?».
                    .font(.system(size: glyph * 0.8, weight: .semibold)) // Чуть меньше эмодзи.
                    .foregroundStyle(AppColor.textSecondary) // Вторичный цвет.
            }
        }
        .frame(minWidth: glyph, minHeight: glyph) // Квадратная область символа.
        .padding(AppSpacing.snug) // 10 pt вокруг.
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)) // Белая карточка.
        .accessibilityHidden(true) // Название читается текстом.
    }
}
