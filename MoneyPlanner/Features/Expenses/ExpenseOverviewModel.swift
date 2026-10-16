// ExpenseOverviewModel.swift
// Состояние главного экрана и экрана категории: выбранный период, загрузка сводки, обновление данных.

// Foundation нужен для UUID.
import Foundation
// Observation нужен для макроса @Observable.
import Observation

/// Выбранный период — общий для всех экранов (Figma: «Период — единственный глобальный фильтр»).
///
/// Живёт в `RootView` на время работы приложения; между запусками не сохраняется.
@Observable
final class PeriodSelection {
    /// Выбранный вариант.
    var preset: PeriodPreset

    /// Создаёт выбор с начальным значением из макета.
    init(preset: PeriodPreset = .initial) {
        self.preset = preset // Начальный вариант.
    }
}

/// ViewModel сводки расходов за период: всех категорий (главный экран) или одной категории.
///
/// - Чтение и расчёт выполняет `ExpenseOverviewProviding` на исполнителе хранилища, не на MainActor.
/// - Каждая загрузка получает номер; результат применяется, только если номер текущий.
///   Поздний ответ старого запроса не заменяет актуальный, предыдущая загрузка отменяется.
/// - `run()` держит подписку на изменения данных на время показа экрана: после создания,
///   изменения или удаления расходов сводка перечитывается без сброса периода.
@Observable
final class ExpenseOverviewModel {
    /// Состояние содержимого.
    enum Phase: Equatable {
        /// Первая загрузка: данных ещё нет.
        case loading
        /// Сводка загружена для периода.
        case loaded(ExpensePeriod, ExpenseOverview)
        /// Чтение завершилось ошибкой; это не «расходов нет».
        case failed
    }

    /// Категория экрана; `nil` — все расходы (главный экран).
    let categoryID: UUID?
    /// Текущее состояние содержимого.
    private(set) var phase: Phase = .loading
    /// Идёт перечитывание уже показанных данных (интерфейс не очищается).
    private(set) var isRefreshing = false

    /// Общий выбранный период.
    private let selection: PeriodSelection
    /// Источник сводок.
    private let repository: any ExpenseOverviewProviding
    /// Оповещения об изменении данных.
    private let changes: any LedgerChangeObserving
    /// «Сегодня» в часовом поясе устройства; внедряется для тестов.
    private let today: () -> CalendarDate
    /// Номер последней запущенной загрузки.
    private var generation = 0
    /// Последняя запущенная загрузка.
    private var loadTask: Task<Void, Never>?
    /// Период последней запущенной загрузки.
    private var requestedPeriod: ExpensePeriod?

    /// Создаёт ViewModel.
    init(
        categoryID: UUID? = nil, // Категория или все расходы.
        selection: PeriodSelection, // Общий период.
        repository: any ExpenseOverviewProviding, // Сводки.
        changes: any LedgerChangeObserving, // Оповещения.
        today: @escaping () -> CalendarDate = { .today() } // «Сегодня» устройства.
    ) {
        self.categoryID = categoryID // Область сводки.
        self.selection = selection // Общий период.
        self.repository = repository // Источник данных.
        self.changes = changes // Оповещения.
        self.today = today // Часы.
    }

    /// Выбранный вариант периода.
    var preset: PeriodPreset { selection.preset } // Из общего выбора.

    /// Выбранный период с границами на сегодня.
    var period: ExpensePeriod { ExpensePeriod(preset: selection.preset, today: today()) } // Пересчитывается при смене дня.

    /// Загруженная сводка, если есть.
    var overview: ExpenseOverview? {
        if case .loaded(_, let overview) = phase { return overview } // Данные есть.
        return nil // Загрузка или ошибка.
    }

    /// Выбирает период и загружает сводку. Сетевых запросов нет.
    func select(_ preset: PeriodPreset) {
        guard preset != selection.preset else { return } // Тот же период — ничего не делаем.
        selection.preset = preset // Общий период для всех экранов.
        reload() // Новая сводка.
    }

    /// Загружает сводку, если выбранный период изменился с последней загрузки (например, на другом экране).
    func syncWithSelection() {
        guard requestedPeriod != period else { return } // Данные уже для этого периода.
        reload() // Период сменился.
    }

    /// Работает, пока экран показан: загружает сводку и перечитывает её после изменений данных.
    /// При отмене задачи (уход с экрана) подписка и текущая загрузка отменяются.
    func run() async {
        reload() // Актуальные данные при каждом появлении экрана; период не сбрасывается.
        for await _ in changes.changes() { // Событие после сохранённой транзакции; без polling.
            reload() // Перечитываем без очистки экрана.
        }
        loadTask?.cancel() // Экран ушёл: незавершённая загрузка не нужна.
    }

    /// Повторяет загрузку после ошибки.
    func retry() {
        reload() // Та же загрузка.
    }

    /// Запускает загрузку сводки за выбранный период. Предыдущая загрузка отменяется.
    /// - Returns: задача загрузки (тесты ждут её завершения).
    @discardableResult
    func reload() -> Task<Void, Never> {
        loadTask?.cancel() // Устаревший запрос не нужен.
        generation += 1 // Номер новой загрузки.
        // Номер этой загрузки.
        let current = generation
        // Период этой загрузки.
        let period = period
        requestedPeriod = period // Запоминаем, для какого периода данные.
        switch phase { // Что показывать во время чтения.
        case .loaded: isRefreshing = true // Данные остаются на экране.
        case .loading, .failed: phase = .loading // Первая загрузка или повтор после ошибки.
        }
        // Источник данных для задачи.
        let repository = repository
        // Категория для задачи.
        let categoryID = categoryID
        let task = Task { [weak self] in // Чтение на исполнителе хранилища.
            // Результат чтения: сводка или ошибка.
            let result: Result<ExpenseOverview, any Error>
            do {
                result = .success(try await repository.overview(of: period.elapsed, categoryID: categoryID)) // Сводка за P*.
            } catch {
                result = .failure(error) // Ошибка чтения.
            }
            self?.apply(result, period: period, generation: current) // Применяем, если ответ актуален.
        }
        loadTask = task // Текущая загрузка.
        return task // Для ожидания в тестах.
    }

    /// Применяет результат загрузки, если он относится к последнему запросу.
    private func apply(_ result: Result<ExpenseOverview, any Error>, period: ExpensePeriod, generation: Int) {
        guard generation == self.generation else { return } // Поздний ответ старого запроса.
        isRefreshing = false // Чтение завершено.
        switch result { // Итог чтения.
        case .success(let overview): // Данные прочитаны.
            phase = .loaded(period, overview) // Новая сводка.
        case .failure(let error) where error is CancellationError: // Загрузку отменили.
            break // Состояние меняет следующая загрузка.
        case .failure: // Ошибка чтения БД.
            phase = .failed // Экран ошибки с повтором, а не «расходов нет».
        }
    }
}
