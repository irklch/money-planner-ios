# Money Planner — iOS

Клиент Money Planner: local-first учёт расходов. Этап 1 — основа проекта: структура, дизайн-система, SwiftData, сетевой слой, тесты и CI. Этап 2 — локальное хранение расходов, категорий и отметок дня с подготовкой к sync: данные работают без сети и переживают перезапуск. Этап 3 — главный экран «Обзор» и история расходов по макету Figma: итог за период, полоса распределения по категориям, категории с долями, история по дням и экран категории; всё из локальной БД, без сети. Ввод и правка расходов, импорт, вход, sync, Premium и AI-инсайты — следующие этапы.

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

### Этап 3: сверка с бэкендом и Figma

Бэкенд: `money-planner-backend` `main` на коммите **`012c1ea6f1137f0a7e4e1a01492e977c597b3d53`** (14.10.2026): `docs/production-migration-plan.md` §7.2–7.4 (арифметика и определения аналитики), `docs/architecture-local-first.md` §8, §10.0, `contract/`. Изменений контракта для экранов этого этапа с 36ce86b нет.

| Правило | Источник | Реализация |
|---|---|---|
| Расход в итогах — живой, `amount > 0`; категории — по `categoryId`, включая архивные; неизвестные → «Без категории» | план §7.3 | `ExpenseSummaryCalculator`, `CategoryReference.unknown` |
| Период `[a, b]` включительно; считается прошедшая часть `P* = [a, min(b, сегодня)]` | план §7.3 | `ExpensePeriod.elapsed` |
| Деньги — целые копейки `Int64`; доли — метод наибольшего остатка, сумма ровно 100,0 %, при равных остатках — большая сумма, затем `categoryId`; проценты до 0,1 | план §7.2 | `largestRemainderShares` в десятых долях процента |
| Порядок при равенстве — сумма ↓, затем `categoryId` ↑ | план §7.2 | категории и сегменты полосы |

Figma: файл `q1hu3Mn5HR2E5HKGtkCAZh`, страница «UI — Exploration 01» (`131:2`), секция «FINAL UI · MVP · READY FOR IMPLEMENTATION» (`291:5802`). Использованные узлы: Foundations (токены, `132:67`), D1 «Dashboard — есть данные» `295:5944` и полный скролл `295:6027`, D1s «компактный период в toolbar» `295:6110`, D3 «Выбор периода» `295:6198`, D1 «Период 90 дней» `295:6321`, H9 «Нет расходов за период» `295:6633`, E1x «Все категории — раскрыто» `303:11616`, E4 «Категория — вся история за период» `304:11771`, компоненты Expense Bar `135:54`, Category / Row `134:54`, Category / Emoji `134:17`. Страница «UX Flow — MVP» (`19:2`) — серые wireframes и спецификация переходов, для вёрстки не использовалась.

Решения там, где задача этапа расходится с макетом:
- **История на главном экране.** В макете экрана «все операции» нет, история есть только у категории (E4). По задаче история за период стоит на главном экране сразу под категориями; дни и строки оформлены как в E4. Под комментарием указана категория. Если комментария нет, заголовком строки служит название категории, и пустой строки не остаётся (так же устроена строка в K1).
- **Категории раскрываются на месте.** В D1 строка «Все категории N» ведёт на экран E1. Здесь она раскрывает полный список прямо в карточке, а «Свернуть» возвращает компактный вид: так устроен E1x, только без отдельного экрана.
- **Не реализовано на этом этапе** (в макете есть, относится к следующим этапам): сравнение с прошлым периодом («↑ 12 % к августу», «Что изменилось», «34 % · +4 370 ₽ к августу»), карточка «Учтено N из M дней» (календарь K1), «Как менялись расходы» и мини-график по дням, инсайт и «Все инсайты», «Данные по …», кнопки «Добавить» и «Добавить расходы», настройки (⚙), переход из строки истории к расходу (E5). Пояснение в D3 про сравнение периодов не показывается, остаётся «Под суммой — точные даты».
- **Палитра.** В Figma 17 цветов категорий и отдельный `category/other`, а в контракте `colorIndex` 0–11 (`category_palette_size = 12`). Приоритет у контракта: `CategoryPalette` — это `category/01…12`. Цвет `category/other` достался категории, которой нет на устройстве. «Другое» сохраняет цвет 11 из реестра.

