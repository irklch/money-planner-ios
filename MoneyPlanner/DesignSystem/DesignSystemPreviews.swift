#if DEBUG
import SwiftUI

// Previews для проверки токенов дизайн-системы. Подписи — имена токенов для разработчика,
// поэтому выводятся через `Text(verbatim:)` и не попадают в String Catalog.

private struct ColorTokensPreview: View {
    private let tokens: [(String, Color)] = [
        ("background", AppColor.background),
        ("surface", AppColor.surface),
        ("textPrimary", AppColor.textPrimary),
        ("textSecondary", AppColor.textSecondary),
        ("accent", AppColor.accent),
        ("separator", AppColor.separator),
        ("error", AppColor.error),
        ("success", AppColor.success),
    ]

    var body: some View {
        List {
            Section {
                ForEach(tokens, id: \.0) { name, color in
                    HStack(spacing: AppSpacing.small) {
                        RoundedRectangle(cornerRadius: AppRadius.small)
                            .fill(color)
                            .stroke(AppColor.separator)
                            .frame(width: AppSize.minimumTapTarget, height: AppSize.minimumTapTarget)
                        Text(verbatim: name).textStyle(.body)
                    }
                }
            } header: {
                Text(verbatim: "AppColor")
            }
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: AppSize.minimumTapTarget))], spacing: AppSpacing.xSmall) {
                    ForEach(CategoryPalette.colors.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: AppRadius.small)
                            .fill(CategoryPalette.color(at: index))
                            .frame(height: AppSize.minimumTapTarget)
                            .overlay {
                                Text(verbatim: "\(index)").textStyle(.caption)
                            }
                    }
                }
            } header: {
                Text(verbatim: "CategoryPalette")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColor.background)
    }
}

private struct TypographyPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                Text(verbatim: "screenTitle").textStyle(.screenTitle)
                Text(verbatim: "sectionTitle").textStyle(.sectionTitle)
                Text(verbatim: "body — основной текст, который переносится на несколько строк при крупном шрифте")
                    .textStyle(.body)
                Text(verbatim: "caption").textStyle(.caption)
                Text(Decimal(string: "1250.50") ?? 0, format: .currency(code: "RUB")).textStyle(.amount)
                Text(Date.now, format: .dateTime.day().month(.wide).year()).textStyle(.body)
                Text(verbatim: "button").textStyle(.button)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.medium)
        }
        .background(AppColor.background)
    }
}

private struct MetricsAndIconsPreview: View {
    @ScaledMetric(relativeTo: .body) private var iconSize = AppIconSize.small

    var body: some View {
        List {
            Section {
                ForEach(AppIcon.allCases, id: \.self) { icon in
                    Label {
                        Text(verbatim: "\(icon)").textStyle(.body)
                    } icon: {
                        icon.image
                            .resizable()
                            .scaledToFit()
                            .frame(width: iconSize, height: iconSize)
                            .foregroundStyle(AppColor.accent)
                    }
                }
            } header: {
                Text(verbatim: "AppIcon")
            }
            Section {
                ForEach([
                    ("xxSmall", AppSpacing.xxSmall), ("xSmall", AppSpacing.xSmall), ("small", AppSpacing.small),
                    ("medium", AppSpacing.medium), ("large", AppSpacing.large), ("xLarge", AppSpacing.xLarge),
                ], id: \.0) { name, value in
                    HStack {
                        Rectangle().fill(AppColor.accent).frame(width: value, height: AppSpacing.medium)
                        Text(verbatim: "\(name) = \(Int(value))").textStyle(.caption)
                    }
                }
            } header: {
                Text(verbatim: "AppSpacing")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColor.background)
    }
}

#Preview("Цвета") { ColorTokensPreview() }
#Preview("Типографика") { TypographyPreview() }
#Preview("Типографика, AX5") {
    TypographyPreview().environment(\.dynamicTypeSize, .accessibility5)
}
#Preview("Иконки и отступы") { MetricsAndIconsPreview() }
#endif
