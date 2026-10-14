# Money Planner — iOS

Клиент Money Planner: local-first учёт расходов. Этап 1 — основа проекта: структура, дизайн-система, SwiftData, сетевой слой, тесты и CI. Продуктовые экраны (расходы, импорт, вход, аналитика) — следующие этапы.

**Стек:** iOS 26.0+, Swift 6, SwiftUI + MVVM (Observation), SwiftData, URLSession + async/await, Swift Testing и XCTest UI. Сторонних зависимостей нет. Только светлая тема, нативная навигация и Liquid Glass.

## Сверка с бэкендом

Сверка проведена с [`money-planner-backend`](https://github.com/irklch/money-planner-backend) `main` на коммите **`1943bcdad978c879d20373a229be3b69565b0071`** (11.10.2026): код `app/`, `openapi.json`, `docs/architecture-local-first.md`, `docs/production-migration-plan.md` (ред. 5.1), `docs/contract-changes.md`.

Что из этого следует для клиента:

| Тема | Реализовано в коде бэкенда | Запланировано (план миграции) | Решение на iOS |
|---|---|---|---|
| Health-check | `GET /healthz` → `{"status":"ok"}`, без авторизации, вне `/v1` и вне `openapi.json` | `/healthz` — в контракте E0/E1 | `HealthService` — единственный сервис этапа |
| Формат ошибок | `{ error: { code, message, status, retryable, requestId, details[] } }`, заголовки `X-Request-Id`, `Retry-After` | сохраняется («09 — Error Model») | `APIErrorPayload`, `HTTPError` |
| JSON | camelCase, деньги — decimal-строки `"1250.00"`, даты `YYYY-MM-DD` | то же | ключи совпадают с именами свойств; деньги/даты — со следующим этапом |
| Авторизация | `POST /v1/auth/anonymous`, `/v1/auth/refresh`, Bearer JWT | `/v1/auth/guest`, `/auth/apple`, Keychain | не реализуется на этом этапе |
| Расходы, категории, календарь, аналитика | CRUD на сервере (PostgreSQL) | **удаляются** в E1, данные — на устройстве, sync через `/v1/sync/*` | не используются; будут локальными |
| `app_settings` | — | только на устройстве, не синхронизируются | `SchemaV1.AppSettings` |
| Палитра категорий | `category_palette_size = 12`, `colorIndex` | `colorIndex: 0–11` | `CategoryPalette` из 12 цветов |
| Production URL | `deploy/` с заглушкой `api.example.ru` | API Gateway Yandex Cloud, создание окружений — E9 | адреса нет, Release собирается без него |

### Противоречия между документами и кодом

1. **Состав API.** Код и `openapi.json` описывают серверный CRUD расходов, категорий, календаря, аналитики и insights. Архитектура и план миграции (источник истины по MVP) эти модули удаляют. Поэтому ни один из этих endpoint клиентом не используется.
2. **Гостевой вход:** в коде `POST /v1/auth/anonymous`, в плане `POST /v1/auth/guest`.
3. **Коды 401:** в коде `access_token_expired`, `access_token_invalid`, `user_deleted`; в плане (§2.8) — `token_expired`, `refresh_token_invalid`, `session_revoked`, `account_deleted`. Клиент хранит `code` строкой и не зашивает список.
4. **Категории:** в коде `kind: "system" | "custom"`, `archivedAt`; в плане `kind: "user" | "system"`, `isArchived` в payload sync.
5. **Health-check:** в коде `/healthz` (вне схемы OpenAPI, хотя описание API говорит, что все запросы, кроме `/auth/*`, требуют Bearer); прототип YDB использовал `/health` с JWT для подробного ответа. План фиксирует `/healthz`.
6. **Размер выписки:** в коде 10 МБ (`max_upload_bytes`, Caddy 11 МБ), в плане 2 МБ.
7. **Источник истины:** README бэкенда называет главным источником Figma «API Architecture», документы `docs/` — план миграции. Для iOS принят план миграции, так как он новее и прямо объявлен приоритетным для MVP.

**Подходящий read-only endpoint есть:** `GET /healthz`. Он безопасен (без авторизации, без данных пользователя) и сохраняется в новом контракте. Endpoints `/v1/*` требуют авторизации, которая на этом этапе не реализуется.

## Структура

```
Configuration/                 xcconfig окружений и Info.plist с ключом MPAPIBaseURL
MoneyPlanner/
  App/                         точка входа, AppBootstrap (открытие БД), AppDependencies (корень композиции), RootView и AppRoute
  Core/
    Configuration/             AppConfiguration (base URL, версия), LaunchMode (приложение / тесты / previews)
    Networking/
      HTTP/                    HTTPClient, URLSessionHTTPClient, Endpoint, NetworkError, формат ошибок бэкенда
      API/Health/              HealthService: протокол, реализация, endpoint и DTO
    Persistence/               SchemaV1 + AppMigrationPlan, ModelContainerFactory, AppSettingsRepository
  DesignSystem/                AppColor, CategoryPalette, AppTextStyle, AppSpacing/AppRadius/AppIconSize/AppSize, AppIcon, previews
    Components/                ErrorStateView
  Features/LaunchCheck/        временный экран проверки запуска (View + ViewModel)
  Resources/                   Assets.xcassets, Localizable.xcstrings
MoneyPlannerTests/             Swift Testing: сеть через URLProtocol, SwiftData, конфигурация, ViewModel
MoneyPlannerUITests/           XCTest UI: запуск без сети, крупный Dynamic Type
scripts/ci-simulator.sh        выбор симулятора iPhone с iOS 26+
.github/workflows/ios.yml      CI
```

Папки в Xcode — synchronized groups: новый файл в каталоге автоматически попадает в target.

## Запуск и конфигурация API

1. Откройте `MoneyPlanner.xcodeproj`, схема **MoneyPlanner** (shared), симулятор с iOS 26+.
2. Run. Приложение запускается и работает без сети: запросов при старте нет.

Base URL — origin сервера **без `/v1`**; версия входит в путь endpoint (`/v1/...`), а `/healthz` лежит в корне.

| Конфигурация | `MP_API_BASE_URL` | Откуда |
|---|---|---|
| Debug | `http://localhost:8000` | локальный бэкенд: `docker compose up --build api` в `money-planner-backend` |
| Release | пусто | production-адрес не утверждён (план миграции, E9) |

Цепочка: `Configuration/{Debug,Release}.xcconfig` → `MP_API_BASE_URL` → `Configuration/MoneyPlanner-Info.plist` (`MPAPIBaseURL`) → `AppConfiguration.apiBaseURL`. Пустое или некорректное значение даёт `nil`: сетевые сервисы не создаются, на экране — «Адрес сервера не настроен».

Свой адрес (staging, IP компьютера для устройства) — без изменения файлов в git:

```bash
cp Configuration/Local.xcconfig.example Configuration/Local.xcconfig
```

В xcconfig `//` начинает комментарий, поэтому адрес пишется так: `MP_API_BASE_URL = https:/$()/api.example.test`. `Local.xcconfig` в `.gitignore`.

Секретов в конфигурации нет. Глобального разрешения HTTP (`NSAllowsArbitraryLoads`) нет: `http://localhost` не требует исключений ATS, остальные адреса должны быть HTTPS.

**Previews, unit- и UI-тесты** определяются `LaunchMode` (переменные окружения Xcode и аргумент `--ui-testing`): они используют временную БД в памяти и не создают сетевых сервисов.

## Тесты

```bash
xcodebuild test -project MoneyPlanner.xcodeproj -scheme MoneyPlanner -destination 'platform=iOS Simulator,name=iPhone 17'
```

Только unit-тесты:

```bash
xcodebuild test -project MoneyPlanner.xcodeproj -scheme MoneyPlanner -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MoneyPlannerTests
```

Release-сборка без подписи:

```bash
xcodebuild build -project MoneyPlanner.xcodeproj -scheme MoneyPlanner -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Что покрыто:
- **HTTP-клиент** (`StubURLProtocol`, без реального сервера): построение запроса (метод, путь, query с `+`, заголовки, JSON-тело), успешный ответ, ответ без тела (200/204), ошибка сервера в формате бэкенда с `Retry-After` и `X-Request-Id`, ошибка без тела бэкенда (502), неверный JSON, несовпадение типа, ошибка транспорта, отмена задачи → `CancellationError`.
- **HealthService:** `GET /healthz` без тела и авторизации, base URL с префиксом пути, `{"status":"ok"}` → `.available`, мок `HTTPClient`.
- **SwiftData:** настройки сохраняются и читаются после повторного открытия временной файловой БД; одна запись настроек; изоляция in-memory хранилищ; процесс тестов не использует пользовательскую БД и сеть; при ошибке сохранения — прежнее значение и `updatedAt` после неудачного изменения, отсутствие незаписанной записи после неудачного создания, корректная следующая операция, сохранность несохранённых изменений другого контекста.
- **Конфигурация, палитра, LaunchCheckViewModel** с моком `HealthServicing`.
- **UI:** запуск без сети показывает RootView; запуск с Accessibility XXXL; скриншоты запуска.

### CI

`.github/workflows/ios.yml` на каждый PR и push в `main`:
- runner **`macos-26`** (GitHub-hosted), самый новый установленный `Xcode_26*.app`;
- симулятор — первый доступный iPhone с самой новой средой iOS 26+ (`scripts/ci-simulator.sh`);
- `xcodebuild test` (Debug, unit + UI), Release для симулятора и Release для устройства без подписи;
- результаты тестов — артефакт `TestResults.xcresult`.

## Правила дизайн-системы

Все значения — в `DesignSystem/` и `Resources/Assets.xcassets`. В экранах не должно быть HEX/RGB, `Color(red:…)`, `.font(.system(size:))`, числовых `padding`/`spacing`/`cornerRadius` и строковых имён SF Symbols.

| Что | Как использовать | Где определено |
|---|---|---|
| Цвет | `AppColor.textPrimary`, `CategoryPalette.color(at: colorIndex)` | значения — `Assets.xcassets/Colors`, `CategoryPalette`, `AccentColor` |
| Текст | `.textStyle(.body)`; шрифт без цвета — `AppTextStyle.button.font` | `AppTypography.swift` |
| Отступы, радиусы, размеры | `AppSpacing.medium`, `AppRadius.medium`, `AppIconSize.small`, `AppSize.minimumTapTarget` | `AppMetrics.swift` |
| Иконки | `AppIcon.retry.image`, `AppIcon.retry.systemName` | `AppIcon.swift` |
| Изображения | генерируемый `ImageResource`: `Image(.name)` | `Assets.xcassets` |

- Генерация `Color.xxx`/`UIColor.xxx` из каталога **выключена** (`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = NO`): единственный доступ к цветам — `AppColor` и `CategoryPalette`, которые ссылаются на сгенерированные `ColorResource`.
- Типографика опирается на системные text styles и масштабируется Dynamic Type. Не ограничивайте высоту текста и `lineLimit` там, где текст должен переноситься. Иконки рядом с текстом масштабируйте через `@ScaledMetric(relativeTo:)`.
- Уникальную геометрию одного экрана можно задать константой рядом с экраном, если это не общий токен.
- Liquid Glass — только нативные средства: `NavigationStack`, toolbar, `.buttonStyle(.glass)` / `.glassProminent`, `glassEffect`. Не имитируйте стекло прозрачностью и blur.
- Эмодзи категорий — данные категории, а не ресурсы.
- **Все значения токенов предварительные** (цвета, шкалы, роли текста): макет Figma ещё не утверждён. При вёрстке по Figma меняются значения в каталоге и `DesignSystem/`, а не экраны.

Previews: `DesignSystemPreviews.swift` (цвета, палитра, типографика, AX5, иконки и отступы), `ErrorStateView`, `RootView` (обычный размер и AX3), `LaunchCheckView` (AX5), экран ошибки открытия БД.

## Локализация

- Основной язык — русский (`developmentRegion = ru`, `sourceLanguage = ru`). Все строки — в `Resources/Localizable.xcstrings`, включая ошибки, кнопки и accessibility-тексты.
- Ключи семантические: `экран.элемент.смысл` (`launchCheck.server.checkAction`, `error.noConnection.title`). Новые ключи добавляются вручную (`extractionState: manual`).
- Доступ — символы, которые генерирует Xcode (`STRING_CATALOG_GENERATE_SYMBOLS = YES`): `Text(.actionRetry)`, `String(localized: .errorNoConnectionTitle)`. Параметры — форматные аргументы ключа: `Text(.launchCheckAppVersion(version, build))`. Множественные формы — вариации Plural в каталоге. Строки не склеиваются.
- Даты, суммы и числа — через `FormatStyle` с текущей локалью: `Text(date, format: .dateTime…)`, `Text(amount, format: .currency(code: "RUB"))`.
- `message` из ответа сервера не показывается пользователю: UI получает категорию ошибки и берёт текст из каталога.
- Тексты в previews дизайн-системы — имена токенов для разработчика (`Text(verbatim:)`), не пользовательский текст.

## Вызов API одним методом

```swift
// AppDependencies — единственное место сборки:
let client = URLSessionHTTPClient(baseURL: configuration.apiBaseURL!)
let healthService: any HealthServicing = HealthService(client: client)

// ViewModel:
let health = try await healthService.fetchHealth()   // ServerHealth.available / .degraded
```

Вызывающий код не видит `URLSession`, `URLRequest`, заголовков и JSON. Новый сервис:
1. `Core/Networking/API/<Area>/`: DTO (`nonisolated struct …: Decodable, Sendable`), endpoint (`Endpoint<DTO>(name:method:path:query:headers:body:)`), протокол и реализация сервиса с типизированными параметрами и результатом (`async throws`).
2. Регистрация в `AppDependencies.make`, передача во ViewModel через инициализатор.
3. Тесты: сервис — через `StubURLProtocol` (проверка запроса и маппинга), ViewModel — через мок протокола сервиса.

Ошибки: `NetworkError` — `.transport(URLError.Code)`, `.http(HTTPError)` (статус, тело бэкенда, `Retry-After`, `requestId`), `.decoding(path:)`, `.invalidResponse`, `.invalidURL`, `.encoding`. Отмена задачи — `CancellationError`. `isRetryable` повторяет правило плана §8.1 (нет сети, таймаут, 5xx, 429), но автоматических повторов пока нет.

Логи (`os.Logger`, категория `network`) содержат только имя операции, статус, длительность и `X-Request-Id`. URL, query, заголовки, тела, токены и данные выписок не логируются.

## Границы слоёв

| Слой | Отвечает за | Не делает |
|---|---|---|
| **View** (SwiftUI) | отображение состояния ViewModel, токены дизайн-системы, локализованные строки, `.task(id:)` для отмены при уходе | не обращается к сети и SwiftData напрямую, не форматирует ошибки сервера |
| **ViewModel** (`@Observable`, MainActor) | состояние экрана, вызов методов сервисов и хранилищ, перевод ошибок в пользовательские категории | не строит запросы, не знает о DTO и `ModelContext` |
| **Networking** (`nonisolated`, `Sendable`) | endpoints, DTO, HTTP, ошибки; работа вне главного потока (`@concurrent`) | не знает о UI и SwiftData; DTO не являются моделями SwiftData |
| **Persistence** | схема, миграции, контейнер, репозитории; наружу — снимки (`AppSettingsSnapshot`) | не знает о сети и UI |
| **App** | сборка зависимостей, запуск, навигация | бизнес-логики нет |

Изоляция: target приложения собирается с `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` и Swift 6. UI, ViewModel и репозиторий настроек — на MainActor; сетевой слой и конфигурация явно `nonisolated` и `Sendable`, `URLSessionHTTPClient.send` — `@concurrent`. `@unchecked Sendable` не используется. Будущие тяжёлые операции с БД (импорт, sync) — в отдельном `@ModelActor`.

## SwiftData

- `SchemaV1` (`VersionedSchema`) с единственной моделью `AppSettings` (`app_settings`): одна запись на устройство, ключ `device`, флаг онбординга, даты создания и изменения. Настройки не синхронизируются (архитектура backend §8.1).
- `AppMigrationPlan` (`SchemaMigrationPlan`) — пока одна версия. Изменение модели = новая `SchemaV2` + этап миграции; `SchemaV1` не правится.
- `ModelContainerFactory`: постоянное хранилище `Application Support/MoneyPlanner.store` для приложения и изолированное in-memory для previews и тестов. CloudKit отключён (`cloudKitDatabase: .none`).
- Ошибка открытия БД → экран «Не удалось открыть данные» с «Повторить». БД не удаляется и не подменяется временной.

### Контекст репозитория настроек и ошибки сохранения

- `AppSettingsRepository` работает в **собственном** `ModelContext(container)`, а не в `container.mainContext`. Автосохранение этого контекста выключено (`autosaveEnabled = false`): запись происходит только явным `save()` внутри репозитория.
- Если `save()` завершается ошибкой, репозиторий вызывает `rollback()` своего контекста и пробрасывает **исходную** ошибку вызывающему коду. Правило одинаково для создания записи по умолчанию (`load()` при первом запуске) и для изменения (`setOnboardingCompleted`).
- После ошибки в контексте нет несохранённых изменений: следующее чтение возвращает последнее сохранённое значение и `updatedAt`, несохранённая новая запись исчезает, и позже её не запишет автосохранение. Следующая успешная операция работает как обычно.
- Откат касается только контекста репозитория: несохранённые изменения `mainContext` (`@Query` во View) и других контекстов не теряются.
- Изоляция и интерфейс не меняются: репозиторий на MainActor, наружу — `AppSettingsStoring` и `AppSettingsSnapshot`.
- Для тестов есть внутренний инициализатор `init(container:now:save:)` с подменой операции сохранения. Тесты бросают ошибку до настоящего `ModelContext.save()` и проверяют реальное состояние контекста и хранилища после `rollback()`.

## Предварительные решения

- Значения цветов, палитры категорий, шкал и ролей текста — до утверждения Figma.
- Base URL Release пустой до создания окружений (E9). Staging подключается через `Local.xcconfig` или значение в `Release.xcconfig`, когда адрес будет утверждён.
- `HealthService` проверяет подход; запрос выполняется только по кнопке на временном экране.
- Экран проверки запуска временный и будет заменён продуктовым RootView.
- Swift 6 language mode включён во всех targets.

## Следующий этап

- Локальная модель `Expense`, `Category` (системные категории со стабильными UUID), `DayMark` в `SchemaV2` с миграцией; репозитории в `@ModelActor`.
- Типы `Money` (decimal-строки, целые копейки) и календарных дат `YYYY-MM-DD`.
- Сопоставление категории с `CategoryPalette`.
- Вёрстка по Figma с обновлением токенов.
- После утверждения контракта E0: гостевая авторизация, Keychain, политика повторов §8.1, sync и импорт.
