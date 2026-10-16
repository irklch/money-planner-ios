// CategoryDistributionCard.swift
// Секция «Куда ушли деньги»: полоса распределения и категории с суммами и долями (Figma D1, E1x).

// SwiftUI нужен для View и анимации раскрытия.
import SwiftUI

/// Карточка распределения расходов по категориям.
///
/// Сначала видны первые категории, строка «Все категории N» раскрывает полный список на месте,
/// «Свернуть» возвращает компактный вид (Figma: решение 36, без отдельного экрана и шторки).
struct CategoryDistributionCard: View {
    /// Число категорий в компактном виде (Figma D1).
    static let collapsedCount = 4

    /// Сводка периода.
    let overview: ExpenseOverview
    /// Открыть категорию.
    let open: (CategoryReference) -> Void

    /// Полный список раскрыт.
    @State private var isExpanded = false

    /// Содержимое секции.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { // Заголовок и карточка.
            Text(.homeDistributionTitle) // «Куда ушли деньги».
                .textStyle(.sectionTitle) // 20 Semibold.
                .accessibilityAddTraits(.isHeader) // Заголовок секции.
                .padding(.horizontal, AppSpacing.mediumLarge) // Поля 20 pt.
                .padding(.bottom, AppSpacing.snug) // 10 pt до карточки.
            VStack(alignment: .leading, spacing: 0) { // Карточка.
                DistributionBar(segments: overview.segments, total: overview.total) // Полоса «Хранилища».
                    .padding(.horizontal, AppSpacing.medium) // Поля 16 pt.
                    .padding(.top, AppSpacing.mediumLarge) // 20 pt сверху.
                    .padding(.bottom, AppSpacing.small) // 12 pt до строк.
                ForEach(Array(visibleCategories.enumerated()), id: \.element.id) { index, item in // Строки категорий.
                    if index > 0 { Separator() } // Линия между строками.
                    CategoryTotalRow(item: item) { open(item.category) } // Строка категории.
                }
                if overview.categories.count > Self.collapsedCount { // Есть что раскрывать.
                    Separator() // Линия перед строкой действия.
                    toggleRow // «Все категории» / «Свернуть».
                }
            }
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)) // Карточка 24 pt.
            .padding(.horizontal, AppSpacing.medium) // Поля 16 pt.
        }
    }

    /// Категории в текущем виде.
    private var visibleCategories: [CategoryTotal] {
        isExpanded ? overview.categories : Array(overview.categories.prefix(Self.collapsedCount)) // Все или первые.
    }

    /// Строка раскрытия и сворачивания списка.
    private var toggleRow: some View {
        Button { // Раскрытие на месте.
            withAnimation(.snappy) { isExpanded.toggle() } // Плавное раскрытие.
        } label: {
            HStack(spacing: AppSpacing.xSmall) { // Подпись, число, шеврон.
                Text(isExpanded ? .homeCategoriesCollapse : .homeCategoriesShowAll) // «Все категории» / «Свернуть».
                    .textStyle(.button) // Акцентный текст.
                    .fontWeight(.regular) // Body Regular по макету.
                    .frame(maxWidth: .infinity, alignment: .leading) // Подпись слева.
                if !isExpanded { // Число категорий — только в компактном виде.
                    Text(overview.categories.count, format: .number) // «12».
                        .font(AppTextStyle.body.font) // 17 Regular.
                        .foregroundStyle(AppColor.textSecondary) // Вторичный цвет.
                }
                DisclosureChevron() // Шеврон.
            }
            .padding(.horizontal, AppSpacing.medium) // Поля 16 pt.
            .padding(.vertical, AppSpacing.cozy) // 14 pt сверху и снизу.
            .frame(minHeight: AppSize.minimumTapTarget) // Область нажатия 44 pt.
            .contentShape(Rectangle()) // Нажатие по всей строке.
        }
        .buttonStyle(.plain) // Без системной подсветки.
        .accessibilityHint(isExpanded ? Text(verbatim: "") : Text(.homeCategoriesShowAllHint)) // Подсказка раскрытия.
        .accessibilityIdentifier("home.categories.toggle") // Идентификатор для UI-тестов.
    }
}

/// Строка категории: эмодзи, название, ● доля, сумма, шеврон (Figma Category / Row, вариант Overview).
private struct CategoryTotalRow: View {
    /// Сумма категории.
    let item: CategoryTotal
    /// Открыть категорию.
    let open: () -> Void

    /// Размер шрифта среды для раскладки.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Содержимое строки.
    var body: some View {
        Button(action: open) { // Переход к расходам категории.
            HStack(spacing: AppSpacing.small) { // Бейдж, текст, шеврон.
                CategoryBadge(category: item.category) // Эмодзи на нейтральной подложке.
                AdaptiveRowLayout(dynamicTypeSize: dynamicTypeSize).layout { // Текст и сумма.
                    VStack(alignment: .leading, spacing: 1) { // Название и доля.
                        item.category.title.textStyle(.body) // Название категории, переносится.
                        HStack(spacing: AppSpacing.compact) { // Точка цвета и доля.
                            CategoryDot(color: item.category.color) // Цвет категории.
                            Text(verbatim: ExpenseFormatting.share(tenths: item.shareTenths)).textStyle(.caption) // «23 %».
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading) // Текст занимает остаток.
                    Text(verbatim: ExpenseFormatting.money(item.amount)) // «28 430 ₽».
                        .textStyle(.amount) // 17 Medium.
                        .fixedSize() // Сумма не переносится.
                }
                DisclosureChevron() // Шеврон.
            }
            .padding(.horizontal, AppSpacing.medium) // Поля 16 pt.
            .padding(.vertical, AppSpacing.snug) // 10 pt сверху и снизу.
            .contentShape(Rectangle()) // Нажатие по всей строке.
        }
        .buttonStyle(.plain) // Без системной подсветки.
        .accessibilityElement(children: .combine) // Один элемент VoiceOver.
        .accessibilityHint(Text(.historyRowHint)) // «Открывает расходы категории за период».
        .accessibilityIdentifier("home.categoryRow") // Идентификатор для UI-тестов.
    }
}

/// Разделитель строк с отступом от бейджа (Figma: отступ 64 pt).
private struct Separator: View {
    /// Отступ слева, масштабируемый вместе с бейджем.
    @ScaledMetric(relativeTo: .body) private var inset = AppSpacing.medium + AppSize.categoryBadge + AppSpacing.small

    /// Линия 0.5 pt.
    var body: some View {
        Rectangle().fill(AppColor.separator).frame(height: AppSize.hairline).padding(.leading, inset) // Линия с отступом.
    }
}