## Структура

```
Configuration/                 xcconfig окружений и Info.plist с ключом MPAPIBaseURL
MoneyPlanner/
  App/                         точка входа, AppBootstrap (открытие БД), AppDependencies (корень композиции), RootView и AppRoute, LedgerFixture (данные previews и UI-тестов)
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
  Features/Expenses/           главный экран, экран категории, ViewModel сводки, форматирование; Components/ — общие части экранов
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
- **Конфигурация, палитра.**
- **Сводка (`ExpenseSummaryCalculator`, `ExpensePeriod`):** пустой период без деления на ноль; точные суммы и доли из одного набора (сумма долей ровно 100,0 %, разбор равенств); включительные границы; архивные и неизвестные категории сохраняют сумму; стабильный порядок при равных суммах; переполнение итога → `MoneyError.overflow`; полоса: объединение категорий < 2 % в «Ещё N», ровно 2 % не объединяется, «Другое» в конце; группировка истории по дням; границы вариантов периода (переход через год, 29 февраля, окна 30/90 дней); смена часового пояса меняет только «сегодня».
- **Сводка из хранилища:** читается только период, удалённые исключены, сводка категории, архивная и отсутствующая на устройстве категории, дата первого расхода для пустого периода; `changeFeed` оповещает после записи и снимает подписку при отмене; методы `LedgerStore` выполняются не на главном потоке.
- **`ExpenseOverviewModel`** (управляемый репозиторий): поздний ответ старого периода не заменяет новый; ошибка чтения → состояние ошибки, повтор загружает; событие изменения данных перечитывает сводку без очистки экрана и без сброса периода, уход с экрана снимает подписку; период, сменённый на другом экране, подхватывается.
- **UI (fixtures `--ui-fixture filled | previousMonthOnly`):** главный экран с расходами; пустой период и выбор другого; смена периода меняет итог и историю; раскрытие категорий на месте; переход в категорию с сохранением периода и возврат; Accessibility XXXL. Скриншоты — во вложениях `TestResults.xcresult`.

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
- Значения токенов взяты из Figma «FINAL UI · MVP», Foundations (`132:67`): цвета — `background/*`, `surface/*`, `text/*`, `accent/primary`, `accent/glow`, `border/separator`, `status/*`, `category/01…12`, `category/other`; роли текста — «iOS / …» на системном SF Pro (Inter на канвасе — прокси); отступы — шкала по 4 pt (поля 16/20, между секциями 28); радиусы — 10/16/24. Итоговая сумма 56 Medium масштабируется через `@ScaledMetric` (`heroAmountStyle()`).
- Содержимое (карточки, строки, полоса, итог) сплошное. Стекло — только системное: toolbar, кнопка «Назад», компактная кнопка периода, sheet. Sheets имеют непрозрачный фон `background/primary` (`presentationBackground`).

Previews: `DesignSystemPreviews.swift` (цвета, палитра, типографика, AX5, иконки и отступы), `ErrorStateView`, `RootView` (с данными, AX3, пустой месяц, без данных), экран ошибки открытия БД.

## Локализация

- Основной язык — русский (`developmentRegion = ru`, `sourceLanguage = ru`). Все строки — в `Resources/Localizable.xcstrings`, включая ошибки, кнопки и accessibility-тексты.
- Ключи семантические: `экран.элемент.смысл` (`home.categories.showAll`, `error.noConnection.title`). Новые ключи добавляются вручную (`extractionState: manual`).
- Доступ — символы, которые генерирует Xcode (`STRING_CATALOG_GENERATE_SYMBOLS = YES`): `Text(.actionRetry)`, `String(localized: .errorNoConnectionTitle)`. Параметры — форматные аргументы ключа: `Text(.homeSpent(range))`. Множественные формы — вариации Plural в каталоге. Строки не склеиваются.
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

Изоляция: target приложения собирается с `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` и Swift 6. UI, ViewModel и репозиторий настроек — на MainActor; сетевой слой, доменные типы и конфигурация явно `nonisolated` и `Sendable`, `URLSessionHTTPClient.send` — `@concurrent`. Расходы, категории и отметки дня — в `actor LedgerStore: ModelActor`. Его методы выполняются на собственной последовательной очереди (`unownedExecutor` → `DispatchSerialQueue`), и там же создаётся и используется его `ModelContext`. Стандартный `DefaultSerialModelExecutor` на iOS 26 фактически выполнял работу актора на главном потоке, даже если контекст был создан вне его. Это показала проверка `Thread.isMainThread`, а тест `storeDoesNotRunOnMainThread` теперь не даёт этому повториться. `@unchecked Sendable` не используется.

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
- **Сводка за период** — `overview(of:categoryID:)` (`ExpenseOverviewProviding`). Читает только неудалённые расходы периода (индекс `dateKey`) и таблицу категорий. Вся история приложения не загружается. Итог, категории, полосу и историю считает `ExpenseSummaryCalculator` на очереди хранилища. Для пустого периода дополнительно читается один расход с наименьшей датой — по нему пустое состояние сообщает «Расходы есть с …».
- **Обновление экранов** — `changeFeed` (`LedgerChangeObserving`). После каждой сохранённой транзакции (расход, категория, отметка дня, а в будущем — применение sync) подписчики получают событие. `ExpenseOverviewModel.run()` подписан, пока экран показан (`.task`), и перечитывает сводку, не очищая экран и не сбрасывая период. Буфер хранит одно событие: серия изменений даёт одно перечитывание. Polling и таймеров нет. При уходе с экрана задача отменяется, вместе с ней снимаются подписка и незавершённая загрузка. При возврате экран перечитывает данные.
- **Устаревшие ответы.** Каждая загрузка получает номер, предыдущая отменяется. Результат применяется, только если номер текущий, поэтому при быстрой смене периода поздний ответ не заменяет актуальный.

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

## Предварительные решения и ограничения

- Base URL Release пустой до создания окружений (E9). Staging подключается через `Local.xcconfig` или значение в `Release.xcconfig`, когда адрес будет утверждён.
- `HealthService` остаётся проверкой сетевого слоя; в интерфейсе этапа 3 сеть не используется, экрана проверки запуска больше нет.
- Дата расхода в будущем не запрещена: в контракте E0 такого правила для `expense` нет. Итоги и история считаются по прошедшей части периода (`date ≤ сегодня`, план §7.3), поэтому расход с будущей датой появится в своём дне. Отметка дня в будущем запрещена.
- Выбранный период живёт, пока работает приложение (`PeriodSelection` в `RootView`), и между запусками не сохраняется. Начальное значение — «Текущий месяц» (Figma D3).
- Подпись капсулы периода: для текущего месяца — его название, для остальных вариантов — «Прошлый месяц», «30 дней», «90 дней» (D1, H9, 02.05). Даты форматируются по локали устройства, сокращения месяцев — тоже («сент.», в макете «сен»).
- Строки истории пока без перехода к расходу (E5 — следующий этап). Строка истории на главном экране открывает расходы своей категории, в том числе архивной и неизвестной.
- Название пользовательской категории нормализуется так же, как комментарий (NFC, без Cc, без пробелов по краям), чтобы длина на устройстве и на сервере считалась одинаково.
- Swift 6 language mode включён во всех targets.

## Следующий этап

- Ввод и правка расхода (M1–M7, E5, E7), выбор и создание категорий, календарь учёта и «День без расходов» (K1). Ввод суммы с локальным форматом (запятая) — в UI-слое поверх `Money`. После сохранения экраны обновятся сами через `changeFeed`.
- Аналитика плана §7: сравнение периодов («Что изменилось», «↑ N % к …»), дорогие дни и динамика (E2), полнота данных («Учтено N из M дней»).
- Импорт выписок: черновик (`importId`, план §6.5) только на устройстве; сохранение операций — через тот же `createExpense` (название операции → `comment`, обрезка `ExpenseCommentRule.truncated`). Модель расходов этого не требует менять.
- SyncEngine (E6): чтение `OutboxMutation` по `sequence`, пачки по 100, `baseVersion` из `serverVersion` и перебазирование после `applied`, применение `record`, pull по курсору, `410 resync_required`. Авторизация (гость, Apple ID, Keychain), политика повторов §8.1.
- Не реализованы на этом этапе: настройки, Premium, AI-инсайты, парсинг файлов, черновик импорта, перезапись дней, разархивирование категорий, автоматическое обнаружение дубликатов, массовая смена категории, push/pull и авторизация.
