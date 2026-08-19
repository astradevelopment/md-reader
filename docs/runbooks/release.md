# Выпуск версии

От правки в коде до того, что у пользователей появится предложение обновиться.

## 1. Поднять версию

`Resources/Info.plist`, **оба** поля:

```xml
<key>CFBundleVersion</key>            <!-- целое, +1 -->
<string>29</string>
<key>CFBundleShortVersionString</key> <!-- то, что видит человек -->
<string>1.5.5</string>
```

`CFBundleShortVersionString` — это то, что приложение сравнивает с полем
`version` из фида. Если не поднять, обновление не предложится никому.

Нумерация: третья цифра — исправление, вторая — новая возможность.

## 2. Собрать

```bash
./build.sh release && ./make-dmg.sh
```

Проверить, что в бандл попала нужная версия:

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "MD Reader.app/Contents/Info.plist"
```

## 3. Опубликовать

```bash
V=1.5.5
scp "MD Reader.dmg" dmind:~/md-reader-updates/MD-Reader-$V.dmg
ssh dmind "chmod 644 ~/md-reader-updates/MD-Reader-$V.dmg"

ssh dmind "cat > ~/md-reader-updates/appcast.json" <<JSON
{
  "version": "$V",
  "url": "https://md.dmind.pro/MD-Reader-$V.dmg",
  "notes": "Что изменилось, одной строкой."
}
JSON

ssh dmind "cd ~/md-reader-updates && ln -sfn MD-Reader-$V.dmg md-reader.dmg && ln -sfn MD-Reader-$V.dmg latest.dmg"
```

Старые образы не удалять: `md-reader.dmg` — символическая ссылка, а прежние версии
остаются доступны по прямым адресам. `latest.dmg` ведёт туда же и сохранён на
случай, если старая ссылка кому-то уже отдана.

## 4. Проверить снаружи

Изнутри сервера проверять бесполезно — он резолвит себя сам. Нужна другая машина:

```bash
ssh praxius 'curl -s https://md.dmind.pro/appcast.json'
ssh praxius 'curl -sL -o /tmp/l.dmg https://md.dmind.pro/md-reader.dmg && sha256sum /tmp/l.dmg'
shasum -a 256 "MD Reader.dmg"
```

Контрольные суммы должны совпасть. Если пересобирали образ после загрузки — они
разойдутся: `hdiutil` не даёт побайтово воспроизводимый результат, и на сервере
окажется другая сборка той же версии. Тогда перезалить.

## 5. Закоммитить

Код, документация и поднятая версия — одним коммитом.

## Чего не делать

**Не обновлять копию пользователя руками.** Она живёт в `/Applications` и
обновляется сама — в этом весь смысл. Рабочая сборка в папке проекта отдельная;
ассоциация `.md` заведена на `/Applications`, поэтому пересборки её не касаются.

Проверить, что разделение цело:

```bash
swift -e 'import AppKit; import UniformTypeIdentifiers
if let t = UTType("net.daringfireball.markdown"),
   let u = NSWorkspace.shared.urlForApplication(toOpen: t) { print(u.path) }'
```

Должно печатать `/Applications/MD Reader.app`.

## Как это выглядит у пользователя

При запуске, не чаще раза в сутки, приложение читает фид. Если версия там выше —
показывает окно «Доступна версия…» с кнопками «Обновить и перезапустить»,
«Позже», «Пропустить эту версию». По первой кнопке образ скачивается, приложение
подменяет себя и перезапускается.

Вручную — «Проверить обновления…» в меню приложения, там же ограничение по суткам
не действует.

Отметка последней проверки лежит в `UserDefaults` приложения под ключом
`update.lastCheckedAt`, пропущенная версия — `update.skippedVersion`. Тестовые
прогоны делят настройки с пользователем (идентификатор бандла один), поэтому
вокруг них состояние надо снимать и возвращать:

```bash
defaults export com.denis.mdreader /tmp/snapshot.plist
# ... прогон ...
defaults import com.denis.mdreader /tmp/snapshot.plist
```

## Первая установка на чужом Mac

Gatekeeper не пустит ad-hoc подпись. Один раз:

```bash
xattr -dr com.apple.quarantine "/Applications/MD Reader.app"
```

Дальше обновления ставятся сами: образ, скачанный самим приложением, карантином
не помечается. Подробнее — `docs/adr/0003-ad-hoc-signing.md`.
