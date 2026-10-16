// OverviewScreenSupport.swift
// Общее поведение экранов сводки: жизненный цикл ViewModel, sheet периода, загрузка и ошибка.

// SwiftUI нужен для View и модификаторов.
import SwiftUI

/// Подключает ViewModel сводки к экрану.
///
/// - `.task` запускает `run()` на время показа экрана: загрузка и подписка на изменения данных;
///   при уходе с экрана задача отменяется вместе с подпиской и загрузкой.
/// - Смена общего периода на другом экране перечитывает данные (`syncWithSelection`).
/// - Sheet «Период» с непрозрачным фоном.
private struct OverviewLifecycle: ViewModifier {
    /// ViewModel экрана.
    let model: ExpenseOverviewModel
    /// Общий выбранный период.
    let selection: PeriodSelection
    /// Показан ли sheet выбора периода.
    @Binding var isPickingPeriod: Bool

    /// Экран с жизненным циклом.
    func body(content: Content) -> some View {
        content
            .task { await model.run() } // Загрузка и подписка, пока экран показан.
            .onChange(of: selection.preset) { model.syncWithSelection() } // Период сменили на другом экране.
            .sheet(isPresented: $isPickingPeriod) { // Выбор периода.
                PeriodPickerSheet(selected: model.preset, today: .today()) { model.select($0) } // Применяем выбор.
            }
    }
}

extension View {
    /// Подключает ViewModel сводки, общий период и sheet выбора периода.
    func overviewLifecycle(model: ExpenseOverviewModel, selection: PeriodSelection, isPickingPeriod: Binding<Bool>) -> some View {
        modifier(OverviewLifecycle(model: model, selection: selection, isPickingPeriod: isPickingPeriod)) // Общий модификатор.
    }
}

/// Первая загрузка локальных данных.
struct OverviewLoadingView: View {
    /// Индикатор загрузки.
    var body: some View {
        ProgressView() // Системный индикатор.
            .frame(maxWidth: .infinity, minHeight: AppSize.emptyStateBadge * 3) // Место под содержимое.
            .accessibilityLabel(Text(.overviewLoading)) // «Загружаем расходы».
            .accessibilityIdentifier("overview.loading") // Идентификатор для UI-тестов.
    }
}

/// Ошибка чтения локальных данных с повтором — не «расходов нет».
struct OverviewErrorView: View {
    /// Повторить чтение.
    let retry: () -> Void

    /// Состояние ошибки.
    var body: some View {
        ErrorStateView(icon: .error, title: .errorOverviewTitle, message: .errorOverviewMessage, retry: retry) // Общий компонент ошибки.
            .accessibilityIdentifier("overview.error") // Идентификатор для UI-тестов.
    }
}
