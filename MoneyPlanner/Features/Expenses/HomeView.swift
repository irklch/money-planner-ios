// HomeView.swift
// Главный экран «Обзор»: период, итог, распределение по категориям и история за период.
// Figma «FINAL UI · MVP»: D1 `295:5944`, D1s `295:6110`, D3 `295:6198`, H9 `295:6633`, E1x `303:11616`, E4 `304:11771`.

// SwiftUI нужен для View, ScrollView и toolbar.
import SwiftUI

/// Главный экран.
///
/// Без Tab Bar. Все блоки используют один выбранный период. Список категорий раскрывается
/// на месте, история за период — сразу ниже, без отдельного экрана.
struct HomeView: View {
    /// ViewModel главного экрана.
    let model: ExpenseOverviewModel
    /// Общий выбранный период.
    let selection: PeriodSelection
    /// Открыть категорию.
    let openCategory: (CategoryReference) -> Void

    /// Показан ли sheet выбора периода.
    @State private var isPickingPeriod = false
    /// Капсула периода ушла за верх экрана: в toolbar появляется компактная кнопка.
    @State private var isPeriodMenuHidden = false

    /// Содержимое экрана.
    var body: some View {
        ScrollView { // Прокрутка всего экрана.
            LazyVStack(alignment: .leading, spacing: 0) { // Длинная история создаётся лениво.
                PeriodMenuButton(period: model.period) { isPickingPeriod = true } // «Сентябрь ⌃⌄».
                    .padding(.horizontal, AppSpacing.mediumLarge) // Поля 20 pt.
                    .padding(.bottom, AppSpacing.xSmall) // 8 pt под капсулой.
                    .onScrollVisibilityChange(threshold: 0.01) { isPeriodMenuHidden = !$0 } // Компактная кнопка, когда капсула скрыта.
                content // Содержимое по состоянию.
            }
            .padding(.bottom, AppSpacing.xxLarge) // Отступ после истории.
        }
        .scrollIndicators(.automatic) // Системные индикаторы.
        .background { HomeBackground() } // Тёплый фон со свечением.
        .navigationTitle(Text(.homeTitle)) // «Обзор» — large title.
        .navigationBarTitleDisplayMode(.large) // Крупный заголовок на холсте.
        .toolbar { // Компактная кнопка периода.
            if isPeriodMenuHidden { // Основная капсула не видна: два селектора одновременно не показываем.
                ToolbarItem(placement: .topBarLeading) { // Слева, как в макете.
                    PeriodToolbarButton(period: model.period) { isPickingPeriod = true } // Тот же sheet.
                }
            }
        }
        .overviewLifecycle(model: model, selection: selection, isPickingPeriod: $isPickingPeriod) // Загрузка, обновления, sheet.
        .accessibilityIdentifier("home") // Идентификатор для UI-тестов.
    }

    /// Содержимое по состоянию загрузки.
    @ViewBuilder
    private var content: some View {
        switch model.phase { // Состояние ViewModel.
        case .loading: // Первая загрузка.
            OverviewLoadingView() // Индикатор.
        case .failed: // Ошибка чтения.
            OverviewErrorView(retry: model.retry) // Ошибка с повтором.
                .padding(.top, AppSpacing.xLarge) // Отступ от капсулы.
        case .loaded(let period, let overview): // Данные периода.
            if overview.isEmpty { // Нет расходов за период.
                EmptyPeriodView(period: period, earliestExpenseDate: overview.earliestExpenseDate, today: .today()) { isPickingPeriod = true } // H9.
                    .padding(.top, AppSpacing.xxLarge * 2) // Состояние ниже капсулы, ближе к центру.
            } else {
                HomeTotalView(overview: overview) // Итог.
                CategoryDistributionCard(overview: overview, open: openCategory) // Полоса и категории.
                    .padding(.bottom, AppSpacing.section) // 28 pt до истории.
                Text(period.phrase(month: LocalizedStringResource.historyTitleMonth, days: LocalizedStringResource.historyTitleDays)) // «История · сентябрь».
                    .textStyle(.sectionTitle) // 20 Semibold.
                    .accessibilityAddTraits(.isHeader) // Заголовок секции.
                    .padding(.horizontal, AppSpacing.mediumLarge) // Поля 20 pt.
                    .padding(.bottom, AppSpacing.small) // 12 pt до первого дня.
                ExpenseHistoryDays(days: overview.days, today: .today(), showsCategory: true, openCategory: openCategory) // Дни истории.
            }
        }
    }
}

/// Итог периода: «Потрачено · 1–30 сентября» и крупная сумма.
private struct HomeTotalView: View {
    /// Сводка периода.
    let overview: ExpenseOverview

    /// Содержимое итога.
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) { // Подпись и сумма.
            Text(.homeSpent(ExpenseFormatting.range(overview.period, today: .today()))) // «Потрачено · 1–30 сентября».
                .textStyle(.subheadline) // 15, вторичный цвет.
            Text(ExpenseFormatting.heroMoney(overview.total)) // «124 580 ₽», знак валюты третичным цветом.
                .heroAmountStyle() // 56 Medium.
                .lineLimit(1) // Сумма в одну строку.
                .minimumScaleFactor(0.4) // Крупная сумма уменьшается, а не обрезается.
        }
        .padding(.horizontal, AppSpacing.mediumLarge) // Поля 20 pt.
        .padding(.top, AppSpacing.section) // 28 pt сверху.
        .padding(.bottom, AppSpacing.xxLarge) // 40 pt снизу.
        .accessibilityElement(children: .combine) // Итог читается одной фразой.
        .accessibilityIdentifier("home.total") // Идентификатор для UI-тестов.
    }
}

/// Фон главного экрана: `background/primary` и тёплое свечение сверху справа (Figma «Ambient glow»).
private struct HomeBackground: View {
    /// Фон с радиальным свечением.
    var body: some View {
        AppColor.background // Тёплый off-white.
            .overlay(alignment: .topTrailing) { // Свечение в правом верхнем углу.
                RadialGradient( // Мягкий градиент без blur и прозрачных поверхностей.
                    colors: [AppColor.accentGlow.opacity(0.38), AppColor.accentGlow.opacity(0)], // ≤ 38 % по макету.
                    center: .topTrailing, startRadius: 0, endRadius: AppSize.emptyStateBadge * 6 // Радиус ~380 pt.
                )
            }
            .ignoresSafeArea() // Под статус-баром и toolbar.
    }
}
