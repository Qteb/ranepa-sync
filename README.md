# Удалённый конфиг приложения

Приложение раз в сутки читает `config.json` из этой ветки:

- `https://raw.githubusercontent.com/Qteb/ranepa-sync/config/config.json`
- `https://cdn.jsdelivr.net/gh/Qteb/ranepa-sync@config/config.json` (запасной)

| Поле | По умолчанию | Что делает |
|---|---|---|
| `sync` | `true` | `false` — приложение не обращается к ЛК, показывает сохранённое расписание |
| `minIntervalHours` | `4` | Минимальный интервал между фоновыми обновлениями |
| `manualCooldownMinutes` | `2` | Ручное обновление чаще этого не делает запросов |
| `message` | `null` | Текст, который видит пользователь при попытке обновить, когда `sync: false` |

После коммита GitHub Action сбрасывает кэш jsDelivr. Изменения доходят до
приложений в течение суток: настолько часто они перечитывают конфиг.
