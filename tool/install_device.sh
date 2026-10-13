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

# Flutter может быть не в PATH (например, при запуске из другого терминала).
if ! command -v flutter >/dev/null; then
  export PATH="$HOME/development/flutter/bin:$PATH"
fi

device="${1:-}"
if [[ -z "$device" ]]; then
  device=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/connected/ && /iPhone/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F-]{36}$/) { print $i; exit } }')
fi
if [[ -z "$device" ]]; then
  echo "iPhone не найден. Подключи кабелем, разблокируй и нажми «Доверять»." >&2
  exit 1
fi

flutter build ios --release --config-only --dart-define=TEST_TOOLS=true
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/device \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  build -quiet
app=build/device/Build/Products/Release-iphoneos/Runner.app
xcrun devicectl device install app --device "$device" "$app" >/dev/null
if xcrun devicectl device process launch --device "$device" com.qteb.ranepaTimetable >/dev/null 2>&1; then
  echo "Установлено и запущено. Отладка — в аккаунте, внизу."
else
  echo "Установлено. Телефон заблокирован — открой «Расписание» сам. Отладка — в аккаунте, внизу."
fi
