import SwiftUI

/// Временный экран проверки запуска. Продуктовый дизайн появится по макетам Figma.
struct LaunchCheckView: View {
    let model: LaunchCheckViewModel

    /// Меняется по нажатию «Проверить соединение»; `.task(id:)` отменяет запрос при уходе с экрана.
    @State private var serverCheckRequest = 0

    var body: some View {
        List {
            storageSection
            serverSection
        }
        .scrollContentBackground(.hidden)
        .background(AppColor.background)
        .navigationTitle(Text(.launchCheckTitle))
        .task {
            model.loadSettings()
            await model.loadLedger() // Готовим хранилище расходов и категорий.
        }
        .task(id: serverCheckRequest) {
            guard serverCheckRequest > 0 else { return }
            await model.checkServer()
        }
        .accessibilityIdentifier("launchCheck")
    }

    // MARK: - Sections

    private var storageSection: some View {
        Section {
            switch model.storage {
            case .loading:
                ProgressView()
            case .ready(let settings):
                StatusRow(icon: .storage, tint: AppColor.success, title: .launchCheckStorageReady)
                LabeledContent {
                    Text(settings.createdAt, format: .dateTime.day().month(.wide).year().hour().minute())
                        .textStyle(.caption)
                } label: {
                    Text(.launchCheckSettingsCreatedAt).textStyle(.body)
                }
            case .failed:
                StatusRow(icon: .failure, tint: AppColor.error, title: .launchCheckStorageFailed)
            }
            switch model.ledger { // Состояние хранилища расходов и категорий.
            case .loading:
                ProgressView()
            case .ready(let summary):
                Text(.launchCheckCategoriesCount(summary.activeCategoryCount)) // Число доступных категорий — признак успешной инициализации.
                    .textStyle(.body)
                    .accessibilityIdentifier("launchCheck.categories") // Идентификатор для UI-тестов.
            case .failed:
                StatusRow(icon: .failure, tint: AppColor.error, title: .launchCheckStorageFailed)
            }
        } header: {
            Text(.launchCheckStorageSection).textStyle(.caption)
        } footer: {
            Text(.launchCheckAppVersion(model.appVersion, model.buildNumber)).textStyle(.caption)
        }
        .listRowBackground(AppColor.surface)
    }

    private var serverSection: some View {
        Section {
            switch model.server {
            case .notConfigured:
                StatusRow(icon: .notConfigured, tint: AppColor.textSecondary, title: .launchCheckServerNotConfigured)
            case .idle:
                StatusRow(icon: .server, tint: AppColor.textSecondary, title: .launchCheckServerIdle)
            case .checking:
                ProgressView {
                    Text(.launchCheckServerChecking).textStyle(.body)
                }
            case .available:
                StatusRow(icon: .success, tint: AppColor.success, title: .launchCheckServerAvailable)
            case .degraded:
                StatusRow(icon: .error, tint: AppColor.error, title: .launchCheckServerDegraded)
            case .failed(let failure):
                ServerFailureRow(failure: failure)
            }
            Button {
                serverCheckRequest += 1
            } label: {
                Label {
                    Text(.launchCheckServerCheckAction).font(AppTextStyle.button.font)
                } icon: {
                    AppIcon.retry.image
                }
            }
            .tint(AppColor.accent)
            .disabled(model.server == .notConfigured || model.server == .checking)
            .accessibilityIdentifier("launchCheck.checkServer")
        } header: {
            Text(.launchCheckServerSection).textStyle(.caption)
        }
        .listRowBackground(AppColor.surface)
    }
}

/// Строка статуса с иконкой и текстом.
private struct StatusRow: View {
    let icon: AppIcon
    let tint: Color
    let title: LocalizedStringResource

    var body: some View {
        Label {
            Text(title).textStyle(.body)
        } icon: {
            icon.image.foregroundStyle(tint)
        }
    }
}

private struct ServerFailureRow: View {
    let failure: LaunchCheckViewModel.ServerFailure

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            StatusRow(icon: icon, tint: AppColor.error, title: title)
            Text(message).textStyle(.caption)
        }
        .padding(.vertical, AppSpacing.xxSmall)
        .accessibilityElement(children: .combine)
    }

    private var icon: AppIcon {
        failure == .noConnection ? .noConnection : .error
    }

    private var title: LocalizedStringResource {
        switch failure {
        case .noConnection: .errorNoConnectionTitle
        case .unavailable: .errorServiceUnavailableTitle
        case .unexpected: .errorUnexpectedTitle
        }
    }

    private var message: LocalizedStringResource {
        switch failure {
        case .noConnection: .errorNoConnectionMessage
        case .unavailable: .errorServiceUnavailableMessage
        case .unexpected: .errorUnexpectedMessage
        }
    }
}

#Preview("Сервер доступен") {
    NavigationStack {
        LaunchCheckView(model: LaunchCheckViewModel(
            configuration: AppDependencies.preview().configuration,
            settingsStore: AppDependencies.preview().settingsStore,
            ledgerSummary: AppDependencies.preview().ledger, // Хранилище временной БД для preview.
            healthService: PreviewHealthService(result: .success(.available))
        ))
    }
}

#Preview("Нет соединения, AX5") {
    NavigationStack {
        LaunchCheckView(model: LaunchCheckViewModel(
            configuration: AppDependencies.preview().configuration,
            settingsStore: AppDependencies.preview().settingsStore,
            ledgerSummary: AppDependencies.preview().ledger, // Хранилище временной БД для preview.
            healthService: PreviewHealthService(result: .failure(.transport(.notConnectedToInternet)))
        ))
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
