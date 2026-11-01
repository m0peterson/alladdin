# Проверки пакета T15–T19

2026-11-01. База main `89ad5d5` (PR #8). Интеграционный код проверен на
`741dc82`; после этого добавлены отчёты, логи и отдельная визуальная фикстура.
Все доказательства получены заново после пересоздания среды.

Godot `4.7.2.stable.official.ed1daf0bf`, Linux, Compatibility.
T15 и T18 проверены самостоятельно; T16 принят после T15, T17 после T16,
затем проверена общая сцена. T20 вне запроса; T19 остаётся BLOCKED.

| Блок/проверка | Результат | Доказательство |
| --- | --- | --- |
| T15: round-trip, происхождение/ID, malformed, safe write, backup, F5/F9/Continue | PASS | `check_player_save.gd`, [final-tests.log](t19/final-tests.log) |
| T16: контейнеры/лампа/квест/торговцы/тревога/бандит, атомарные отказы | PASS | `check_world_save.gd`, [final-tests.log](t19/final-tests.log); повторный load, финал и граница trail 4096/4097 |
| T17: 360 s, пауза, once-per-day, save/restore, staged refill, no arbitrage | PASS | `check_economy.gd`, [отчёт](../../docs/reviews/T17_ECONOMY.md), [final-tests.log](t19/final-tests.log) |
| T18: роли/направления/ноги/палитра/GUI/состояния/источники | PASS | [визуальный отчёт](../../docs/reviews/T18_VISUAL.md), [кадры и команды](t18/README.md), ресурсный контракт 60 кадров |
| Сквозная game.tscn: E/F/покупка/заказ → F5 → день/мутации → F9 → Continue → финал/reload | PASS | [integration.log](integration.log), `check_t15_t19.gd`, [final-tests.log](t19/final-tests.log) |
| Импорт, запуск, настройки | PASS | [final-check.log](t19/final-check.log), [root check](checks.log) |
| Безопасность: malformed/late-tail, lamp/reward, busy clock, лимиты, backup | PASS для 63 ожиданий | [probe.gd](security/probe.gd), [probe.log](security/probe.log); KNOWN_LOW_S3 — подтверждённое ограничение, не исправление |
| T19 целиком | BLOCKED | Нет T20; [матрица ACCEPTANCE](../../docs/reviews/T19_ACCEPTANCE.md) |

Основные команды:

```sh
./tools/check.sh
./tools/test.sh
timeout 60s ./tools/godot.sh --headless --fixed-fps 60 --script res://artifacts/t15-t19/security/probe.gd
```

Runner проверяет exit code, ошибки Godot и итоговый маркер, ограничивает
сценарии 60 s (T03 — 90 s). Baseline-логи в `t19/` относятся только к T00–T14;
для общего результата используются `final-*`. Тесты записывают отдельные
временные save и не перезаписывают пользовательские файлы.

## Настоящий рендер новых сохранений

Использован уже доступный Xorg dummy `:118` и Mesa llvmpipe. При наличии
такого дисплея повторить:

```sh
DISPLAY=:118 LIBGL_ALWAYS_SOFTWARE=1 timeout 60s ./tools/godot.sh --audio-driver Dummy --fixed-fps 60 --script res://tests/capture_save_ui.gd
```

[Лог](save-render.log): exit 0, OpenGL Compatibility, ошибок нет; предупреждения
V-Sync виртуального дисплея и повторной компиляции shader cache не мешали рендеру.
Все кадры — необработанный viewport настоящей game.tscn, 320×180, просмотрены:

- [Меню](main-menu.png): русское управление сохранениями.
- [F5](save-confirmation.png): полный объём сохранения, непрозрачная панель.
- [Повреждение](save-recovery.png): явная ошибка и отдельная кнопка backup.
- [Восстановление](save-restored.png): результат явного выбора.
- [Следующий день](day-hud.png): HUD дня/времени и существующие подсказки.

NOT RUN: полный ручной десятиминутный проход, субъективное ощущение движения/боя,
power-loss durability, экспорт, Windows. Рендер не заменяет эти проверки.
Известные Low и оценка проекта: [PROJECT_REVIEW.md](../../docs/PROJECT_REVIEW.md).
