import 'package:flutter/material.dart';

/// Lightweight localization for the editor UI.
///
/// English strings are used directly as keys in the source code, so any string
/// that is not (yet) translated simply falls back to English. Only the Russian
/// dictionary below needs to be maintained.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  static const AppLocalizations _fallback = AppLocalizations(Locale('en'));

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      _fallback;

  bool get isRussian => locale.languageCode == 'ru';

  /// Translates [key] (an English phrase) to the active language.
  String tr(String key) => isRussian ? (_ru[key] ?? key) : key;

  String _plural(
    int n, {
    required String enOne,
    required String enMany,
    required String ruOne,
    required String ruFew,
    required String ruMany,
  }) {
    if (!isRussian) return n == 1 ? enOne : enMany;
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return ruOne;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return ruFew;
    return ruMany;
  }

  String nodes(int n) =>
      '$n ${isRussian ? _plural(n, enOne: 'node', enMany: 'nodes', ruOne: 'узел', ruFew: 'узла', ruMany: 'узлов') : (n == 1 ? 'node' : 'nodes')}';

  String scenes(int n) =>
      '$n ${isRussian ? _plural(n, enOne: 'scene', enMany: 'scenes', ruOne: 'сцена', ruFew: 'сцены', ruMany: 'сцен') : (n == 1 ? 'scene' : 'scenes')}';

  String issuesFound(int n) => isRussian
      ? 'Найдено проблем: $n'
      : '$n issue${n == 1 ? '' : 's'} found';

  String selected(String name) =>
      isRussian ? 'Выбрано: $name' : 'Selected: $name';

  String canvasSize(int width, int height) =>
      isRussian ? 'Холст $width×$height' : 'Canvas $width×$height';

  String deleteProject(String name) =>
      isRussian ? 'Удалить «$name» и все его сцены?' : 'Delete "$name" and all its scenes?';

  String deleteScene(String name) =>
      isRussian ? 'Удалить «$name.fxml»?' : 'Delete "$name.fxml"?';

  String fileLabel(String path) => isRussian ? 'Файл: $path' : 'File: $path';

  /// "Owner: ivanov@mail.ru" / "Владелец: ivanov@mail.ru".
  String owner(String? email) => isRussian
      ? 'Владелец: ${email ?? 'гость'}'
      : 'Owner: ${email ?? 'guest'}';

  /// Caption of the owner field in the project settings.
  String get ownerLabel => isRussian ? 'Владелец' : 'Owner';

  /// "Projects 1–12 of 37" / "Проекты 1–12 из 37".
  String projectPageRange(int from, int to, int total) => isRussian
      ? 'Проекты $from–$to из $total'
      : 'Projects $from–$to of $total';

  String couldNotOpenLink(String title) => isRussian
      ? 'Не удалось открыть ссылку для «$title».'
      : 'Could not open the download link for $title.';

  static const Map<String, String> _ru = <String, String>{
    // ------------------------------------------------------------------ login
    'Sign in to store your projects in the cloud.':
        'Войдите, чтобы хранить проекты в облаке.',
    'Sign in': 'Войти',
    'Create account': 'Создать аккаунт',
    'Email': 'Эл. почта',
    'Password': 'Пароль',
    'Confirm password': 'Подтвердите пароль',
    'Enter a valid email address.':
        'Введите корректный адрес эл. почты.',
    'Password must be at least 6 characters.':
        'Пароль должен содержать не менее 6 символов.',
    'Passwords do not match.': 'Пароли не совпадают.',

    // --------------------------------------------------------------- account
    'Account': 'Аккаунт',
    'Signed in': 'Вы вошли',
    'Download client': 'Скачать клиент',
    'Sign out': 'Выйти',
    'Projects': 'Проекты',
    'Components': 'Компоненты',
    'Drag to resize. Double click to fit the content.':'Потяните, чтобы изменить размер. Двойной щелчок — по содержимому.',
    'Project': 'Проект',
    'Run preview': 'Запустить превью',
    'Browser preview of the current scene': 'Превью текущей сцены в браузере',
    'Refresh preview': 'Обновить превью',
    'Close preview': 'Закрыть превью',
    'Live document': 'Текущий документ',
    'Outline': 'Структура',
    'Inspector': 'Свойства',
    'Loading…': 'Загрузка…',
    'Language': 'Язык',
    'Settings': 'Настройки',
    // ------------------------------------------------------------- профиль
    'Profile': 'Профиль',
    'Login': 'Логин',
    'Choose picture': 'Выбрать фото',
    'Remove picture': 'Удалить фото',
    'PNG or JPEG, up to 400 KB.': 'PNG или JPEG, до 400 КБ.',
    'Current password': 'Текущий пароль',
    'New password': 'Новый пароль',
    'Change password': 'Сменить пароль',
    'Login updated.': 'Логин обновлён.',
    'Password changed.': 'Пароль изменён.',
    'Picture updated.': 'Аватар обновлён.',
    'Picture removed.': 'Аватар удалён.',
    'The login is unchanged.': 'Логин не изменился.',
    'The picture is too large.': 'Картинка слишком большая.',
    'The picture could not be read.': 'Не удалось прочитать картинку.',
    'Current password is incorrect.': 'Текущий пароль указан неверно.',
    'Could not change the login.': 'Не удалось изменить логин.',
    'Could not change the password.': 'Не удалось изменить пароль.',
    'Could not upload the picture.': 'Не удалось загрузить аватар.',
    'Could not remove the picture.': 'Не удалось удалить аватар.',
    'You are not signed in.': 'Вы не авторизованы.',
    'Server error.': 'Ошибка сервера.',
    'Authentication failed.': 'Ошибка авторизации.',
    'Theme': 'Тема',
    'Theme of the editor interface.': 'Тема оформления редактора.',
    'System default': 'Как в системе',
    'Light': 'Светлая',
    'Dark': 'Тёмная',
    'Interface language': 'Язык интерфейса',
    'Language of the editor interface.':
        'Язык интерфейса редактора.',
    'Could not open the selected file.':
        'Не удалось открыть выбранный файл.',
    'Document saved.': 'Документ сохранён.',
    'Save cancelled.': 'Сохранение отменено.',

    // ---------------------------------------------------------------- toolbar
    'New document': 'Новый документ',
    'Open FXML…': 'Открыть FXML…',
    'Save FXML': 'Сохранить FXML',
    'Save document': 'Сохранить документ',
    'Download FXML…': 'Скачать FXML…',
    'Undo (Ctrl+Z)': 'Отменить (Ctrl+Z)',
    'Redo (Ctrl+Y)': 'Вернуть (Ctrl+Y)',
    'Toggle grid': 'Сетка',
    'Zoom out': 'Уменьшить',
    'Zoom in': 'Увеличить',
    'More': 'Ещё',
    'Load example': 'Пример',
    'View / edit FXML': 'Просмотр/правка FXML',

    // ------------------------------------------------------------- status bar
    'Unsaved changes': 'Не сохранено',
    'Saved': 'Сохранено',
    'Preview': 'Просмотр',

    // -------------------------------------------------------------- palette
    'Search components': 'Поиск компонентов',
    'Layout': 'Разметка',
    'Controls': 'Элементы управления',
    'Shapes': 'Фигуры',
    'Text': 'Текст',
    'Menus': 'Меню',
    'Charts': 'Диаграммы',
    'Misc': 'Разное',

    // ------------------------------------------------------------- projects
    'New project': 'Новый проект',
    'Import project': 'Импорт проекта',
    'No projects yet': 'Пока нет проектов',
    'Create a JavaFX application to start building. Projects (FXML scenes and generated Java sources) are saved automatically on this device.':
        'Создайте JavaFX-приложение, чтобы начать. Проекты (FXML-сцены и сгенерированный Java-код) сохраняются автоматически на этом устройстве.',
    'Back to projects': 'К списку проектов',
    'New scene': 'Новая сцена',
    'Rename project': 'Переименовать проект',
    'Export project': 'Экспорт проекта',
    'Delete project': 'Удалить проект',
    'Rename': 'Переименовать',
    'Duplicate': 'Дублировать',
    'Export': 'Экспорт',
    'Delete': 'Удалить',
    'Open': 'Открыть',
    'Project imported.': 'Проект импортирован.',
    'Import failed.': 'Не удалось импортировать проект.',
    'Project exported.': 'Проект экспортирован.',
    'Export failed.': 'Не удалось экспортировать проект.',
    'Archive format': 'Формат архива',
    'Build tool': 'Сборочная система',
    'Build files added to the archive root.':
        'Файлы сборки добавляются в корень архива.',
    'None': 'Нет',
    'Only sources and scenes': 'Только исходники и сцены',
    'generated on export': 'создаётся при экспорте',
    'Include Java sources': 'Включить Java-исходники',
    'Build': 'Собрать',
    'Build project': 'Собрать проект',
    'Build finished.': 'Сборка завершена.',
    'Build failed.': 'Сборка не удалась.',
    'Download ready JAR': 'Скачать готовый JAR',
    'Artifact': 'Артефакт',
    'app.jar — needs JavaFX on the classpath':
        'app.jar — нужен JavaFX в classpath',
    'JAR + JavaFX runtime + run scripts for Windows, Linux and macOS':
        'JAR + среда JavaFX + скрипты запуска для Windows, Linux и macOS',
    'The project is compiled on the build server.':
        'Проект компилируется на сервере сборки.',
    'The project will be compiled on the build server and a ready-to-run JAR will be downloaded.':
        'Проект будет скомпилирован на сервере сборки, и вы сможете скачать готовый JAR.',
    'Compiling…': 'Компиляция…',
    'Build analysis': 'Анализ сборки',
    'Score': 'Оценка',
    'Build time': 'Время сборки',
    'Issues found': 'Найденные проблемы',
    'Recommendations': 'Рекомендации',
    'No issues found. The project looks healthy.': 'Проблем не обнаружено. Проект выглядит здоровым.',
    'Add the generated Java files to the archive.':
        'Добавить сгенерированные Java-файлы в архив.',
    'Kiosk mode': 'Режим киоска',
    'Start full-screen without a title bar. ESC is disabled.':
        'Запуск на весь экран без заголовка. ESC отключён.',
    // ---- Export check / build analysis report ----
    'Export check': 'Проверка экспорта',
    'Export anyway': 'Всё равно экспортировать',
    'Fix issues': 'Исправить',
    'No scenes in the project.': 'В проекте нет сцен.',
    'Add at least one scene to the project.':
        'Добавьте в проект хотя бы одну сцену.',
    'Java package is invalid.': 'Некорректный Java-пакет.',
    'Fix the Java package in project settings (letters, digits, underscores, dots).':
        'Исправьте Java-пакет в настройках проекта (буквы, цифры, подчёркивания, точки).',
    'Main class is not set.': 'Не задан главный класс.',
    'Set the main class in project settings.':
        'Задайте главный класс в настройках проекта.',
    'Project description is empty.': 'Описание проекта пустое.',
    'Add a description — it will appear in the exported README.':
        'Добавьте описание — оно попадёт в экспортируемый README.',
    'Check the build log in the history window.':
        'Посмотрите журнал сборки в окне истории.',
    'Build took more than 10 seconds.': 'Сборка заняла более 10 секунд.',
    'Consider simplifying the project or scenes.':
        'Упростите проект или сцены.',
    'The controller package must match the project package "{0}". Update the scene controllers or the package in the settings.':
        'Пакет контроллера должен совпадать с пакетом проекта «{0}». Обновите контроллеры сцен или пакет в настройках.',
    'Scene "{0}": the FXML refers to the controller "{1}", but the project package is "{2}". The application will not start.':
        'Сцена «{0}»: FXML ссылается на контроллер «{1}», а пакет проекта — «{2}». Приложение не запустится.',
    'Scene "{0}": the FXML controller "{1}" differs from the scene controller "{2}".':
        'Сцена «{0}»: контроллер в FXML «{1}» отличается от контроллера сцены «{2}».',
    'Scene "{0}": the FXML refers to a controller, but the scene has no controller class.':
        'Сцена «{0}»: FXML ссылается на контроллер, но у сцены нет класса контроллера.',
    'Scene "{0}": the controller "{1}" lies outside the project package "{2}".':
        'Сцена «{0}»: контроллер «{1}» находится вне пакета проекта «{2}».',
    'Scene "{0}": the element "{1}" is used, but the import "{2}" is missing. The application will not start.':
        'Сцена «{0}»: используется элемент «{1}», но импорт «{2}» отсутствует. Приложение не запустится.',
    'Every element used in a scene needs its own <?import?> line in the FXML file. The automatic fix adds the missing imports.':
        'Каждый элемент сцены должен иметь строку <?import?> в файле FXML. Автоисправление добавит недостающие импорты.',
    'Scene actions': 'Действия со сценой',
    'Project files': 'Файлы проекта',
    'Project actions': 'Действия с проектом',
    'Project settings': 'Настройки проекта',
    'Participants': 'Участники',
    'Shared mode': 'Совместный режим',
    'Editor': 'Редактор',
    'Viewer': 'Наблюдатель',
    'Email of the participant': 'Почта участника',
    'Participant': 'Участник',
    'Rights': 'Права',
    'Invite by link': 'Пригласить по ссылке',
    'Release notes': 'Заметки о версии',
    'What has changed in this version?': 'Что изменилось в этой версии?',
    'Previous builds': 'Предыдущие сборки',
    'Reading the history…': 'Читаем историю…',
    'History': 'История',
    'No notes': 'Без заметок',
    'The project has no versions yet: build it to release the first one.':
        'У проекта ещё нет версий: соберите его, чтобы выпустить первую.',
    'The first version of the project': 'Первая версия проекта',
    'Version {0} will be released (the last one was {1})':
        'Выпускается версия {0} (предыдущая — {1})',
    'Version {0} is already released': 'Версия {0} уже выпущена',
    'Date': 'Дата',
    'Author': 'Автор',
    'Scenes': 'Сцены',
    'Notes': 'Заметки',
    'Changes compared to the previous version:': 'Изменения по сравнению с предыдущей версией:',
    'Added scenes:': 'Добавленные сцены:',
    'Removed scenes:': 'Удалённые сцены:',
    'This is the first version of the project.': 'Это первая версия проекта.',
    'Invitation link': 'Ссылка для приглашения',
    'Invitation': 'Приглашение',
    'Join the project': 'Присоединиться',
    'Later': 'Позже',
    'Copied': 'Скопировано',
    'You have joined the project.': 'Вы присоединились к проекту.',
    'Could not join the project.': 'Не удалось присоединиться к проекту.',
    'Send the link to the person: they join the project when they open it.':
        'Отправьте ссылку человеку: он присоединится к проекту, когда её откроет.',
    'You are invited to the project "{0}" of {1}. Do you want to join it?':
        'Вас пригласили в проект «{0}» ({1}). Присоединиться?',
    'Pick an account or type an email':
        'Выберите аккаунт или введите почту',
    'Add participant': 'Добавить участника',
    'Remove participant': 'Убрать участника',
    'Publish for the participants': 'Опубликовать для участников',
    'The participant has been added.': 'Участник добавлен.',
    'The participant has been removed.': 'Участник удалён.',
    'The project has been published for the participants.':
        'Проект опубликован для участников.',
    'Enter the email of the participant.':
        'Введите почту участника.',
    'Nobody has been invited yet. Add a participant to work on the project together.':
        'Участники ещё не приглашены. Добавьте участника для совместной работы над проектом.',
    'Open project': 'Открыть проект',
    'Actions': 'Действия',
    'Project renamed.': 'Проект переименован.',
    'Project duplicated.': 'Проект продублирован.',
    'Project name is empty.': 'Название проекта не может быть пустым.',
    'Description': 'Описание',
    'Description saved.': 'Описание сохранено.',
    'Project updated.': 'Проект обновлён.',
    'Shown in the README of the export.':
        'Показывается в README при экспорте.',
    'Previous page': 'Предыдущая страница',
    'Next page': 'Следующая страница',
    'Choose a project': 'Выберите проект',
    'Create your first JavaFX application to start building scenes and generating Java sources.':
        'Создайте первое JavaFX-приложение, чтобы начать строить сцены и генерировать Java-код.',
    'Open an existing project or start a new one.':
        'Откройте существующий проект или создайте новый.',

    // ------------------------------------------------------------- dialogs
    'New JavaFX project': 'Новый проект JavaFX',
    'Project name': 'Название проекта',
    'Java package': 'Java-пакет',
    'Main class': 'Главный класс',
    'Invalid Java package': 'Недопустимый Java-пакет',
    'Package cannot be empty.': 'Пакет не может быть пустым.',
    'Package must not start or end with a dot.': 'Пакет не может начинаться или заканчиваться точкой.',
    'Package must not contain consecutive dots.': 'Пакет не может содержать две точки подряд.',
    'Package must not contain spaces.': 'Пакет не может содержать пробелы.',
    'Each package segment must not be empty.': 'Каждый сегмент пакета не может быть пустым.',
    'Each segment must start with a letter and contain only letters, digits and underscores.': 'Каждый сегмент должен начинаться с буквы и содержать только буквы, цифры и знаки подчёркивания.',
    'Segment cannot be a Java keyword.': 'Сегмент не может быть зарезервированным словом Java.',
    'Owner': 'Владелец',
    'You are the owner of this project.': 'Вы являетесь владельцем этого проекта.',
    'Transfer ownership': 'Передать право владения',
    'New owner': 'Новый владелец',
    'Transfer': 'Передать',
    'Only the project owner can transfer ownership.': 'Только владелец проекта может передать право владения.',
    'The new owner must be a participant of the project.': 'Новый владелец должен быть участником проекта.',
    'Ownership transferred to {0}.': 'Право владения передано {0}.',
    'Failed to transfer ownership.': 'Не удалось передать право владения.',
    'The project belongs to {0}.': 'Проект принадлежит {0}.',
    'No participants available to transfer ownership to.': 'Нет участников, которым можно передать право владения.',
    'Select the new owner:': 'Выберите нового владельца:',
    'Used for the generated Java sources.': 'Используется для сгенерированных исходников Java.',
    'Description (optional)': 'Описание (необязательно)',
    'Cancel': 'Отмена',
    'Create': 'Создать',
    'Rename scene': 'Переименовать сцену',
    'Delete scene': 'Удалить сцену',
    'Close': 'Закрыть',
    'OK': 'ОК',

    // ------------------------------------------------------------ code editor
    'Back to canvas': 'К холсту',
    'Reload': 'Перезагрузить',
    'Copy': 'Копировать',
    'Fix with AI': 'Исправить с помощью ИИ',
    'Apply': 'Применить',
    'Source copied to clipboard.': 'Исходник скопирован в буфер обмена.',
    'AI suggestion loaded. Review and Apply.':
        'Предложение ИИ загружено. Проверьте и нажмите «Применить».',
    'No issues found.': 'Ошибок нет.',
    'Cannot apply invalid source.':
        'Нельзя применить некорректный исходник.',
    'Java source applied.': 'Java-код применён.',
    'FXML applied.': 'FXML применён.',
    'Invalid FXML — not applied.': 'Некорректный FXML — не применён.',
    'Canvas': 'Холст',
    'Code': 'Код',

    // ---------------------------------------------------------------- ai fix
    'Model:': 'Модель:',
    'Extra instruction (optional)': 'Доп. инструкция (необязательно)',
    'Asking the local model…': 'Запрос к локальной модели…',
    'The corrected source will appear here.':
        'Здесь появится исправленный исходник.',
    'Fix': 'Исправить',
    'Apply to editor': 'Применить в редакторе',
    'Loading models…': 'Загрузка моделей…',
    'No models found. Is Ollama running?':
        'Модели не найдены. Запущена ли Ollama?',
    'AI result copied to clipboard.':
        'Результат ИИ скопирован в буфер обмена.',

    // ------------------------------------------------------------- downloads
    'Download': 'Скачать',
    'Soon': 'Скоро',
    'Ready-made builds are served from the downloads/ folder. Unavailable platforms are marked “Soon”.':
        'Готовые сборки раздаются из папки downloads/. Недоступные платформы помечены как «Скоро».',
    'Desktop': 'Десктоп',
    'Mobile': 'Мобильные',
    'Portable client for Windows 10/11 (x64)':
        'Портативный клиент для Windows 10/11 (x64)',
    'Build for Apple Silicon and Intel': 'Сборка для Apple Silicon и Intel',
    'Build for Linux (x64, tar.gz)': 'Сборка для Linux (x64, tar.gz)',
    'APK for phones and tablets': 'APK для телефонов и планшетов',
    'Build for iPhone and iPad (signed)':
        'Сборка для iPhone и iPad (с подписью)',

    // -------------------------------------------------------- color picker
    'Choose color': 'Выбор цвета',
    'Hex value': 'HEX-значение',

    // ------------------------------------------------------------ inspector
    'Select an element on the canvas to edit its properties.':
        'Выберите элемент на холсте, чтобы редактировать его свойства.',
    'no fx:id': 'без fx:id',
    'Move up': 'Вверх',
    'Move down': 'Вниз',
    'Font': 'Шрифт',
    'size': 'размер',
    'family': 'семейство',
    'Padding': 'Отступы',
    'All attributes': 'Все атрибуты',
    'name': 'имя',
    'package': 'пакет',
    'main class': 'главный класс',
    'Project updated': 'Проект обновлён',
    'value': 'значение',
    'Add attribute': 'Добавить атрибут',
    'Remove': 'Удалить',
    'Node': 'Узел',
    'Transform': 'Трансформация',
    'Content': 'Содержимое',
    'Behaviour': 'Поведение',
    'Value': 'Значение',
    'Geometry': 'Геометрия',
    'Appearance': 'Внешний вид',
    'Anchors': 'Привязки',
    'Constraints': 'Ограничения',
    'Grid': 'Сетка',
    'Properties': 'Свойства',
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'ru';

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Convenient access from any widget: `context.tr('Sign in')`.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  String tr(String key) => AppLocalizations.of(this).tr(key);
}
