import SwiftData
import SwiftUI

@main
struct MoneyPlannerApp: App {
    @State private var bootstrap = AppBootstrap()

    var body: some Scene {
        WindowGroup {
            AppLaunchView(bootstrap: bootstrap)
        }
    }
}

/// Показывает RootView после открытия БД или состояние ошибки с повторной попыткой.
struct AppLaunchView: View {
    let bootstrap: AppBootstrap

    var body: some View {
        Group {
            switch bootstrap.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColor.background)
            case .ready(let dependencies):
                RootView(dependencies: dependencies)
                    .modelContainer(dependencies.modelContainer)
            case .failed:
                ErrorStateView(
                    icon: .error,
                    title: .errorStorageTitle,
                    message: .errorStorageMessage,
                    retry: bootstrap.start
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.background)
            }
        }
        .task {
            if case .loading = bootstrap.state {
                bootstrap.start()
            }
        }
    }
}

#Preview("Ошибка открытия БД") {
    let bootstrap = AppBootstrap { throw CocoaError(.fileReadCorruptFile) }
    AppLaunchView(bootstrap: bootstrap)
}
