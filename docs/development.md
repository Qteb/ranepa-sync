# Сборка и разработка

Нужны Xcode 26 и [XcodeGen](https://github.com/yonaskolb/XcodeGen): проект
Xcode собирается из [`app/project.yml`](../app/project.yml).

```bash
cd app
xcodegen generate
open Ranepa.xcodeproj
```

Тесты:

```bash
xcodebuild -project app/Ranepa.xcodeproj -scheme Ranepa -destination "platform=iOS Simulator,name=iPhone 17 Pro" test
```

В отладочной сборке на экране аккаунта есть раздел «Отладка»: запуск фонового
обновления и имитация изменения в расписании. В релизную сборку он не попадает.

## Демо-режим и скриншоты

Долгое нажатие на логотип на стартовом экране открывает демо: выдуманная
студентка с расписанием и планом обучения, без входа и без интернета
([`app/Ranepa/Services/Demo.swift`](../app/Ranepa/Services/Demo.swift)). Работают напоминания, виджет, календарь и
«потянуть вниз»: каждое обновление меняет одну аудиторию на завтра, чтобы было
видно уведомление об изменении. «Выйти из демо» на экране аккаунта удаляет всё,
включая календарь, и возвращает к стартовому экрану. Демо есть и в релизной
сборке — для проверки в App Review.

Сегодняшние пары сдвигаются так, чтобы одна из них шла прямо сейчас. Для
одинаковых скриншотов время приложения можно зафиксировать аргументом
запуска:

```bash
xcrun simctl launch booted com.qteb.ranepaTimetable -DEMO_AT 2026-10-13T11:05
```

```bash
xcrun simctl status_bar booted override --time 11:05 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
```

## Тестовая сборка на свой iPhone

```bash
tool/install_device.sh
```

Собирает релизную сборку с разделом «Отладка» в аккаунте и ставит её на
подключённый кабелем iPhone. В «Отладке»: «ускоренный день» (демо, где сегодня
4 пары по 4 минуты, первая — через 3 минуты, напоминания за 1 минуту —
за 20 минут видно напоминания, Live Activity, виджеты и часы), уведомление
об изменении, перезапуск Live Activity, фоновое обновление. Сборка заменяет
версию из TestFlight; вернуться — переустановить из TestFlight.

## Своя сборка для iPhone

Идентификаторы в проекте привязаны к аккаунту разработчика автора. Чтобы собрать
приложение под своим аккаунтом Apple, замени их на свои:

| Что | Где |
|---|---|
| Команда разработчика (`DEVELOPMENT_TEAM`) | [`app/project.yml`](../app/project.yml) |
| Bundle ID `com.qteb.ranepaTimetable` | [`app/project.yml`](../app/project.yml) |
| App Group `group.com.qteb.ranepatimetable` | `*.entitlements` в [`app/`](../app/), [`app/Shared/Lessons.swift`](../app/Shared/Lessons.swift) |
| Фоновая задача `com.qteb.ranepaTimetable.refresh` | [`app/project.yml`](../app/project.yml), [`app/Ranepa/Services/Background.swift`](../app/Ranepa/Services/Background.swift) |

После правки `project.yml` — снова `xcodegen generate`.
