#!/usr/bin/env bash
# Тестовая сборка на свой iPhone по кабелю: релизная (запускается без Xcode),
# но с разделом «Отладка» в аккаунте — «ускоренный день», уведомления,
# Live Activity, фоновое обновление.
#
#   tool/install_device.sh            # первый подключённый iPhone
#   tool/install_device.sh <UDID>     # конкретный
#
# Заменяет версию из TestFlight на телефоне, данные приложения остаются.
# Чтобы вернуться на TestFlight, переустанови приложение из TestFlight.
set -euo pipefail
cd "$(dirname "$0")/.."

device="${1:-}"
if [[ -z "$device" ]]; then
  device=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/(connected|available)/ && /iPhone/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F-]{36}$/) { print $i; exit } }')
fi
if [[ -z "$device" ]]; then
  echo "iPhone не найден. Подключи кабелем или по Wi-Fi, разблокируй и нажми «Доверять»." >&2
  exit 1
fi

(cd app && xcodegen generate --quiet)
xcodebuild -project app/Ranepa.xcodeproj -scheme Ranepa -configuration TestTools \
  -destination 'generic/platform=iOS' -derivedDataPath build/device \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  build -quiet
app=build/device/Build/Products/TestTools-iphoneos/Ranepa.app
xcrun devicectl device install app --device "$device" "$app" >/dev/null
if xcrun devicectl device process launch --device "$device" com.qteb.ranepaTimetable >/dev/null 2>&1; then
  echo "Установлено и запущено. Отладка — в аккаунте, внизу."
else
  echo "Установлено. Телефон заблокирован — открой «Расписание» сам. Отладка — в аккаунте, внизу."
fi
