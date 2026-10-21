# Islora — пакет сборки и загрузки

Подготовлено 20 октября 2026. Данные нового аккаунта ожидаются 21 октября.

## Идентификаторы

| Поле | Значение |
|---|---|
| App Store title | Islora: Modular City |
| Имя под иконкой | Islora |
| Новый explicit Bundle ID | com.isloragames.islora |
| Bundle ID тестов | com.isloragames.islora.tests |
| SKU | ISLORA-IOS-001 |
| Версия / первый build | 1.0 / 1 |
| Платформа | iOS, iPhone + iPad, iOS 18.6+ |
| Xcode project / release scheme | Blockora.xcodeproj / Islora |
| Локаль магазина | nl-NL, дополнительно en-US |
| Язык самой игры | English |
| Категория | Games → Simulation |
| Цена | Free; без IAP и подписок |
| Выпуск | Manual, после отдельной отправки на ревью |

Bundle ID уже установлен в Debug/Release проекта и CI, но пока не зарегистрирован у Apple. Доступность названия и идентификатора проверяется в новом аккаунте. Внутренние имена target/Swift-модуля оставлены Blockora, чтобы сохранить импорты тестов; пользователь видит Islora.

## Тексты

`metadata/nl-NL/` и `metadata/en-US/` содержат готовые name, subtitle, description, keywords, promotional_text и release_notes. Для первого релиза поле What's New может не понадобиться. `review_notes.txt` — инструкции для ревьюера, `testflight_description.txt` и `testflight_what_to_test.txt` — бета-тексты.

Тексты не обещают действующий мультиплеер, общий онлайн-прогресс или недоступные с нового сохранения продвинутые здания. Английский интерфейс указан явно. Основная локаль nl-NL сохранена из прежнего пакета; это локаль листинга, а не обещание нидерландского интерфейса.

## Что потребуется от нового аккаунта

- Team ID и доступ для регистрации explicit App ID `com.isloragames.islora`.
- App Store Connect API: `.p8`, Key ID, Issuer ID с доступом к приложению/загрузке.
- Apple Distribution certificate и соответствующий приватный ключ, либо возможность создать их в новом аккаунте. Один `.p8` API-ключ не является сертификатом подписи.
- App Store provisioning profile для этого Bundle ID и сертификата; в Codemagic его нужно загрузить или получить через подключённый аккаунт.
- После создания приложения — числовой Apple ID приложения.
- Актуальные имя/фамилия, email и телефон контакта App Review; владелец copyright. Данные прежнего владельца автоматически не переносятся.
- Сведения владельца для обязательных разделов нового аккаунта (включая статус trader/контакты, если применимо), принятые соглашения Apple.

В `account.env.example` перечислены переменные; настоящих ключей в пакете нет. Новый Codemagic secret group называется `islora_appstore_credentials` и отделён от прежней группы.

## Последовательность завтра

1. Выбрать новый team, зарегистрировать Bundle ID и создать App Store Connect app: iOS, title, SKU, nl-NL.
2. Настроить Apple Distribution certificate и App Store profile для нового team и Bundle ID.
3. В Codemagic добавить API-переменные в `islora_appstore_credentials`; загрузить signing identities нового аккаунта. `ios_signing` выбирает уже настроенные сертификаты/профили, а не создаёт их из трёх publishing-переменных автоматически.
4. Доставить текущие локальные изменения в выбранный Git-репозиторий/ветку, подключённую к Codemagic. В этом пакете push не выполнялся.
5. Запустить workflow `ios-release`. По умолчанию build number = номер CI-запуска + 1; при необходимости задать уникальный `BUILD_NUMBER` вручную. Первая локальная версия имеет номер 1.
6. Workflow подпишет и загрузит IPA в App Store Connect. Автоматическая отправка на App Review и внешнее TestFlight beta review выключена. Пройти обработку build и проверить его через внутренний TestFlight.
7. Заполнить owner/review contact, загрузить локализованные тексты и актуальные скриншоты, указать действующие URL, заполнить privacy/age rating, выбрать build. Отправка на ревью — отдельное действие после устранения блокеров.

## URL и сайт

