# Проверка итоговой версии — 20 октября 2026

- Bundle ID `com.isloragames.islora`, схема `Islora`, title `Islora: Modular City`.
- **66 unit-тестов прошли, 0 failures**. Машинный отчёт: `unit-test-result.json`.
- Нормальная скорость: UI-сценарий стройки, работников, первой награды и отмены удаления прошёл.
- Финальные UI-сценарии iPhone/iPad прошли; экспортировано 20 оригинальных PNG. Размеры, уникальность и SHA-256 проверены в screenshots/evidence/files.json.
- QA-прогресс: уровень 9 на обоих устройствах, 11 целей, три класса зданий, шесть участков и три чертежа. Сохранения созданы игровыми действиями; ускорение — только Debug, с разрешения пользователя.
- `xcodebuild archive`, Release, generic iOS, signing disabled: успешно. Info.plist соответствует release.json.
- В Release-бинарнике нет `ISLORA_TEST_TIME_SCALE` / `ISLORA_TEST_SAVE_NAME`; 9 WAV-файлов включены.
- `python3 release/scripts/validate.py`: поля обеих локалей в лимитах, идентификаторы согласованы.
- `git diff --check`: успешно.

Архив неподписан. Регистрация имени/Bundle ID, подписание, TestFlight и App Review ещё не выполнялись. Полный обычный темп всех 19 целей человеком не оценивался. В проекте остаются предупреждения Swift concurrency/AVAudioSession; сборка и перечисленные проверки проходят.
