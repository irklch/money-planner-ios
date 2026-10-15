# Money Planner — iOS

Клиент Money Planner: local-first учёт расходов. Этап 1 — основа проекта: структура, дизайн-система, SwiftData, сетевой слой, тесты и CI. Этап 2 — локальное хранение расходов, категорий и отметок дня с подготовкой к sync: данные работают без сети и переживают перезапуск. Продуктовые экраны, импорт, вход, sync и аналитика — следующие этапы.

**Стек:** iOS 26.0+, Swift 6, SwiftUI + MVVM (Observation), SwiftData, URLSession + async/await, Swift Testing и XCTest UI. Сторонних зависимостей нет. Только светлая тема, нативная навигация и Liquid Glass.

## Сверка с бэкендом

Сверка проведена с [`money-planner-backend`](https://github.com/irklch/money-planner-backend) `main` на коммите **`1943bcdad978c879d20373a229be3b69565b0071`** (11.10.2026): код `app/`, `openapi.json`, `docs/architecture-local-first.md`, `docs/production-migration-plan.md` (ред. 5.1), `docs/contract-changes.md`.

Что из этого следует для клиента:

| Тема | Реализовано в коде бэкенда | Запланировано (план миграции) | Решение на iOS |
|---|---|---|---|
| Health-check | `GET /healthz` → `{"status":"ok"}`, без авторизации, вне `/v1` и вне `openapi.json` | `/healthz` — в контракте E0/E1 | `HealthService` — единственный сервис этапа |
| Формат ошибок | `{ error: { code, message, status, retryable, requestId, details[] } }`, заголовки `X-Request-Id`, `Retry-After` | сохраняется («09 — Error Model») | `APIErrorPayload`, `HTTPError` |
| JSON | camelCase, деньги — decimal-строки `"1250.00"`, даты `YYYY-MM-DD` | то же | ключи совпадают с именами свойств; деньги — `Money`, даты — `CalendarDate` (этап 2) |
| Авторизация | `POST /v1/auth/anonymous`, `/v1/auth/refresh`, Bearer JWT | `/v1/auth/guest`, `/auth/apple`, Keychain | не реализуется на этом этапе |
| Расходы, категории, календарь, аналитика | CRUD на сервере (PostgreSQL) | **удаляются** в E1, данные — на устройстве, sync через `/v1/sync/*` | не используются; будут локальными |
| `app_settings` | — | только на устройстве, не синхронизируются | `SchemaV2.AppSettings` (не синхронизируется) |
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

### Этап 2: сверка с контрактом E0

Сверка проведена с `money-planner-backend` `main` на коммите **`36ce86b0956c5297b16776087b8869ad1df64818`** (14.10.2026): `contract/` (`openapi.yaml`, `system-categories.json`, `config-parameters.json`, `vectors/`, `swift/comment_rule_check.swift`), `docs/api-contract.md` (утверждён, ревью E0 11.10.2026), `docs/architecture-local-first.md` §8, `docs/production-migration-plan.md` §3–§4, §6.5. Старый серверный CRUD (`openapi.json`, `app/`) и `prototype/` production-контрактом не считаются.

| Решение | Источник |
|---|---|
| `Expense` — **одна сущность** для ручных и импортированных расходов, без признака источника; название операции из выписки — в `comment`; у сохранённых расходов одинаковый набор редактируемых полей (сумма, категория, дата, комментарий) | архитектура §8.1; `ExpensePayload` (`additionalProperties: false`) |
| Сумма — целые копейки `Int64`; в API — строка ровно с 2 знаками, `0.01` … `999999999.99`, валюта RUB | `Money` в `openapi.yaml`; api-contract §6, §12 п. 7 |
| Дата расхода — календарный день `YYYY-MM-DD`, без часового пояса | `CalendarDate` в `openapi.yaml`; план §7.3 |
| Комментарий: NFC → удалить Cc → обрезать Zs/Zl/Zp → пусто = `null`; ≤ 200 Unicode scalar values; ручной ввод длиннее — ошибка, обрезка по графемам — только для импорта | план §3.3; api-contract §9; `vectors/comment.json` |
| Категории: системные — фиксированные UUID реестра (12, статус approved), «Другое» не архивируется; пользовательские — `name` 1–24 scalar values, эмодзи — 1 графема, `colorIndex` 0–11; не удаляются, а архивируются; разархивирование — после MVP; уникальности названий в контракте нет | план §3.2; api-contract §6, §9.1; `system-categories.json` |
| В sync системная категория — только состояние `{kind: system, isArchived}`; пока пользователь её не менял, мутации нет | план §3.2; `SystemCategoryPayload` |
| Расход ссылается на категорию UUID без FK; связь сохраняется после архивирования | план §3.2; архитектура §8.4 |
| `DayMark`: `entityId = UUIDv5(NS_DAY_MARK, дата)`, не удаляется (`isMarked=false`), расход главнее отметки, после удаления расхода отметка не восстанавливается, дата ≤ сегодня | план §4; `vectors/day-mark-id.json` |
| Метаданные записи: UUID клиента, `createdAt`/`updatedAt` (часы устройства), `deletedAt` (tombstone, delete wins), серверная `version` → `baseVersion`; outbox с `mutationId`, `schemaVersion = 1`, порядок отправки; изменение данных и outbox — одна локальная транзакция | архитектура §8.1, §8.2, §8.4; `MutationBase` |
| Автоматического обнаружения дубликатов нет | архитектура §8.1 |

**Согласовано с владельцем продукта 14.10.2026** (задача этапа расходилась с контрактом):
1. Запись «Из выписки» как сумма за день и категорию с неизменной датой в контракте не описана: в `ExpensePayload` нет признака источника, и синхронизировать его нельзя. Принято — **строго по контракту**: одна сущность, ограничение «меняется только сумма» не реализуется.
2. Уникальность названий пользовательских категорий **не проверяется** (в контракте правила нет).
3. Правка названия, эмодзи и цвета неархивной пользовательской категории **добавлена** (payload sync это допускает).

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
    Domain/                    Money, CalendarDate, правила текста, UUIDv5 отметки дня, реестр системных категорий, снимки и ошибки
    Persistence/               SchemaV1 (заморожена), SchemaV2, AppMigrationPlan, ModelContainerFactory,
                               AppSettingsRepository, протоколы репозиториев, LedgerStore (ModelActor)
    Sync/                      DTO payload мутаций (expense, category, day_mark), снимок мутации outbox
  DesignSystem/                AppColor, CategoryPalette, AppTextStyle, AppSpacing/AppRadius/AppIconSize/AppSize, AppIcon, previews
    Components/                ErrorStateView
  Features/LaunchCheck/        временный экран проверки запуска (View + ViewModel)
  Resources/                   Assets.xcassets, Localizable.xcstrings
MoneyPlannerTests/             Swift Testing: сеть через URLProtocol, SwiftData, миграция, слой данных, конфигурация, ViewModel
  Fixtures/Contract/           копии векторов и реестра из contract/ бэкенда (36ce86b)
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
- **Миграция:** реальный временный файл V1 → V2 с сохранением флага онбординга и обеих дат; данные V2 после повторного открытия; нечитаемый файл не удаляется и не перезаписывается.
- **Деньги:** точное разбиение decimal-строк, неверный формат (знак, экспонента, запятая, ведущие нули, не-ASCII цифры), лишние знаки без округления, переполнение Int64 при разборе и сложении, диапазон суммы расхода.
- **Даты:** високосные годы (2000, 2024; не 1900, 2100), несуществующие дни, неверный формат, арифметика через 29 февраля, «сегодня» в разных поясах; дата расхода не сдвигается при чтении в другом поясе.
- **Правила текста:** все 37 векторов `comment.json`; кириллица 200/201; составные эмодзи (ZWJ, тон кожи, флаг) у границы; название и эмодзи категории; `colorIndex`.
- **Контракт:** каталог системных категорий совпадает с реестром (UUID, эмодзи, цвет, порядок, архивируемость, русские названия из String Catalog); UUIDv5 отметки дня — по векторам.
- **Слой данных (`LedgerStore`):** системные категории без дубликатов при повторной и параллельной инициализации и без сброса архивирования; создание и правка пользовательской категории; архивирование («Другое» нельзя); архивная категория в истории, но запрещена для новых расходов и переноса; CRUD расхода с проверкой payload outbox; фильтр периода по граничным дням и категории, стабильный порядок; tombstone и мутация удаления; сохранение после повторного открытия файла; атомарность: при ошибке сохранения не остаётся ни расхода, ни мутации, ни снятой отметки; следующая операция после ошибки; инварианты «Дня без расходов».
- **Конфигурация, палитра, LaunchCheckViewModel** с моком `HealthServicing`; подготовка хранилища (12 категорий).
- **UI:** запуск без сети показывает RootView и «Категории: 12»; запуск с Accessibility XXXL; скриншоты запуска.

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
| **Domain** (`nonisolated`, `Sendable`) | `Money`, `CalendarDate`, правила полей, реестр системных категорий, снимки и черновики | не знает о SwiftData, сети и UI |
| **Persistence** | схема, миграции, контейнер, репозитории; наружу — протоколы и снимки (`AppSettingsSnapshot`, `ExpenseSnapshot`, `CategorySnapshot`) | не знает о сети и UI; `PersistentModel` и `ModelContext` не выходят за границу актора |
| **Sync** (`nonisolated`) | DTO payload мутаций, кодирование JSON | не является моделью SwiftData и снимком для UI |
| **App** | сборка зависимостей, запуск, навигация | бизнес-логики нет |

Изоляция: target приложения собирается с `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` и Swift 6. UI, ViewModel и репозиторий настроек — на MainActor; сетевой слой, доменные типы и конфигурация явно `nonisolated` и `Sendable`, `URLSessionHTTPClient.send` — `@concurrent`. Расходы, категории и отметки дня — в `actor LedgerStore: ModelActor`: его методы выполняются на исполнителе актора с собственным контекстом, а синхронный инициализатор при изоляции модуля по умолчанию — на MainActor (как у `@ModelActor`). `@unchecked Sendable` не используется.

## SwiftData

- `SchemaV2` (`VersionedSchema`): `AppSettings` (без изменений с V1), `Category`, `Expense`, `DayMark`, `OutboxMutation`. Связи — UUID без SwiftData-relationship: FK на клиенте нет (план §3.2), каскадного удаления категории с расходами нет.
- `SchemaV1` заморожена; `typealias AppSettings` и `AppMigrationPlan` вынесены из её файла. Изменение модели = новая `SchemaV3` + этап миграции.
- `AppMigrationPlan`: `[SchemaV1, SchemaV2]`, этап `lightweight(V1 → V2)` — добавление сущностей, настройки (флаг онбординга, `createdAt`, `updatedAt`) переносятся без изменений.
- `ModelContainerFactory` открывает текущую схему V2: постоянное хранилище `Application Support/MoneyPlanner.store` для приложения и изолированное in-memory для previews и тестов. CloudKit отключён (`cloudKitDatabase: .none`).
- Ошибка открытия или миграции БД → экран «Не удалось открыть данные» с «Повторить». БД не удаляется, не пересоздаётся и не подменяется временной.

### Модели V2

| Модель | Поля | Sync |
|---|---|---|
| `Category` | `id` (UUID, unique), `kindRaw` (`system`/`user`), `name`, `emoji`, `colorIndex` (только `user`), `sortOrder`, `isArchived`, `createdAt`, `updatedAt`, `serverVersion` | `category`, только upsert |
| `Expense` | `id`, `amountMinorUnits` (Int64 копеек), `categoryID` (UUID), `dateKey` (`YYYYMMDD`), `comment`, `createdAt`, `updatedAt`, `deletedAt` (tombstone), `serverVersion`; индексы по `dateKey` и `categoryID` | `expense`, upsert / delete |
| `DayMark` | `id` (UUIDv5 по дате), `dateKey`, `isMarked`, `createdAt`, `updatedAt`, `serverVersion` | `day_mark`, только upsert |
| `OutboxMutation` | `mutationID` (unique), `sequence` (порядок отправки), `entityTypeRaw`, `entityID`, `opRaw`, `baseVersion`, `entityCreatedAt`, `updatedAt`, `deletedAt`, `schemaVersion = 1`, `payload` (JSON) | конверт `MutationBase` |

`serverVersion = 0` — запись на сервер ещё не попадала (`baseVersion = 0` — создание). Тело мутации фиксируется при записи: повтор с тем же `mutationId` и другим телом сервер отклонил бы (`mutation_id_reused`). Системная категория хранится локально как строка с UUID реестра; её название, эмодзи и цвет — константы `SystemCategory`, название — из String Catalog (`category.system.<key>`).

### Слой данных: `LedgerStore`

- Один `actor LedgerStore: ModelActor` на контейнер, создаётся в `AppDependencies.make`. ViewModel получают узкие протоколы: `CategoryRepository`, `ExpenseRepository`, `DayMarkRepository`, `LedgerSummaryProviding`. Параметры и результаты — Sendable-значения (`ExpenseDraft`, `NewCategory`, `ExpenseSnapshot`, `CategorySnapshot`, `DayMarkSnapshot`), `PersistentModel` и `ModelContext` наружу не выходят.
- Собственный `ModelContext` с `autosaveEnabled = false`. Каждая операция — синхронная транзакция `write { … }` без `await` внутри: изменение данных и мутация outbox (и, если нужно, снятие отметки дня) сохраняются одним `save()`. При любой ошибке — `rollback()` и проброс исходной ошибки: в контексте не остаётся ни одной части операции, и позже её не запишет автосохранение.
- Проверка полей (`LedgerError`) выполняется до записи.
- Системные категории создаются при первом обращении к хранилищу (`ensureSystemCategories`) одной транзакцией: недостающие UUID реестра вставляются, существующие не меняются (архивирование не сбрасывается). Актор выполняет вызовы по очереди, поэтому параллельные вызовы не создают дубликатов. Мутаций при этом нет.
- Тестовая точка подмены — `init(container:now:timeZone:save:)`: управляемые часы, часовой пояс и операция сохранения.

### Правила изменений

| Операция | Правило | Ошибка |
|---|---|---|
| Новый расход | сумма 0.01 … 999 999 999.99; комментарий ≤ 200 scalar values после нормализации; категория существует и не архивирована; снимает отметку «День без расходов» на эту дату | `invalidAmount`, `commentTooLong`, `categoryNotFound`, `categoryArchived` |
| Изменение расхода | меняются сумма, категория, дата, комментарий (у ручных и сохранённых из выписки одинаково); перенос в архивную категорию запрещён, расход в уже архивной категории правится; на новой дате отметка снимается | то же + `notFound` |
| Удаление расхода | `deletedAt` + мутация `delete` без payload; запись остаётся как tombstone, из истории, `expense(id:)` и сводки исчезает | `notFound` |
| Новая категория | название 1–24, эмодзи — 1 графема, `colorIndex` 0–11; `sortOrder` — после существующих; одинаковые названия допустимы | `invalidCategoryName`, `invalidEmoji`, `invalidColorIndex` |
| Правка категории | только пользовательская и неархивная: название, эмодзи, цвет | `systemCategoryNotEditable`, `categoryArchived` |
| Архивирование | любая, кроме «Другое»; повтор — без новой мутации; разархивирования нет | `categoryNotArchivable` |
| Отметка дня | дата ≤ сегодня (часовой пояс устройства); поставить на день с расходами нельзя; снять можно всегда | `dateInFuture`, `dayHasExpenses` |

Список расходов: `expenses(in: a...b, categoryID:)` — границы включительно, без удалённых; порядок — дата ↓, `createdAt` ↓, UUID ↑.

### Примеры вызовов

```swift
let categories: any CategoryRepository = dependencies.categoryRepository
let expenses: any ExpenseRepository = dependencies.expenseRepository

// Категории для выбора (без архивных) и создание своей.
let available = try await categories.categories(includeArchived: false)
let coffee = try await categories.createCategory(NewCategory(name: "Кофе", emoji: "☕️", colorIndex: 5))

// Ручной расход: сумма из decimal-строки, день — календарная дата.
let expense = try await expenses.createExpense(ExpenseDraft(
    amount: try Money(apiString: "250.50"),
    categoryID: coffee.id,
    date: .today(),
    comment: "Капучино"
))

// История за октябрь, только «Кафе и рестораны».
let october = try CalendarDate(isoString: "2026-10-01")...CalendarDate(isoString: "2026-10-31")
let cafe = try await expenses.expenses(in: october, categoryID: SystemCategory.cafe.id)

// Изменение суммы и удаление.
var draft = ExpenseDraft(amount: expense.amount, categoryID: expense.categoryID, date: expense.date, comment: expense.comment)
draft.amount = try Money(apiString: "199.00")
_ = try await expenses.updateExpense(id: expense.id, draft)
try await expenses.deleteExpense(id: expense.id)

// Архивирование системной категории.
_ = try await categories.archiveCategory(id: SystemCategory.travel.id)
```

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
- Экран проверки запуска временный и будет заменён продуктовым RootView. Сейчас он дополнительно показывает число доступных категорий — признак успешной инициализации хранилища.
- Дата расхода в будущем не запрещена: в контракте E0 такого правила для `expense` нет (аналитика учитывает только `date ≤ сегодня`, план §7.3). Отметка дня в будущем запрещена.
- Название пользовательской категории нормализуется так же, как комментарий (NFC, без Cc, без пробелов по краям), чтобы длина на устройстве и на сервере считалась одинаково.
- Swift 6 language mode включён во всех targets.

## Следующий этап

- Экраны по Figma: список расходов, ввод расхода, выбор и создание категорий, «День без расходов». Ввод суммы с локальным форматом (запятая) — в UI-слое поверх `Money`.
- Импорт выписок: черновик (`importId`, план §6.5) только на устройстве; сохранение операций — через тот же `createExpense` (название операции → `comment`, обрезка `ExpenseCommentRule.truncated`). Модель расходов этого не требует менять.
- SyncEngine (E6): чтение `OutboxMutation` по `sequence`, пачки по 100, `baseVersion` из `serverVersion` и перебазирование после `applied`, применение `record`, pull по курсору, `410 resync_required`. Авторизация (гость, Apple ID, Keychain), политика повторов §8.1.
- Не реализованы на этом этапе: парсинг файлов, черновик импорта, перезапись дней, разархивирование категорий, автоматическое обнаружение дубликатов, массовая смена категории, push/pull и авторизация.
