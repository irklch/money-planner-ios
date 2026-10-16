// DistributionBar.swift
// Составная горизонтальная полоса распределения расходов по категориям (Figma, Expense Bar `135:54`).

// SwiftUI нужен для View, Layout и фигур.
import SwiftUI

/// Одна полоса 100 % = все расходы периода; ширина сегмента = доля × (ширина − швы).
///
/// Честные пропорции, без минимальной ширины и подписей внутри. Категории < 2 % уже объединены
/// сводкой в нейтральный сегмент «Ещё N» (пунктирная обводка), это не категория «Другое».
struct DistributionBar: View {
    /// Сегменты слева направо.
    let segments: [DistributionSegment]
    /// Итог периода: знаменатель долей.
    let total: Money

    /// Высота полосы, масштабируемая вместе с текстом.
    @ScaledMetric(relativeTo: .body) private var height = AppSize.distributionBar

    /// Содержимое полосы.
    var body: some View {
        SegmentLayout(weights: segments.map(\.amount.minorUnits), total: total.minorUnits, seam: AppSpacing.tiny) { // Ширины по суммам.
            ForEach(segments) { segment in // Сегмент на каждую категорию и «Ещё N».
                segmentView(segment) // Заливка сегмента.
            }
        }
        .frame(height: height) // Высота 14 pt.
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.bar, style: .continuous)) // Скругление всей полосы.
        .accessibilityElement(children: .ignore) // Полоса — один элемент VoiceOver.
        .accessibilityLabel(Text(.homeDistributionAccessibility)) // «Распределение расходов по категориям».
        .accessibilityIdentifier("home.distributionBar") // Идентификатор для UI-тестов.
    }

    /// Заливка сегмента.
    @ViewBuilder
    private func segmentView(_ segment: DistributionSegment) -> some View {
        switch segment.kind { // Вид сегмента.
        case .category(let category): // Категория.
            Rectangle().fill(category.color) // Сплошной цвет категории.
        case .remainder: // «Ещё N».
            Rectangle() // Нейтральная заливка с пунктиром.
                .fill(AppColor.surfaceSecondary) // `surface/secondary`.
                .overlay { // Пунктирная обводка.
                    RoundedRectangle(cornerRadius: AppSpacing.tiny) // Небольшое скругление обводки.
                        .strokeBorder(AppColor.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [AppSpacing.tiny, AppSpacing.tiny])) // Пунктир.
                }
        }
    }
}

/// Раскладка сегментов: ширина пропорциональна сумме, между сегментами — швы 2 pt.
///
/// Перевод копеек в `Double` — только здесь, для геометрии, после точных денежных расчётов.
private struct SegmentLayout: Layout {
    /// Суммы сегментов в копейках.
    let weights: [Int64]
    /// Итог в копейках.
    let total: Int64
    /// Шов между сегментами.
    let seam: CGFloat

    /// Полоса занимает всю предложенную ширину.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0) // Вся ширина и заданная высота.
    }

    /// Размещает сегменты слева направо.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard total > 0, !subviews.isEmpty else { return } // Пустой итог: делить не на что.
        // Ширина без швов.
        let available = max(0, bounds.width - seam * CGFloat(subviews.count - 1))
        // Левая граница следующего сегмента.
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() { // Сегменты по порядку.
            // Ширина сегмента по доле суммы.
            let width = available * CGFloat(Double(weights[index]) / Double(total))
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height)) // Сегмент.
            x += width + seam // Следующий — после шва.
        }
    }
}