Используются адреса нового домена: https://isloramodularcity.online, https://isloramodularcity.online/support и https://isloramodularcity.online/privacy. До публичного релиза опубликовать обновлённые страницы и проверить доступность поддержки, корректность контакта и работу формы.

## Privacy / возраст / export

- Игра сохраняет мир на устройстве; вход, реклама, аналитический SDK и ATT отсутствуют. Удалённый игровой API не включён.
- Через встроенный WebView доступен сайт с формой поддержки: Name, Email и Message отправляются на сервер сайта. При заполнении App Privacy учесть этот поток; не выбирать автоматически Data Not Collected. Рабочий вариант декларации: Contact Info → Name/Email и User Content → Customer Support, цель App Functionality, без tracking/advertising. Связь с личностью определить по фактической форме и хранению сообщений. Исключение для добровольной редкой поддержки применимо только при выполнении всех критериев Apple.
- Обязательные ответы age rating заполнить по фактическому функционалу: нет насилия, азартных игр, покупок/loot boxes, медицинских советов, публичного чата или пользовательской ленты. В игре есть переход на сайт и форма поддержки. Итоговый рейтинг вычисляет App Store Connect; старое 4+ не переносится как гарантия. Kids Category не выбиралась.
- Клиент использует системные HTTPS/WKWebView и не содержит собственной криптографии. В Info.plist установлен `ITSAppUsesNonExemptEncryption = NO` для текущего состава приложения; при добавлении собственной криптографии пересмотреть декларацию.
- Запросов камеры, микрофона, геолокации, контактов или photo library нет; не добавлены фиктивные purpose strings.

## Игровая проверка и материалы

В пакете подготовлены 20 новых оригинальных скриншотов: 10 iPhone (1320×2868, 6.9-inch) и 10 iPad (2064×2752, 13-inch). Прогресс получен через XCTest-нажатия и перетаскивания с разрешённым ускорением игровых расчётов; перед снимками скорость возвращена к обычной. На обоих устройствах достигнут level 7, открыты шесть участков, построены три класса зданий, сохранены три чертежа, внесены реальные ресурсы в Skybridge. Старые BLOCKORA-снимки сохранены отдельно в screenshots_legacy_blockora и не входят в новый upload-набор.

Исправлены повторная выдача контрактов, второй техник для Server, ёмкость склада/батареи и несущая способность генератора/сервера, из-за которой они обрушались от собственного веса. 57 unit-тестов проходят; UI-прогон на каждом устройстве прошёл. Оставшиеся ограничения (локальный серверный режим, различия офлайн-расчётов, отсутствие звуковых файлов) описаны в GAME_REVIEW.md. Подписание, проверка на реальном устройстве/TestFlight и обязательные поля нового аккаунта остаются следующими этапами.

## Локальная проверка без ключей

Из корня репозитория:

```sh
python3 release/scripts/validate.py
bash release/scripts/archive-unsigned.sh
```

Архив: `build_out/Islora-final-unsigned.xcarchive`. Это неподписанный device archive для проверки Release-конфигурации; он не является IPA для загрузки и не устанавливается на физический iPhone. После получения team/cert/profile сборку подписать через Codemagic или Xcode. Поля нового аккаунта в `release.json` пока `null`.

## Источники требований

- [Apple: product page fields](https://developer.apple.com/app-store/product-page/)
- [Apple: app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)
- [Apple: privacy disclosures, including WebViews and optional support](https://developer.apple.com/app-store/app-privacy-details/)
- [Codemagic: iOS signing identities](https://docs.codemagic.io/yaml-code-signing/signing-ios/)
- [Codemagic: publishing environment variables](https://docs.codemagic.io/partials/yaml-publishing-app-store-connect-environment-variables/)


## Итог доработки игры

Старая запись о 57 тестах/level 7 выше историческая. Актуально: 66 unit-тестов, оба обновлённых UI-прогона прошли, уровень 9 и 11 целей на скриншотах; Release-архив пересобран. Звуковые ассеты теперь есть; офлайн-расчёты учитывают рецепты, район и события. Полный обычный темп и физическое устройство/TestFlight ещё требуют проверки. См. GAMEPLAY_UPDATE.md и VALIDATION.md.
