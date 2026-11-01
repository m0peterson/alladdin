# T18: свежие кадры и проверки

2026-11-01, база `89ad5d5`, code commit `3914c7e`.
Godot 4.7.2 stable official `ed1daf0bf`, Compatibility, Mesa 25.0.7 llvmpipe,
OpenGL 4.5. Рабочий каталог `/workspace/alladdin/work/t18`.
Повторно полученные доказательства; ничего из потерянной среды не переиспользуется.

Восемь PNG — необработанный viewport настоящей `game.tscn`, 320×180.
Все просмотрены `view_image`; изображения не перерисовывались и не редактировались.

| Этап | Статус | Лог |
| --- | --- | --- |
| Импорт ресурсов | PASS exit 0, без script/resource errors | [import.log](import.log) |
| Проверка запуска/настроек | PASS exit 0 | [checks.log](checks.log) |
| T02–T14 | PASS exit 0 | [tests.log](tests.log) |
| Пять атласов/60 опорных стоп | PASS exit 0 | [visual-contract.log](visual-contract.log) |
| Настоящая интеграция T05–T10 | PASS exit 0 | [render.log](render.log) |
| Настоящая интеграция T11–T14 | PASS exit 0, скрытный/замеченный маршруты | [stealth-render.log](stealth-render.log) |
| Графическая проверка T18 | PASS exit 0, Y-sort/направления/поиск/возврат | [visual-render.log](visual-render.log) |
| Повторная генерация | PASS, SHA-256 всех PNG до/после одинаковы | `python3 tools/generate_characters.py` |

Точные команды из корня worktree:

```sh
export GODOT_BIN=/workspace/alladdin/.tools/godot/4.7.2/Godot_v4.7.2-stable_linux.x86_64
python3 tools/generate_characters.py
timeout 60s ./tools/godot.sh --headless --audio-driver Dummy --path . --import
./tools/check.sh
./tools/test.sh
timeout 60s ./tools/godot.sh --headless --audio-driver Dummy --script res://tests/check_visual.gd
```

Отдельный Xorg использует уже установленную конфигурацию и dummy-драйвер:

```sh
Xorg :118 -config /etc/X11/xorg.conf -noreset -nolisten tcp \
  -logfile /workspace/alladdin/work/t18/work/Xorg.118.log
```

Существующая конфигурация: Driver `dummy`, Depth 24, Modes `1364x1024_60.00`,
Virtual `1364 1364`; отдельный XAUTHORITY не задавался. Ничего не устанавливалось,
Docker/сеть не требовались. Xorg сначала сообщает `_XSERVTransmkdir: ERROR:
euid != 0` при попытке создать каталог `/tmp/.X11-unix`, затем успешно работает.
В renderer-логах есть предупреждение о невозможности сменить V-Sync;
OpenGL и все три сценария успешны. Все renderer-команды включают Dummy audio.

```sh
DISPLAY=:118 LIBGL_ALWAYS_SOFTWARE=1 timeout 60s ./tools/godot.sh \
  --audio-driver Dummy --fixed-fps 60 --script res://tests/check_t05_t10.gd \
  -- --capture-review > artifacts/t15-t19/t18/render.log 2>&1
DISPLAY=:118 LIBGL_ALWAYS_SOFTWARE=1 timeout 90s ./tools/godot.sh \
  --audio-driver Dummy --fixed-fps 60 --script res://tests/check_t11_t14.gd \
  -- --capture-review > artifacts/t15-t19/t18/stealth-render.log 2>&1
DISPLAY=:118 LIBGL_ALWAYS_SOFTWARE=1 timeout 60s ./tools/godot.sh \
  --audio-driver Dummy --fixed-fps 60 --script res://tests/check_visual.gd \
  -- --capture-review > artifacts/t15-t19/t18/visual-render.log 2>&1
```

Скопированы без изменения PNG:

- `.godot/t05-t10-review/`: `inventory`, `player-attack`, `bandit-windup`;
- `.godot/t11-t14-review/`: `witness-alarm`;
- `.godot/t18-review/`: `stall-behind`, `stall-front`, `guard-search`, `guard-clear`.

Полные capture-наборы воспроизводятся командами выше и остаются в игнорируемой
`.godot/`. Headless доказывает только логику; изображение подтверждено отдельным
графическим запуском и просмотром. Субъективный бой, экспорт, Windows NOT RUN.
Подробное заключение: [T18_VISUAL.md](../../../docs/reviews/T18_VISUAL.md).
