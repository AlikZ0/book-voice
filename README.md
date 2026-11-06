# BookVoice — офлайн-озвучивание PDF на iPhone

Нативное iOS-приложение на SwiftUI, PDFKit, Vision и AVFoundation. Не использует облачные сервисы, сервер или сторонние библиотеки.

## Что работает в этой версии

- Импорт PDF из «Файлов» с сохранением локальной копии книги.
- Библиотека книг с обложкой первой страницы и индикатором прогресса.
- Просмотр PDF через PDFKit.
- Системное озвучивание текста (AVSpeechSynthesizer), пауза, продолжение, стоп, переход к соседним страницам.
- Автопереход к следующей странице после завершения чтения предыдущей.
- Выбор голоса и скорости; автоопределение русского, английского и армянского текста.
- Для PDF, состоящего из изображений: попытка локального OCR через Apple Vision с кешированием результата.
- Запоминание последней страницы между запусками.
- Настроенная аудиосессия и background audio для воспроизведения после блокировки экрана.
- Никаких сетевых запросов, аккаунтов, подписок или передачи книг в интернет.

### Ограничения

- PDF с защитой паролем импортировать нельзя.
- Место чтения сохраняется по **странице**, а не по конкретному слову.
- OCR зависит от качества скана и языков, которые поддерживает Vision на установленной версии iOS. Армянский OCR может не поддерживаться или работать неточно.
- Озвучивание зависит от доступности установленного системного голоса выбранного языка. Наличие голоса **hy-AM** на конкретном iPhone не гарантировано.
- Скорость/голос применяются на следующем запуске чтения страницы. На практике системные голоса могут по-разному интерпретировать скорость.
- В некоторых PDF порядок извлечения колонок и сносок определяется текстовым слоем PDF и может быть неправильным.
- Поведение фонового воспроизведения с AVSpeechSynthesizer следует проверить на физическом iPhone: сборка в этом окружении не выполнялась.
- Пока нет EPUB, выделения текущего слова, таймера сна, CarPlay, экспорта MP3 или полноценного управления с экрана блокировки.

## Как собрать с Mac

Нужны Xcode 16.4 и XcodeGen.

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open BookVoice.xcodeproj
```

В Xcode открой настройки target BookVoice → Signing & Capabilities, укажи свой Team и уникальный Bundle Identifier. Затем подключи iPhone и запусти Build/Run.

## Как собрать БЕЗ Mac: GitHub Actions

В архиве есть `.github/workflows/ios.yml`. Он собирает **неподписанный IPA** на macOS-сервере GitHub.

1. Создай пустой репозиторий на GitHub (лучше приватный).
2. Из папки BookVoice на Ubuntu выполни:

```bash
git init
git branch -M main
git add .
git commit -m "Initial BookVoice"
git remote add origin https://github.com/USERNAME/REPOSITORY.git
git push -u origin main
```

3. Открой GitHub → Actions → Build BookVoice for iPhone → Run workflow. Если push на `main` активировал сборку, ручной запуск не нужен.
4. После **успешной** сборки открой её страницу, скачай артефакт `BookVoice-unsigned-IPA` (ZIP с файлом `BookVoice-unsigned.ipa`).
5. Неподписанный IPA **нельзя открыть непосредственно на iPhone**. Его надо подписать и установить (например, через уже настроенный SideStore/AltStore либо используя собственную учётную запись разработчика Apple).

При использовании бесплатной учётной записи Apple установка требует пере-подписи, как правило, раз в 7 дней; также действует лимит одновременно установленных приложений разработчика. Это ограничение Apple, не приложения.

### Системные голоса

Приложение показывает доступные голоса iPhone. Для нужного языка может потребоваться заранее скачать голос в настройках iOS, пока есть интернет. После этого работа с книгами и встроенное чтение рассчитаны на офлайн.

## Структура проекта

```text
BookVoice/
  BookVoiceApp.swift
  Models/Book.swift
  Services/BookLibrary.swift
  Services/BookSpeechPlayer.swift
  Services/PDFTextExtractor.swift
  Services/OCRTextCache.swift
  Views/LibraryView.swift
  Views/ReaderView.swift
  Views/SettingsView.swift
  Assets.xcassets/AppIcon.appiconset/
project.yml
.github/workflows/ios.yml
```

## Конфиденциальность

Исходники не содержат сетевых вызовов, трекеров и API-ключей. Импортированные PDF копируются в папку приложения. Кеш OCR лежит в системном каталоге кешей и может быть очищен iOS. Метаданные библиотеки сохраняются локально в JSON.

## Исправление сборки ReaderView (6 ноября 2026)

При сообщении Xcode `the compiler is unable to type-check this expression in reasonable time` для `BookVoice/Views/ReaderView.swift:16:25` структура `ReaderView` разделена на небольшие computed views и методы (`readerContent`, `documentContent`, `pageHeader`, `pageJumpSheet`, `playerPanel` и др.). Дополнительно указан явный `Color.primary` вместо неявного стиля в обводке и разделителе.

Для обновления существующего GitHub-репозитория достаточно заменить **один файл** `BookVoice/Views/ReaderView.swift` на исправленный и сделать commit в `main`. Изменять настройки Actions или переустанавливать Xcode не требуется. Полноценная сборка iOS из Linux не проверена: Xcode доступен только в macOS.


## Исправление сборки Xcode 16.4: AVSpeechSynthesizerDelegate и ReaderView (6 ноября 2026)

Лог `cannot assign value of type 'BookSpeechPlayer' to type '(any AVSpeechSynthesizerDelegate)?'` исправлен добавлением явного соответствия `AVSpeechSynthesizerDelegate`, а методы делегата помечены ObjC-селекторами.

В логах также `ReaderView.swift:16:25` — признак того, что GitHub собирает **старую версию файла** с большим `body`; в этом архиве `body` начинается на **строке 18** и разделён на подкомпоненты.

**Нужно заменить два файла в репозитории в тех же путях:**

- `BookVoice/Services/BookSpeechPlayer.swift`
- `BookVoice/Views/ReaderView.swift`

Затем выполнить commit/push в ветку `main` и проверить новый run Actions, чтобы он действительно использовал новый commit.

На Linux выполнена синтаксическая проверка Swift-файлов. Полноценная сборка под iOS требует macOS/Xcode и не была подтверждена в этой среде.
