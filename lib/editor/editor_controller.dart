import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale, Size;

import 'package:flutter/foundation.dart';

import '../auth/api_client.dart';
import '../build/build_client.dart';
import '../fxml/fxml_parser.dart';
import '../fxml/fxml_serializer.dart';
import '../io/file_service.dart';
import '../io/local_store.dart';
import '../model/fxml_node.dart';
import '../project/java_generator.dart';
import '../project/invite_link.dart';
import '../project/project.dart';
import '../project/project_history.dart';
import '../project/project_exporter.dart';
import '../project/project_storage.dart';
import '../render/fx_renderer.dart';
import 'build_analyzer.dart';
import 'fx_catalog.dart';

enum AuthStatus { loading, signedOut, signedIn }

/// Central application state: the edited document, selection, undo history and
/// view options. The UI listens to this object via [ChangeNotifier].
class EditorController extends ChangeNotifier {
  EditorController({
    FileService? fileService,
    ProjectStorage? storage,
    ApiClient? api,
    KeyValueStore? tokenStore,
    InviteLinks? inviteLinks,
    this.buildClient,
  }) : _fileService = fileService ?? const FileService(),
       _projectStorage = storage ?? createProjectStorage(),
       _api = api ?? HttpApiClient(),
       _tokenStore = tokenStore ?? createKeyValueStore(),
       _inviteLinks = inviteLinks ?? createInviteLinks() {
    _document = FxmlDocument.empty();
    Future.microtask(() async {
      try {
        await _loadLanguage();
      } catch (_) {}
      try {
        await _loadTheme();
      } catch (_) {}
      try {
        await _loadSplit();
      } catch (_) {}
      try {
        await initAuth();
      } catch (_) {}
      try {
        await loadWorkspace();
      } catch (_) {}
    });
  }

  final FileService _fileService;
  final ProjectStorage _projectStorage;
  final ApiClient _api;
  final KeyValueStore _tokenStore;

  /// Reads the invitation links from the address of the page.
  final InviteLinks _inviteLinks;

  /// Optional override of the build service client (used in tests).
  final BuildClient? buildClient;
  static const ProjectExporter _exporter = ProjectExporter();
  static const FxmlParser _parser = FxmlParser();
  static const FxmlSerializer _serializer = FxmlSerializer();

  late FxmlDocument _document;

  // ------------------------------------------------------------------ workspace
  final List<Project> _projects = <Project>[];
  Project? _currentProject;
  SceneFile? _activeScene;
  bool _projectsLoaded = false;
  bool _standaloneOpen = false;
  String _languageCode = 'en';
  Future<void> _persistChain = Future.value();
  int _persistGeneration = 0;
  int _idCounter = 0;

  // ------------------------------------------------------------------------ auth
  AuthStatus _authStatus = AuthStatus.loading;
  bool _authDecided = false;
  bool _authBusy = false;
  String? _authError;
  String? _token;
  String? _userEmail;
  String? _userId;
  String? _avatar;

  List<Project> get projects => List.unmodifiable(_projects);
  Project? get currentProject => _currentProject;
  SceneFile? get activeScene => _activeScene;
  bool get projectsLoaded => _projectsLoaded;

  /// Identifier of the signed-in account; null while nobody is signed in.
  String? get userId => _userId;

  /// Storage scope of the current workspace: the account id, or the guest
  /// scope for work done without a sign-in.
  String get storageScope => _userId ?? guestScope;

  /// True when there is something to edit in the main pane: either an open
  /// project or a loose document opened from disk. When false the editor shows
  /// the project picker instead of an empty canvas.
  bool get hasOpenDocument => _currentProject != null || _standaloneOpen;

  String? get activeControllerClass => _activeScene?.controllerClass;

  AuthStatus get authStatus => _authStatus;
  bool get authBusy => _authBusy;
  String? get authError => _authError;
  String? get userEmail => _userEmail;
  bool get signedIn => _authStatus == AuthStatus.signedIn;
  bool get editorVisible => _authStatus == AuthStatus.signedIn;

  final List<FxmlDocument> _undoStack = <FxmlDocument>[];
  final List<FxmlDocument> _redoStack = <FxmlDocument>[];
  String? _lastEditKey;

  FxmlNode? _selected;
  String? _fileName;
  String? _looseDocument;
  String? _looseDocumentName;
  bool _dirty = false;
  GeneratedFile? _openSource;
  bool _codeMode = false;
  int _codeEpoch = 0;
  double _zoom = 1.0;
  bool _showGrid = true;
  final double _gridSize = 10;

  /// Result of the last project validation. Recomputed on every save, so the
  /// editor shows build problems (missing imports, wrong controllers, invalid
  /// package…) as soon as they appear — not only when exporting.
  BuildReport? _validation;
  // ------------------------------------------------------------------ getters

  FxmlDocument get document => _document;
  FxmlNode get root => _document.root;
  FxmlNode? get selected => _selected;
  String? get fileName => _fileName;
  bool get dirty => _dirty;
  GeneratedFile? get openSource => _openSource;

  /// The up-to-date validation of the open project, or null when no project
  /// is open.
  BuildReport? get validation => _validation;

  /// True when the main pane shows the text editor instead of the canvas.
  bool get codeMode => _codeMode;

  /// Bumped whenever the code editor must reload its text (tab opened, another
  /// file selected); used as part of the editor widget key.
  int get codeEpoch => _codeEpoch;
  double get zoom => _zoom;
  bool get showGrid => _showGrid;
  double get gridSize => _gridSize;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get nodeCount => _document.allNodes.length;

  String get displayTitle {
    if (_codeMode) return codePath;
    final scene = _activeScene;
    final project = _currentProject;
    if (project != null && scene != null) {
      return '${project.name}/${scene.name}.fxml${_dirty ? " •" : ""}';
    }
    if (project != null) return project.name;
    if (!_projectsLoaded) return 'Loading…';
    if (_standaloneOpen) {
      return '${_fileName ?? "Untitled"}.fxml${_dirty ? " •" : ""}';
    }
    return 'Projects';
  }

  /// Repository-style path of the file currently shown by the code editor.
  String get codePath {
    final source = _openSource;
    if (source != null) return source.path;
    final project = _currentProject;
    final scene = _activeScene;
    if (project != null && scene != null) {
      return 'src/main/resources/${JavaGenerator.packageDir(project)}/${scene.name}.fxml';
    }
    return '${_fileName ?? "untitled"}.fxml';
  }

  /// True when the editor shows a generated Java source (read from the tree).
  bool get codeIsJava => _openSource != null;

  /// The current text of the file shown by the code editor. For FXML this is
  /// derived from the live document; for Java it is the (possibly overridden)
  /// generated source.
  String get codeContent => _openSource?.content ?? serialize();

  /// The default canvas size derived from the root node.
  double get canvasWidth =>
      _num(_document.root.attributes['prefWidth']) ??
      _num(_document.root.attributes['width']) ??
      800;

  double get canvasHeight =>
      _num(_document.root.attributes['prefHeight']) ??
      _num(_document.root.attributes['height']) ??
      600;

  FxRenderContext buildRenderContext() => FxRenderContext(
    selected: _selected,
    zoom: _zoom,
    showGrid: _showGrid,
    gridSize: _gridSize,
    canvasSize: Size(canvasWidth, canvasHeight),
    onSelect: select,
    onBeginEdit: onBeginEdit,
    onModelChanged: onModelChanged,
  );

  double? _num(String? value) => value == null ? null : double.tryParse(value);

  // ---------------------------------------------------------------- selection

  void select(FxmlNode? node) {
    if (identical(node, _selected)) return;
    _selected = node;
    _endEditChain();
    notifyListeners();
  }

  // ------------------------------------------------------------------ history

  void onBeginEdit() {
    _pushUndo();
    notifyListeners();
  }

  /// Coalesces repeated edits to the same property into a single undo entry.
  void beginEdit([String? key]) {
    if (key != null && key == _lastEditKey) return;
    _lastEditKey = key;
    _pushUndo();
  }

  void _endEditChain() => _lastEditKey = null;

  void _pushUndo() {
    _undoStack.add(_document.deepCopy());
    if (_undoStack.length > 100) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void onModelChanged() {
    _dirty = true;
    _flushToScene();
    _persist();
    notifyListeners();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_document.deepCopy());
    _document = _undoStack.removeLast();
    _selected = null;
    _dirty = true;
    _flushToScene();
    _persist();
    _endEditChain();
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_document.deepCopy());
    _document = _redoStack.removeLast();
    _selected = null;
    _dirty = true;
    _flushToScene();
    _persist();
    _endEditChain();
    notifyListeners();
  }

  // ------------------------------------------------------------------- files

  void newDocument() {
    _flushToScene();
    _pushUndo();
    _document = FxmlDocument.empty();
    _selected = null;
    _fileName = null;
    _currentProject = null;
    _activeScene = null;
    _standaloneOpen = true;
    _dirty = false;
    _validation = null;
    _endEditChain();
    notifyListeners();
  }

  void loadExample() {
    _pushUndo();
    _document = _parser.parse(exampleFxml);
    _selected = null;
    _fileName = 'example';
    _standaloneOpen = true;
    _dirty = false;
    _flushToScene();
    _persist();
    _endEditChain();
    notifyListeners();
  }

  bool loadFromString(String source, {String? fileName}) {
    try {
      _pushUndo();
      _document = _parser.parse(source);
      _selected = null;
      _fileName = fileName;
      _openSource = null;
      _dirty = false;
      _flushToScene();
      _persist();
      _endEditChain();
      notifyListeners();
      return true;
    } catch (_) {
      _undoStack.removeLast();
      return false;
    }
  }

  Future<bool> openFile() async {
    final picked = await _fileService.open();
    if (picked == null) return false;
    final name = picked.fileName.replaceAll(
      RegExp(r'\.fxml$', caseSensitive: false),
      '',
    );
    final ok = loadFromString(picked.content, fileName: name);
    if (ok) {
      _standaloneOpen = true;
      notifyListeners();
    }
    return ok;
  }

  String serialize() => _serializer.serialize(_document);

  // ----------------------------------------------------------------- code tabs

  /// Switches the main pane between the visual canvas and the code editor.
  void setCodeMode(bool value) {
    if (_codeMode == value) return;
    _codeMode = value;
    if (value) _codeEpoch++;
    notifyListeners();
  }

  /// Opens a generated Java file for editing in the code editor.
  void showSource(GeneratedFile file) {
    _openSource = file;
    _codeMode = true;
    _codeEpoch++;
    notifyListeners();
  }

  /// Opens the active scene's FXML source for editing in the code editor.
  void editSceneSource() {
    _openSource = null;
    _codeMode = true;
    _codeEpoch++;
    notifyListeners();
  }

  /// Stops showing a generated Java file (the code editor falls back to the
  /// active scene's FXML).
  void closeSource() {
    if (_openSource == null) return;
    _openSource = null;
    notifyListeners();
  }

  /// Commits the given text to whichever file the code editor is showing.
  /// Returns false when the FXML source could not be parsed.
  bool applyCode(String text) {
    final source = _openSource;
    if (source != null) return applyJavaSource(source.path, text);
    return applyFxmlSource(text);
  }

  /// Stores a hand-edited Java source on the project. Editing it back to the
  /// generated content removes the override so the file tracks generation.
  bool applyJavaSource(String path, String content) {
    final project = _currentProject;
    if (project == null) return false;
    String? fallback;
    for (final file in JavaGenerator.generate(project, applyOverrides: false)) {
      if (file.path == path) {
        fallback = file.content;
        break;
      }
    }
    if (fallback != null && fallback == content) {
      project.sourceOverrides.remove(path);
    } else {
      project.sourceOverrides[path] = content;
    }
    _openSource = GeneratedFile(path: path, content: content);
    _persist();
    notifyListeners();
    return true;
  }

  /// Replaces the current document with the given FXML source.
  bool applyFxmlSource(String source) {
    final ok = loadFromString(source, fileName: _fileName);
    if (ok) {
      _openSource = null;
      notifyListeners();
    }
    return ok;
  }

  // ------------------------------------------------------------------------ ui

  static const String _languageKey = 'app_lang';

  /// BCP-47 locale used by the whole UI (`en` or `ru`).
  String get languageCode => _languageCode;

  Locale get locale => Locale(_languageCode);

  bool get isRussian => _languageCode == 'ru';

  /// Switches the interface language and persists the choice for later runs.
  Future<void> setLanguage(String code) async {
    if (code != 'en' && code != 'ru') return;
    if (_languageCode == code) return;
    _languageCode = code;
    await _tokenStore.write(_languageKey, code);
    notifyListeners();
  }

  Future<void> _loadLanguage() async {
    final stored = await _tokenStore.read(_languageKey);
    if (stored == null || (stored != 'en' && stored != 'ru')) return;
    _languageCode = stored;
    notifyListeners();
  }

  static const String _themeKey = 'app_theme';

  /// Theme preference: `system`, `light` or `dark`.
  String get themeSetting => _themeSetting;

  String _themeSetting = 'system';

  bool get isDarkTheme => _themeSetting == 'dark';
  bool get isLightTheme => _themeSetting == 'light';

  /// Switches the colour theme and persists the choice for later runs.
  Future<void> setTheme(String value) async {
    if (value != 'system' && value != 'light' && value != 'dark') return;
    if (_themeSetting == value) return;
    _themeSetting = value;
    await _tokenStore.write(_themeKey, value);
    notifyListeners();
  }

  Future<void> _loadTheme() async {
    final stored = await _tokenStore.read(_themeKey);
    if (stored == null ||
        (stored != 'system' && stored != 'light' && stored != 'dark')) {
      return;
    }
    _themeSetting = stored;
    notifyListeners();
  }

  static const String _splitKey = 'project_split_v2';

  /// Share of the right column given to the project tree, or null while the
  /// divider has not been dragged and the pane should fit its content.
  double? get treeFraction => _treeFraction;
  double? _treeFraction;

  /// Remembers how the project tree and the canvas properties are split.
  void setTreeFraction(double value) {
    final clamped = value.clamp(0.05, 0.95);
    if (_treeFraction != null && (clamped - _treeFraction!).abs() < 0.001) {
      return;
    }
    _treeFraction = clamped;
    _tokenStore.write(_splitKey, clamped.toString());
    notifyListeners();
  }

  /// Drops the stored height so the pane follows its content again.
  void clearTreeFraction() {
    if (_treeFraction == null) return;
    _treeFraction = null;
    _tokenStore.delete(_splitKey);
    notifyListeners();
  }

  Future<void> _loadSplit() async {
    final stored = await _tokenStore.read(_splitKey);
    final value = double.tryParse(stored ?? '');
    if (value == null) return;
    _treeFraction = value.clamp(0.05, 0.95);
  }

  // -------------------------------------------------------------------------- ai

  static const String _aiModelKey = 'ai_model';

  /// The Ollama model the user picked for AI fixes, if any.
  Future<String?> readAiModel() => _tokenStore.read(_aiModelKey);

  Future<void> writeAiModel(String model) =>
      _tokenStore.write(_aiModelKey, model);

  /// Persists the open document into the workspace: no file is downloaded.
  ///
  /// Inside a project the FXML is written back to the active scene; a document
  /// opened on its own is stored in the workspace so it comes back on reload.
  Future<bool> saveDocument() async {
    final scene = _activeScene;
    if (scene != null) {
      scene.fxml = serialize();
      _dirty = false;
      _flushToScene();
      await _persist();
      notifyListeners();
      return true;
    }
    _looseDocument = serialize();
    _looseDocumentName = _fileName ?? _looseDocumentName;
    _dirty = false;
    await _persist();
    notifyListeners();
    return true;
  }

  /// Writes the document to a file the user chooses. Separate from
  /// [saveDocument] on purpose: saving must never trigger a download.
  Future<bool> saveFile() async {
    final name = '${_fileName ?? "untitled"}.fxml';
    final ok = await _fileService.save(serialize(), name);
    if (ok) {
      _fileName = _fileName ?? 'untitled';
      _dirty = false;
      notifyListeners();
    }
    return ok;
  }

  // -------------------------------------------------------------- view options

  void setZoom(double value) {
    _zoom = value.clamp(0.25, 4.0);
    notifyListeners();
  }

  void zoomIn() => setZoom(_zoom + 0.1);

  void zoomOut() => setZoom(_zoom - 0.1);

  void resetZoom() => setZoom(1.0);

  void toggleGrid() {
    _showGrid = !_showGrid;
    notifyListeners();
  }

  // --------------------------------------------------------------- workspace

  /// Restores a previous session from the stored token, or shows the login
  /// screen. Called automatically on startup.
  Future<void> initAuth() async {
    if (_authDecided) return;
    _authDecided = true;
    final token = await _tokenStore.read('auth_token');
    final email = await _tokenStore.read('auth_email');
    final userId = await _tokenStore.read('auth_user_id');
    if (token == null || token.isEmpty) {
      _authStatus = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    _token = token;
    // Do not clobber a value that a concurrent profile update already set.
    _userEmail ??= email ?? '';
    _userId ??= userId;
    _avatar ??= await _tokenStore.read('auth_avatar');
    _authStatus = AuthStatus.loading;
    notifyListeners();
    // The workspace of this account is loaded from its own storage slot, so
    // the projects of another person are never shown.
    await loadWorkspace();
    final fetch = await _api.getWorkspace(_token!);
    if (fetch.status == ApiStatus.unauthorized) {
      _token = null;
      _userEmail = null;
      _userId = null;
      _avatar = null;
      await _tokenStore.delete('auth_token');
      await _tokenStore.delete('auth_email');
      await _tokenStore.delete('auth_user_id');
      await _tokenStore.delete('auth_avatar');
      _authStatus = AuthStatus.signedOut;
      await loadWorkspace();
    } else {
      if (fetch.isOk) _adoptServerWorkspace(fetch.value);
      _authStatus = AuthStatus.signedIn;
      unawaited(refreshProfile());
    }
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    _authBusy = true;
    _authError = null;
    notifyListeners();
    await _handleAuthResult(await _api.login(email.trim(), password));
  }

  Future<void> register(String email, String password) async {
    _authBusy = true;
    _authError = null;
    notifyListeners();
    await _handleAuthResult(await _api.register(email.trim(), password));
  }

  /// Returns to the login screen (e.g. from the account menu) while keeping
  /// the local projects intact for migration on the next sign-in.
  void requestLogin() {
    _authStatus = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<void> signOut() async {
    // The projects stay in the storage slot of the account that owns them, so
    // the next person to use this device does not see them.
    await _persist();
    _token = null;
    _userEmail = null;
    _userId = null;
    _avatar = null;
    await _tokenStore.delete('auth_token');
    await _tokenStore.delete('auth_email');
    await _tokenStore.delete('auth_user_id');
    await _tokenStore.delete('auth_avatar');
    _authStatus = AuthStatus.signedOut;
    await loadWorkspace(replace: true);
    notifyListeners();
  }

  Future<void> _handleAuthResult(ApiResult<AuthUser> result) async {
    _authBusy = false;
    if (result.isOk) {
      final user = result.value!;
      _token = user.token;
      _userEmail = user.email;
      _userId = user.id ?? _userId;
      _avatar = user.avatar;
      await _tokenStore.write('auth_token', _token!);
      await _tokenStore.write('auth_email', _userEmail!);
      if (_userId != null) await _tokenStore.write('auth_user_id', _userId!);
      await _storeAvatar(_avatar);
      // The projects prepared on this device without a sign-in move into the
      // slot of the account, then its own workspace is loaded.
      await _migrateGuestScope();
      await loadWorkspace();
      await loadSharedProjects();
      await loadAccounts();
      await _synchronizeAfterLogin();
      await refreshProfile();
      _authStatus = AuthStatus.signedIn;
    } else {
      _authStatus = AuthStatus.signedOut;
      _authError = result.message ?? 'Authentication failed.';
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------- profile

  /// Profile picture as a `data:` URL, or null when none was uploaded.
  String? get avatarDataUrl => _avatar;

  /// Result of the last profile operation, surfaced in the dialog.
  String? profileMessage;
  bool profileError = false;

  /// Largest avatar accepted by the backend, in bytes of raw image data.
  static const int maxAvatarBytes = 400 * 1024;

  Future<void> refreshProfile() async {
    final token = _token;
    if (token == null || _authStatus != AuthStatus.signedIn) return;
    final result = await _api.getProfile(token);
    // A profile update may have rotated the token while this request was in
    // flight; such an answer describes the previous login and must not
    // overwrite the newer values.
    if (token != _token) return;
    if (!result.isOk || result.value == null) return;
    _userEmail = result.value!.email;
    _userId = result.value!.id ?? _userId;
    _avatar = result.value!.avatar;
    await _tokenStore.write('auth_email', _userEmail!);
    if (_userId != null) await _tokenStore.write('auth_user_id', _userId!);
    await _storeAvatar(_avatar);
    notifyListeners();
  }

  /// Changes the login. Returns true when the server accepted it.
  Future<bool> updateEmail(String email) async {
    final token = _token;
    final normalized = email.trim();
    if (token == null) {
      _setProfileMessage('You are not signed in.', error: true);
      return false;
    }
    if (normalized.toLowerCase() == (_userEmail ?? '').toLowerCase()) {
      _setProfileMessage('The login is unchanged.', error: false);
      return false;
    }
    final result = await _api.updateEmail(token, normalized);
    if (result.isOk && result.value != null) {
      _userEmail = result.value!.email;
      // The old token carries the previous address, so take the fresh one.
      _token = result.value!.token;
      _avatar = result.value!.avatar ?? _avatar;
      await _tokenStore.write('auth_token', _token!);
      await _tokenStore.write('auth_email', _userEmail!);
      await _storeAvatar(_avatar);
      _setProfileMessage('Login updated.', error: false);
      notifyListeners();
      return true;
    }
    _setProfileMessage(
      result.message ?? 'Could not change the login.',
      error: true,
    );
    notifyListeners();
    return false;
  }

  /// Changes the password after verifying the current one.
  Future<bool> changePassword(String current, String next) async {
    final token = _token;
    if (token == null) {
      _setProfileMessage('You are not signed in.', error: true);
      return false;
    }
    final result = await _api.changePassword(token, current, next);
    if (result.isOk) {
      _setProfileMessage('Password changed.', error: false);
      notifyListeners();
      return true;
    }
    _setProfileMessage(
      result.message ?? 'Could not change the password.',
      error: true,
    );
    notifyListeners();
    return false;
  }

  /// Uploads raw image [bytes] as the profile picture.
  Future<bool> uploadAvatar(Uint8List bytes, {required String mimeType}) async {
    final token = _token;
    if (token == null) {
      _setProfileMessage('You are not signed in.', error: true);
      return false;
    }
    if (bytes.isEmpty) {
      _setProfileMessage('The picture could not be read.', error: true);
      return false;
    }
    if (bytes.length > maxAvatarBytes) {
      _setProfileMessage('The picture is too large.', error: true);
      return false;
    }
    final dataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
    final result = await _api.updateAvatar(token, dataUrl);
    if (result.isOk) {
      _avatar = result.value ?? dataUrl;
      await _storeAvatar(_avatar);
      _setProfileMessage('Picture updated.', error: false);
      notifyListeners();
      return true;
    }
    _setProfileMessage(
      result.message ?? 'Could not upload the picture.',
      error: true,
    );
    notifyListeners();
    return false;
  }

  /// Removes the profile picture.
  Future<bool> removeAvatar() async {
    final token = _token;
    if (token == null) return false;
    final result = await _api.updateAvatar(token, null);
    if (result.isOk) {
      _avatar = null;
      await _storeAvatar(null);
      _setProfileMessage('Picture removed.', error: false);
      notifyListeners();
      return true;
    }
    _setProfileMessage(
      result.message ?? 'Could not remove the picture.',
      error: true,
    );
    notifyListeners();
    return false;
  }

  void _setProfileMessage(String message, {required bool error}) {
    profileMessage = message;
    profileError = error;
  }

  Future<void> _storeAvatar(String? avatar) async {
    if (avatar == null) {
      await _tokenStore.delete('auth_avatar');
    } else {
      await _tokenStore.write('auth_avatar', avatar);
    }
  }

  /// After login: adopt the cloud workspace, or migrate local projects up if
  /// the account is empty (first sign-in).
  Future<void> _synchronizeAfterLogin() async {
    final fetch = await _api.getWorkspace(_token!);
    if (!fetch.isOk) return;
    final remoteHasProjects = _adoptServerWorkspace(fetch.value);
    if (!remoteHasProjects) {
      // The account has nothing yet, so the projects prepared on this device
      // become its property and are uploaded with the owner's name.
      _claimGuestProjects();
      await _pushWorkingCopy();
    } else {
      // The cloud copy wins; its projects already carry their owner.
      await _persist();
    }
  }

  /// Assigns the freshly signed-in account as the owner of the projects that
  /// were created without a sign-in. Projects of another account are left
  /// alone, so nobody adopts somebody else's work.
  void _claimGuestProjects() {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;
    for (final project in _projects) {
      if (project.ownerId == null) {
        project.assignOwner(userId, _userEmail);
      }
    }
  }

  /// Projects that do not belong to anybody yet: they were created before the
  /// account was known. They are not shown in the picker.
  List<Project> get unownedProjects =>
      _projects.where((p) => p.ownerId == null).toList();

  /// Replaces the local workspace with the server's copy. Returns true only if
  /// the server actually had projects to adopt; an empty or missing remote
  /// leaves the local workspace untouched.
  bool _adoptServerWorkspace(String? raw) {
    if (raw == null || raw.trim().isEmpty) return false;
    try {
      final data = WorkspaceData.fromJson(jsonDecode(raw));
      if (data.projects.isEmpty) return false;
      _projects.clear();
      final seen = <String>{};
      for (final p in data.projects) {
        if (seen.add(p.id)) _projects.add(p);
      }
      _currentProject = null;
      _activeScene = null;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Uploads the current local workspace to the server.
  Future<void> _pushWorkingCopy() async {
    if (_token == null) return;
    try {
      await _api.putWorkspace(_token!, _workspaceJson());
    } catch (_) {}
  }

  Future<void> _pushWorkingCopyIfSignedIn() async {
    if (!signedIn || _token == null) return;
    try {
      await _api.putWorkspace(_token!, _workspaceJson());
    } catch (_) {}
  }

  String _workspaceJson() => jsonEncode(
    WorkspaceData(
      projects: _projects,
      document: _looseDocument,
      documentName: _looseDocumentName,
    ).toJson(),
  );

  /// Loads the persisted projects of the current owner (from device storage /
  /// browser localStorage). Every account has its own storage slot.
  ///
  /// With [replace] the current workspace is dropped even when nothing is
  /// stored for the scope; this is what signing out needs.
  Future<void> loadWorkspace({bool replace = false}) async {
    final raw = await _projectStorage.load(storageScope);
    if (raw == null || raw.isEmpty) {
      if (replace) {
        _projects.clear();
        _looseDocument = null;
        _looseDocumentName = null;
        _currentProject = null;
        _activeScene = null;
      }
      _projectsLoaded = true;
      notifyListeners();
      return;
    }
    try {
      final data = WorkspaceData.fromJson(jsonDecode(raw));
      // The list of projects is replaced, not merged: the projects of the
      // previous owner must not stay on screen.
      _projects.clear();
      // Drop duplicates that may have crept in (same id) so the picker
      // never shows the same project twice.
      final seen = <String>{};
      for (final p in data.projects) {
        if (seen.add(p.id)) _projects.add(p);
      }
      _looseDocument = data.document;
      _looseDocumentName = data.documentName;
      // A saved document outside of any project reopens straight away, so
      // the work is where the user left it.
      if (!_standaloneOpen && data.document != null) {
        if (loadFromString(data.document!, fileName: data.documentName)) {
          _standaloneOpen = true;
        }
      }
    } catch (_) {}
    _projectsLoaded = true;
    notifyListeners();
  }

  /// Copies the projects prepared without a sign-in into the slot of the
  /// account that has just signed in, so the work is not lost.
  Future<void> _migrateGuestScope() async {
    final guest = await _projectStorage.load(guestScope);
    if (guest == null || guest.isEmpty) return;
    final own = await _projectStorage.load(storageScope);
    if (own == null || own.isEmpty) {
      await _projectStorage.save(storageScope, guest);
    }
  }

  /// Writes the current document back into the active scene, if any.
  void _flushToScene() {
    if (_activeScene != null) {
      _activeScene!.fxml = _serializer.serialize(_document);
    }
  }

  /// Persists the whole workspace. Concurrent calls are coalesced so only the
  /// latest state is written locally (and pushed to the server when signed in).
  ///
  /// Every save also refreshes [validation], so the editor always shows the
  /// up-to-date state of the project.
  Future<void> _persist() {
    revalidate();
    final generation = ++_persistGeneration;
    _persistChain = _persistChain.then((_) async {
      if (generation != _persistGeneration) return;
      try {
        await _projectStorage.save(storageScope, _workspaceJson());
        await _pushWorkingCopyIfSignedIn();
      } catch (_) {}
    });
    return _persistChain;
  }

  /// Runs the mini neural network validation of the open project right away
  /// and rebuilds the UI only when the visible result changed. Called after
  /// every save; null when no project is open.
  void revalidate() {
    final project = _currentProject;
    final next = project == null ? null : BuildAnalyzer.validate(project);
    final prev = _validation;
    _validation = next;
    if ((next == null) != (prev == null)) {
      notifyListeners();
      return;
    }
    if (next == null) return;
    // Only rebuild when something the user can see has changed.
    if (next.score != prev!.score ||
        next.issues.length != prev.issues.length ||
        next.criticalIssueCount != prev.criticalIssueCount) {
      notifyListeners();
    }
  }

  /// Completes when all scheduled autosaves have been written.
  Future<void> get flushAutosave => _persistChain;

  String _newId() {
    _idCounter++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  String _fqnController(String simple) {
    final pkg = _currentProject?.package ?? '';
    if (pkg.isEmpty) return simple;
    return '$pkg.$simple';
  }

  String _toClassName(String name) {
    final parts = name
        .split(RegExp(r'[^a-zA-Z0-9]'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join();
    return parts.isEmpty ? 'Controller' : parts;
  }

  String _uniqueSceneName(Project project, String base) {
    var candidate = base;
    var i = 2;
    while (project.scenes.any((s) => s.name == candidate)) {
      candidate = '$base$i';
      i++;
    }
    return candidate;
  }

  /// Builds an FXML document with the project's `fx:controller` wired to the
  /// root and the `fx` namespace declared.
  FxmlDocument _projectSceneFxml(String controllerFqn, {required bool sample}) {
    final doc = _parser.parse(sample ? exampleFxml : _emptySceneFxml);
    doc.root.attributes['fx:controller'] = controllerFqn;
    doc.root.attributes.putIfAbsent(
      'xmlns:fx',
      () => 'http://javafx.com/fxml/1',
    );
    return doc;
  }

  void createProject({
    String? name,
    String package = 'com.example',
    String? mainClass,
    String description = '',
  }) {
    final safeName = (name ?? '').trim().isEmpty ? 'Untitled' : name!.trim();
    final safeMain = (mainClass ?? '').trim().isEmpty
        ? 'MainApp'
        : mainClass!.trim();
    final project = Project(
      id: _newId(),
      name: safeName,
      package: package.trim().isEmpty ? 'com.example' : package.trim(),
      mainClass: safeMain,
      description: description.trim(),
      // A new project belongs to the account that is signed in.
      ownerId: _userId,
      ownerEmail: _userEmail,
    );
    final controllerSimple = '${safeMain}Controller';
    final controllerFqn = project.package.isEmpty
        ? controllerSimple
        : '${project.package}.$controllerSimple';
    final doc = _projectSceneFxml(controllerFqn, sample: true);
    _flushToScene();
    project.scenes.add(
      SceneFile(
        name: 'main',
        fxml: _serializer.serialize(doc),
        controllerClass: controllerFqn,
      ),
    );
    _projects.add(project);
    _currentProject = project;
    _activeScene = project.scenes.first;
    _standaloneOpen = false;
    _document = _parser.parse(project.scenes.first.fxml);
    _fileName = 'main';
    _openSource = null;
    _selected = null;
    _dirty = false;
    _undoStack.clear();
    _redoStack.clear();
    _endEditChain();
    _persist();
    notifyListeners();
  }

  void openProject(Project project) {
    _flushToScene();
    _currentProject = project;
    _standaloneOpen = false;
    final scene = project.mainScene;
    if (scene != null) {
      openScene(scene);
    } else {
      _activeScene = null;
      _openSource = null;
      revalidate();
      notifyListeners();
    }
    // A shared project keeps checking the server for the changes of the
    // other participants.
    _startCollaboration(project);
  }

  void openScene(SceneFile scene) {
    _flushToScene();
    _undoStack.clear();
    _redoStack.clear();
    _document = _parser.parse(scene.fxml);
    _activeScene = scene;
    _fileName = scene.name;
    _openSource = null;
    _selected = null;
    _dirty = false;
    _endEditChain();
    revalidate();
    notifyListeners();
  }

  // ------------------------------------------------------------- collaboration

  Timer? _collabTimer;

  /// Revision of the shared copy that the editor knows about.
  int _collabRevision = 0;

  /// True when the open project is shared with other people.
  bool get collaborativeMode => _currentProject?.collaborative ?? false;

  /// Message shown when somebody else has changed the project.
  String? collaborationNotice;

  /// Participants of the open project.
  List<ProjectMember> get collaborators =>
      _currentProject?.participants ?? <ProjectMember>[];

  /// Projects of other people the account takes part in.
  final List<Project> _sharedProjects = <Project>[];

  /// The shared projects the account may open.
  List<Project> get sharedProjects => List.unmodifiable(_sharedProjects);

  /// Every project the picker knows: the own ones and the shared ones.
  List<Project> get allProjects {
    final result = <Project>[..._projects];
    for (final project in _sharedProjects) {
      if (!result.any((p) => p.id == project.id)) result.add(project);
    }
    return result;
  }

  /// The projects the account may work on: the ones it owns and the ones it
  /// takes part in. Projects of somebody else are not shown at all.
  List<Project> get myProjects {
    final userId = _userId;
    final email = _userEmail?.toLowerCase();
    return allProjects.where((project) {
      // Projects without an owner are shown apart.
      if (project.ownerId == null) return false;
      if (userId != null && project.ownerId == userId) return true;
      if (email != null && project.ownerEmail?.toLowerCase() == email) {
        return true;
      }
      if (email == null) return false;
      return project.members.any((m) => m.email.toLowerCase() == email);
    }).toList();
  }

  /// True when the account owns the project or takes part in it.
  bool isMine(Project project) => myProjects.any((p) => p.id == project.id);

  /// Reads the projects the account takes part in from the server.
  Future<void> loadSharedProjects() async {
    final token = _token;
    if (token == null) return;
    final result = await _api.listSharedProjects(token);
    if (!result.isOk || result.value == null) return;
    _sharedProjects
      ..clear()
      ..addAll(result.value!);
    notifyListeners();
  }

  /// The accounts registered in the system, used to pick the participants of
  /// a project from the list.
  final List<Account> _accounts = <Account>[];

  /// The known accounts.
  List<Account> get accounts => List.unmodifiable(_accounts);

  /// The accounts that are not participants of the project yet.
  List<Account> availableAccounts(Project project) {
    final members = project.members.map((m) => m.email.toLowerCase()).toSet();
    return _accounts
        .where(
          (a) =>
              !members.contains(a.email.toLowerCase()) &&
              a.email.toLowerCase() != _userEmail?.toLowerCase(),
        )
        .toList();
  }

  /// Reads the list of the accounts from the server.
  Future<void> loadAccounts() async {
    final token = _token;
    if (token == null) return;
    final result = await _api.listAccounts(token);
    if (!result.isOk || result.value == null) return;
    _accounts
      ..clear()
      ..addAll(result.value!);
    notifyListeners();
  }

  /// Starts watching the shared project for the changes of the other people.
  void _startCollaboration(Project project) {
    _stopCollaboration();
    if (!project.collaborative || _token == null) return;
    _collabRevision = project.revision;
    _collabTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _checkSharedProject();
    });
  }

  void _stopCollaboration() {
    _collabTimer?.cancel();
    _collabTimer = null;
    _collabRevision = 0;
  }

  /// Reads the shared project from the server and applies the changes of the
  /// other participants.
  Future<void> _checkSharedProject() async {
    final token = _token;
    final project = _currentProject;
    if (token == null || project == null || !project.collaborative) return;
    final result = await _api.getSharedProject(token, project.id);
    if (!result.isOk || result.value == null) return;
    final remote = result.value!;
    if (remote.revision <= _collabRevision) return;

    _collabRevision = remote.revision;
    // The open document is left alone while the user is editing it; the
    // changes are taken over when the document is not being edited.
    if (_dirty) {
      collaborationNotice =
          'The project has been changed by another participant.';
      notifyListeners();
      return;
    }
    _applySharedProject(remote);
  }

  /// Replaces the open project with the copy of the server.
  void _applySharedProject(Project remote) {
    final project = _currentProject;
    if (project == null) return;
    project
      ..name = remote.name
      ..package = remote.package
      ..mainClass = remote.mainClass
      ..description = remote.description
      ..revision = remote.revision;
    project.replaceMembers(remote.members);
    project.scenes
      ..clear()
      ..addAll(remote.scenes.map((s) => s.copy()));
    project.sourceOverrides
      ..clear()
      ..addAll(remote.sourceOverrides);

    final active = _activeScene;
    if (active != null) {
      final updated = project.scenes.where((s) => s.name == active.name);
      if (updated.isNotEmpty) {
        _activeScene = updated.first;
        _document = _parser.parse(updated.first.fxml);
        _dirty = false;
        _undoStack.clear();
        _redoStack.clear();
        _endEditChain();
      }
    }
    collaborationNotice =
        'The project has been updated by another participant.';
    notifyListeners();
  }

  /// Uploads the project to the server, so the other participants see the
  /// changes. Without an argument the open project is published.
  Future<bool> publishSharedProject([Project? target]) async {
    final token = _token;
    final project = target ?? _currentProject;
    if (token == null || project == null) return false;
    if (!project.collaborative) {
      // The project is shared for the first time: it is created on the server.
      project.shared = true;
    }
    if (identical(project, _currentProject)) _flushToScene();
    final result = await _api.saveSharedProject(token, project);
    if (!result.isOk || result.value == null) {
      collaborationNotice = result.message ?? 'Could not save the project.';
      notifyListeners();
      return false;
    }
    final saved = result.value!;
    project
      ..revision = saved.revision
      ..shared = true;
    project.replaceMembers(saved.members);
    _collabRevision = saved.revision;
    collaborationNotice =
        'The project has been published for the participants.';
    notifyListeners();
    return true;
  }

  /// Invites a person to the open project.
  Future<bool> inviteCollaborator(String email, String role) async {
    final token = _token;
    final project = _currentProject;
    if (token == null || project == null) return false;
    final result = await _api.addProjectMember(
      token,
      project.id,
      email.trim(),
      role,
    );
    if (!result.isOk || result.value == null) {
      collaborationNotice = result.message ?? 'Could not add the participant.';
      notifyListeners();
      return false;
    }
    project.shared = true;
    project.replaceMembers(result.value!.members);
    _startCollaboration(project);
    collaborationNotice = 'The participant has been added.';
    notifyListeners();
    return true;
  }

  /// Changes the rights of a participant: editor or viewer.
  Future<bool> changeCollaboratorRole(String email, String role) async {
    final token = _token;
    final project = _currentProject;
    if (token == null || project == null) return false;
    final result = await _api.addProjectMember(token, project.id, email, role);
    if (!result.isOk || result.value == null) {
      collaborationNotice = result.message ?? 'Could not change the rights.';
      notifyListeners();
      return false;
    }
    project.replaceMembers(result.value!.members);
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------- invitation links

  /// The invitation found in the address of the page.
  Invite? pendingInvite;

  /// The invitation from the address of the page, if the page was opened
  /// with a link.
  Invite? get pendingInviteLink => _inviteLinks.pending;

  /// The invitation link of the open project, ready to be copied.
  String? inviteLink;

  /// Issues an invitation link for the open project and returns it.
  Future<String?> createInviteLink(String role) async {
    final token = _token;
    final project = _currentProject;
    if (token == null || project == null) return null;
    // The project must be on the server, otherwise the link leads to nothing.
    if (!project.shared) {
      final published = await publishSharedProject();
      if (!published) return null;
    }
    final result = await _api.createProjectInvite(token, project.id, role);
    if (!result.isOk || result.value == null) {
      collaborationNotice = result.message ?? 'Could not create the link.';
      notifyListeners();
      return null;
    }
    final link = _inviteLinks.build(project.id, result.value!.token);
    inviteLink = link;
    collaborationNotice = 'The invitation link is ready.';
    notifyListeners();
    return link;
  }

  /// Reads the invitation from the address of the page and asks the server
  /// about the project it points to.
  Future<ProjectInvite?> readPendingInvite() async {
    final invite = _inviteLinks.pending;
    final token = _token;
    if (invite == null || token == null) return null;
    final result = await _api.getProjectInvite(token, invite.token);
    if (!result.isOk || result.value == null) return null;
    return result.value;
  }

  /// Joins the project of the invitation link.
  Future<bool> acceptInvite(Invite invite) async {
    final token = _token;
    if (token == null) return false;
    final result = await _api.joinProject(
      token,
      invite.projectId,
      invite.token,
    );
    if (!result.isOk || result.value == null) {
      collaborationNotice = result.message ?? 'Could not join the project.';
      notifyListeners();
      return false;
    }
    final project = result.value!;
    if (!project.members.any((m) => m.email == _userEmail) &&
        project.ownerEmail != _userEmail) {
      project.members.add(
        ProjectMember(email: _userEmail ?? '', role: 'editor'),
      );
    }
    if (!_projects.any((p) => p.id == project.id)) {
      _projects.add(project);
    }
    await loadSharedProjects();
    notifyListeners();
    return true;
  }

  /// Removes a participant from the open project.
  Future<bool> removeCollaborator(String email) async {
    final token = _token;
    final project = _currentProject;
    if (token == null || project == null) return false;
    final result = await _api.removeProjectMember(token, project.id, email);
    if (!result.isOk || result.value == null) {
      collaborationNotice =
          result.message ?? 'Could not remove the participant.';
      notifyListeners();
      return false;
    }
    project.replaceMembers(result.value!.members);
    notifyListeners();
    return true;
  }

  /// Closes the current project and returns to the project picker.
  void backToProjects() {
    _flushToScene();
    _stopCollaboration();
    _currentProject = null;
    _activeScene = null;
    _openSource = null;
    _standaloneOpen = false;
    // The list of the shared projects may have changed meanwhile.
    unawaited(loadSharedProjects());
    notifyListeners();
  }

  void newScene(String baseName) {
    final project = _currentProject;
    if (project == null) return;
    final safe = _uniqueSceneName(
      project,
      baseName.trim().isEmpty ? 'scene' : baseName.trim(),
    );
    final controllerSimple = '${_toClassName(safe)}Controller';
    final doc = _projectSceneFxml(
      _fqnController(controllerSimple),
      sample: false,
    );
    final scene = SceneFile(
      name: safe,
      fxml: _serializer.serialize(doc),
      controllerClass: _fqnController(controllerSimple),
    );
    project.scenes.add(scene);
    openScene(scene);
    _persist();
  }

  void renameScene(SceneFile scene, String newName) {
    final project = _currentProject;
    final safe = newName.trim().replaceAll(RegExp(r'\s+'), '_');
    if (project == null || safe.isEmpty) return;
    if (project.scenes.any((s) => s.name == safe && !identical(s, scene))) {
      return;
    }
    scene.name = safe;
    if (identical(_activeScene, scene)) _fileName = safe;
    _persist();
    notifyListeners();
  }

  void deleteScene(SceneFile scene) {
    final project = _currentProject;
    if (project == null) return;
    _flushToScene();
    project.scenes.remove(scene);
    if (identical(_activeScene, scene)) {
      if (project.scenes.isEmpty) {
        _currentProject = null;
        _activeScene = null;
      } else {
        openScene(project.scenes.first);
      }
    }
    _persist();
    notifyListeners();
  }

  void renameProject(Project project, String newName) {
    final safe = newName.trim();
    if (safe.isEmpty) return;
    project.name = safe;
    _persist();
    notifyListeners();
  }

  /// Stores the free-form project description shown in the settings window and
  /// in the generated README.
  void setProjectDescription(Project project, String description) {
    project.description = description.trim();
    _persist();
    notifyListeners();
  }

  /// Changes the Java package used for the generated sources.
  /// Changes the Java package of the project and moves the controllers of all
  /// scenes into the new package, so the exported FXML keeps matching the
  /// generated classes.
  void setProjectPackage(Project project, String package) {
    project.package = package.trim();
    fixSceneControllers(project);
    _persist();
    notifyListeners();
  }

  /// Rewrites the controller of every scene into the current project package:
  /// both the declared `controllerClass` and the `fx:controller` attribute of
  /// the scene's FXML. Repairs the `ClassNotFoundException` that appears at
  /// launch when the project package was changed after the scenes were
  /// created.
  ///
  /// Also inserts the `<?import?>` statements missing from every scene's
  /// FXML (e.g. `javafx.scene.text.Font` for a `<Font>` property element),
  /// which otherwise make JavaFX fail with "… is not a valid type".
  /// Returns true when something was changed.
  bool fixSceneControllers(Project project) {
    // Bring the active scene's FXML up to date from the editor buffer first,
    // so the fix is not overwritten by the next flush.
    _flushToScene();
    final pkg = project.package;
    var changed = false;
    for (final scene in project.scenes) {
      var fxml = scene.fxml;
      final declared = (scene.controllerClass ?? '').trim();
      final fxmlMatch = RegExp(r'fx:controller\s*=\s*"([^"]+)"')
          .firstMatch(fxml);
      final fxmlFqn = fxmlMatch?.group(1);
      final source = declared.isNotEmpty ? declared : (fxmlFqn ?? '');
      if (source.isNotEmpty) {
        final simple = source.contains('.')
            ? source.substring(source.lastIndexOf('.') + 1)
            : source;
        final fqn = pkg.isEmpty ? simple : '$pkg.$simple';

        if (scene.controllerClass != fqn) {
          scene.controllerClass = fqn;
          changed = true;
        }
        if (fxmlFqn != null && fxmlFqn != fqn) {
          fxml = fxml.replaceFirst(
            RegExp(r'fx:controller\s*=\s*"[^"]*"'),
            'fx:controller="$fqn"',
          );
          changed = true;
        }
        // Keep the in-memory editor document consistent with the active
        // scene.
        if (identical(_activeScene, scene) && fxmlFqn != fqn) {
          _document.root.attributes['fx:controller'] = fqn;
        }
      }

      // Insert the <?import?> statements the scene relies on but does not
      // declare.
      final missingImports = BuildAnalyzer.missingImportStatements(fxml);
      if (missingImports.isNotEmpty) {
        fxml = _insertImports(fxml, missingImports);
        changed = true;
        if (identical(_activeScene, scene)) {
          for (final statement in missingImports) {
            _ensureImport(statement);
          }
        }
      }

      if (!identical(scene.fxml, fxml)) {
        scene.fxml = fxml;
      }
    }
    if (changed) {
      _persist();
      notifyListeners();
    }
    return changed;
  }

  /// Repairs everything the live validation reported (controllers and
  /// `<?import?>` statements) and re-runs the check. Returns true when
  /// something was changed.
  bool fixValidationIssues() {
    final project = _currentProject;
    if (project == null) return false;
    final changed = fixSceneControllers(project);
    // fixSceneControllers persists (and revalidates) only when it changed
    // something; refresh the report either way so the UI matches the model.
    if (!changed) revalidate();
    return changed;
  }

  /// Inserts `<?import?>` lines into [fxml] right after the last existing
  /// import (or after the XML declaration when there are none).
  static String _insertImports(String fxml, List<String> imports) {
    final lines = fxml.split('\n');
    var index = lines.indexWhere((line) => line.trimLeft().startsWith('<?xml'));
    final lastImport = lines.lastIndexWhere(
      (line) => line.trimLeft().startsWith('<?import'),
    );
    if (lastImport >= 0) {
      index = lastImport + 1;
    } else if (index >= 0) {
      // Insert right after the XML declaration line.
      index += 1;
    } else {
      index = 0;
    }
    lines.insertAll(index, imports.map((statement) => '<?import $statement?>'));
    return lines.join('\n');
  }

  /// Changes the entry point class of the generated Java application.
  void setProjectMainClass(Project project, String mainClass) {
    project.mainClass = mainClass.trim().isEmpty ? 'MainApp' : mainClass.trim();
    _persist();
    notifyListeners();
  }

  /// Transfers project ownership to another participant. Only the current
  /// owner may do this, and the new owner must already take part in the
  /// project.
  Future<bool> transferProjectOwnership(
    Project project,
    String newOwnerEmail,
  ) async {
    final currentUser = _userEmail;
    if (currentUser == null || project.ownerEmail != currentUser) return false;

    final newOwner = newOwnerEmail.trim();
    if (newOwner.isEmpty || newOwner.toLowerCase() == currentUser.toLowerCase())
      return false;

    final isParticipant = project.members.any(
      (m) => m.email.toLowerCase() == newOwner.toLowerCase(),
    );
    if (!isParticipant) return false;

    // Look up the account id by email.
    final newOwnerAccount = _accounts.firstWhere(
      (a) => a.email.toLowerCase() == newOwner.toLowerCase(),
      orElse: () => Account(id: '', email: newOwner),
    );

    // The old owner stays in the project as a participant.
    project.ownerId = newOwnerAccount.id.isNotEmpty ? newOwnerAccount.id : null;
    project.ownerEmail = newOwner;
    _persist();
    notifyListeners();
    return true;
  }

  void duplicateProject(Project project) {
    final copy = project.copy()
      ..id = _newId()
      ..name = '${project.name} copy';
    if (_projects.any((p) => p.name == copy.name)) {
      copy.name = '${project.name} copy $_idCounter';
    }
    _projects.insert(_projects.indexOf(project) + 1, copy);
    _persist();
    notifyListeners();
  }

  Future<void> deleteProject(Project project) async {
    _flushToScene();
    _projects.remove(project);
    if (identical(_currentProject, project)) {
      _currentProject = null;
      _activeScene = null;
    }
    notifyListeners();
    // A published project also lives on the server; remove it there too,
    // otherwise loadSharedProjects brings it back after the next sync.
    final token = _token;
    if (token != null && project.shared && project.id.isNotEmpty) {
      try {
        await _api.deleteSharedProject(token, project.id);
      } catch (_) {}
    }
    await _persist();
  }

  /// Packs the project into an archive and saves it. Returns false when the save
  /// was cancelled or failed.
  Future<bool> exportProject(Project project, ExportOptions options) {
    final bytes = _exporter.build(project, options);
    return _fileService.saveBytes(
      bytes,
      _exporter.fileName(project, options.format),
      dialogTitle: 'Export project',
      allowedExtensions: <String>[options.format.extension],
      mimeType: options.format.mimeType,
    );
  }

  /// Compiles the project on the build service and stores the artifact locally.
  /// [bundle] returns the self-contained archive instead of a bare JAR.
  ///
  /// A build is a release: the state of the project is fixed as a version and
  /// the result of the compilation is written into the history.
  Future<bool> buildProject(
    Project project, {
    required bool bundle,
    ExportOptions options = const ExportOptions(),
    String releaseNotes = '',
  }) async {
    // The history of the releases lives on the server, so the project is
    // published before the build. When that is not possible (nobody is signed
    // in, the server is down) the build still runs, only without the history.
    final published = await publishSharedProject(project);
    final version = published
        ? await _releaseVersion(project, releaseNotes)
        : null;
    final archive = _exporter.build(project, options);
    final started = DateTime.now();
    try {
      final artifact = await (buildClient ?? BuildClient()).build(
        archive,
        bundle: bundle,
      );
      final extension = artifact.fileName.contains('.') && bundle
          ? 'zip'
          : 'jar';
      await _recordBuild(
        project,
        version: version ?? project.revision,
        status: 'ok',
        artifact: artifact.fileName,
        sizeBytes: artifact.bytes.length,
        durationMs: DateTime.now().difference(started).inMilliseconds,
      );
      return await _fileService.saveBytes(
        artifact.bytes,
        '${project.name}.$extension',
        dialogTitle: 'Build project',
        allowedExtensions: <String>[extension],
        mimeType: bundle ? 'application/zip' : 'application/java-archive',
      );
    } catch (error) {
      await _recordBuild(
        project,
        version: version ?? project.revision,
        status: 'failed',
        log: error.toString(),
        durationMs: DateTime.now().difference(started).inMilliseconds,
      );
      rethrow;
    }
  }

  /// The history of the project: the released versions and the builds.
  ProjectHistory history = ProjectHistory();

  /// Reads the history of the project from the server.
  Future<ProjectHistory> loadHistory(Project project) async {
    final token = _token;
    // The history of another project must not be shown here.
    if (history.projectId != project.id) {
      history = ProjectHistory(projectId: project.id);
    }
    if (token == null) return history;
    final result = await _api.getProjectHistory(token, project.id);
    if (!result.isOk || result.value == null) return history;
    history = result.value!;
    notifyListeners();
    return history;
  }

  /// Fixes the current state of the project as a released version.
  Future<int?> _releaseVersion(Project project, String summary) async {
    final token = _token;
    if (token == null) return null;
    final result = await _api.createProjectVersion(
      token,
      project.id,
      summary,
      project.revision,
      scenesCount: project.scenes.length,
      filesCount: project.scenes.length,
      sceneNames: project.scenes.map((scene) => scene.name).toList(),
    );
    if (!result.isOk || result.value == null) {
      collaborationNotice = result.message ?? 'Could not release the version.';
      notifyListeners();
      return null;
    }
    history = result.value!;
    notifyListeners();
    return project.revision;
  }

  /// Writes the result of a build into the history of the project.
  Future<void> _recordBuild(
    Project project, {
    required int version,
    required String status,
    String log = '',
    String artifact = '',
    int durationMs = 0,
    int sizeBytes = 0,
  }) async {
    final token = _token;
    if (token == null) return;
    final result = await _api.recordProjectBuild(
      token,
      project.id,
      BuildRecord(
        id: 'b${DateTime.now().microsecondsSinceEpoch}',
        version: version,
        date: DateTime.now().toUtc(),
        author: _userEmail ?? '',
        status: status,
        log: log,
        artifact: artifact,
        durationMs: durationMs,
        sizeBytes: sizeBytes,
      ),
    );
    if (result.isOk && result.value != null) {
      history = result.value!;
      notifyListeners();
    }
  }

  /// True when the build service can be reached.
  Future<bool> isBuilderAvailable() async =>
      await (buildClient ?? BuildClient()).isAvailable();

  Future<bool> importProject() async {
    final picked = await _fileService.open();
    if (picked == null) return false;
    try {
      final json = jsonDecode(picked.content) as Map<String, dynamic>;
      final project = Project.fromJson(json);
      if (project.name.isEmpty || project.scenes.isEmpty) return false;
      var name = project.name;
      var i = 2;
      while (_projects.any((p) => p.name == name)) {
        name = '${project.name} $i';
        i++;
      }
      project.name = name;
      project.id = _newId();
      _projects.add(project);
      _persist();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------- node editing

  void setAttribute(FxmlNode node, String name, String? value) {
    beginEdit('attr:${identityHashCode(node)}:$name');
    if (value == null || value.isEmpty) {
      node.attributes.remove(name);
    } else {
      node.attributes[name] = value;
    }
    onModelChanged();
  }

  void removeAttribute(FxmlNode node, String name) {
    beginEdit('attr:${identityHashCode(node)}:$name');
    node.attributes.remove(name);
    onModelChanged();
  }

  /// Ensures `owner.properties[propertyTag]` contains a child of type
  /// [valueTag] and returns it, then sets one of its attributes.
  FxmlNode ensurePropertyChild(
    FxmlNode owner,
    String propertyTag,
    String valueTag,
  ) {
    final property = owner.properties.putIfAbsent(
      propertyTag,
      () => FxmlNode(propertyTag, isProperty: true),
    );
    if (property.children.isEmpty) {
      property.addChild(FxmlNode(valueTag));
    }
    return property.children.first;
  }

  void setPropertyAttribute(
    FxmlNode owner,
    String propertyTag,
    String valueTag,
    String attribute,
    String? value,
  ) {
    beginEdit('prop:${identityHashCode(owner)}:$propertyTag:$attribute');
    final child = ensurePropertyChild(owner, propertyTag, valueTag);
    // Property values such as `<Font>` or `<Cursor>` are real JavaFX classes
    // and need their own `<?import?>` — without it the exported scene fails
    // to load with "… is not a valid type".
    final valueImport = FxCatalog.importFor(valueTag);
    if (valueImport != null) {
      _ensureImport(valueImport);
    }
    if (value == null || value.isEmpty) {
      child.attributes.remove(attribute);
    } else {
      child.attributes[attribute] = value;
    }
    if (child.attributes.isEmpty) {
      owner.properties.remove(propertyTag);
    }
    onModelChanged();
  }

  void addComponent(FxComponent component, {FxmlNode? parent}) {
    _pushUndo();
    final target = parent ?? _resolveTarget();
    _ensureImport(component.importStatement);
    final node = FxmlNode(component.name)
      ..attributes.addAll(component.defaults);
    _insertChild(target, node);
    _placeNode(target, node);
    _selected = node;
    _endEditChain();
    onModelChanged();
  }

  FxmlNode _resolveTarget() {
    final current = _selected;
    if (current == null) return _document.root;
    if (FxCatalog.isChildrenContainer(current.tag)) return current;
    return current.parent ?? _document.root;
  }

  void _insertChild(FxmlNode parent, FxmlNode child) {
    switch (parent.tag) {
      case 'ScrollPane':
      case 'TitledPane':
        parent.properties['content'] = FxmlNode('content', isProperty: true)
          ..addChild(child);
        break;
      case 'BorderPane':
        parent.properties['center'] = FxmlNode('center', isProperty: true)
          ..addChild(child);
        break;
      case 'TabPane':
        final tab = FxmlNode('Tab')..attributes['text'] = 'Tab';
        tab.addChild(child);
        final tabs = parent.properties.putIfAbsent(
          'tabs',
          () => FxmlNode('tabs', isProperty: true),
        );
        tabs.addChild(tab);
        break;
      default:
        parent.addChild(child);
    }
  }

  void _placeNode(FxmlNode parent, FxmlNode node) {
    const offset = 24.0;
    final index = parent.children.length;
    final cascade = offset + (index % 6) * offset * 0.4;
    if (parent.tag == 'AnchorPane') {
      node.attributes['AnchorPane.leftAnchor'] = cascade.toStringAsFixed(1);
      node.attributes['AnchorPane.topAnchor'] = cascade.toStringAsFixed(1);
    } else if (const {'Pane', 'Region', 'Group'}.contains(parent.tag)) {
      node.attributes['layoutX'] = cascade.toStringAsFixed(1);
      node.attributes['layoutY'] = cascade.toStringAsFixed(1);
    }
  }

  void _ensureImport(String importStatement) {
    if (!_document.imports.contains(importStatement)) {
      _document.imports.add(importStatement);
    }
  }

  void deleteSelected() {
    final node = _selected;
    if (node == null) return;
    _pushUndo();
    if (!_removeFromTree(node)) {
      _undoStack.removeLast();
      return;
    }
    _cleanupEmptyProperties();
    _selected = node.parent;
    _endEditChain();
    onModelChanged();
  }

  /// Removes property elements (e.g. `content`, `center`) that no longer hold
  /// any value, so the serialized FXML stays clean.
  void _cleanupEmptyProperties() {
    for (final node in _document.allNodes.toList()) {
      node.properties.removeWhere(
        (_, property) =>
            property.children.isEmpty &&
            property.attributes.isEmpty &&
            property.text == null,
      );
    }
  }

  bool _removeFromTree(FxmlNode node) {
    final parent = node.parent;
    if (parent != null && parent.removeChild(node)) return true;
    for (final entry in _document.allNodes.toList()) {
      for (final property in entry.properties.entries) {
        if (property.value.children.contains(node)) {
          property.value.removeChild(node);
          return true;
        }
        if (identical(property.value, node)) {
          entry.properties.remove(property.key);
          return true;
        }
      }
    }
    if (identical(_document.root, node)) return false;
    return false;
  }

  void duplicateSelected() {
    final node = _selected;
    if (node == null || node.parent == null) return;
    _pushUndo();
    final copy = node.deepCopy();
    final parent = node.parent!;
    final index = parent.children.indexOf(node);
    parent.addChild(copy, at: index + 1);
    final geometry = NodeGeometryOffset(copy);
    geometry.offsetBy(16);
    _selected = copy;
    _endEditChain();
    onModelChanged();
  }

  void reorderSelected(int delta) {
    final node = _selected;
    final parent = node?.parent;
    if (node == null || parent == null) return;
    final index = parent.children.indexOf(node);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= parent.children.length) return;
    _pushUndo();
    parent.children.removeAt(index);
    parent.children.insert(target, node);
    onModelChanged();
  }

  void moveSelected(int direction, double step) {
    final node = _selected;
    if (node == null) return;
    _pushUndo();
    NodeGeometryOffset(node).move(direction, step);
    onModelChanged();
  }
}

/// Small helper to nudge nodes (used by duplicate and arrow-key movement).
class NodeGeometryOffset {
  NodeGeometryOffset(this.node);
  final FxmlNode node;

  double _attr(String name) =>
      double.tryParse(node.attributes[name] ?? '') ?? 0;

  void move(int direction, double step) {
    // direction: 0=up, 1=down, 2=left, 3=right
    _applyOffset(
      dx: direction == 2 ? -step : (direction == 3 ? step : 0),
      dy: direction == 0 ? -step : (direction == 1 ? step : 0),
    );
  }

  void offsetBy(double delta) => _applyOffset(dx: delta, dy: delta);

  void _applyOffset({required double dx, required double dy}) {
    if (node.parent?.tag == 'AnchorPane') {
      node.attributes['AnchorPane.leftAnchor'] =
          (_attr('AnchorPane.leftAnchor') + dx).toStringAsFixed(1);
      node.attributes['AnchorPane.topAnchor'] =
          (_attr('AnchorPane.topAnchor') + dy).toStringAsFixed(1);
      return;
    }
    node.attributes['layoutX'] = (_attr('layoutX') + dx).toStringAsFixed(1);
    node.attributes['layoutY'] = (_attr('layoutY') + dy).toStringAsFixed(1);
  }
}

/// A ready-to-use demonstration document.
const String exampleFxml = '''<?xml version="1.0" encoding="UTF-8"?>
<?import javafx.scene.control.*?>
<?import javafx.scene.layout.*?>
<?import javafx.scene.text.Font?>
<?import javafx.scene.Cursor?>
<AnchorPane xmlns="http://javafx.com/javafx/17.0.2" xmlns:fx="http://javafx.com/fxml/1" prefWidth="800.0" prefHeight="600.0">
    <Label text="Login" AnchorPane.leftAnchor="60.0" AnchorPane.topAnchor="50.0">
        <font>
            <Font size="24.0"/>
        </font>
    </Label>
    <Label text="Username" AnchorPane.leftAnchor="60.0" AnchorPane.topAnchor="120.0"/>
    <TextField promptText="Enter username" prefWidth="240.0" AnchorPane.leftAnchor="60.0" AnchorPane.topAnchor="150.0"/>
    <Label text="Password" AnchorPane.leftAnchor="60.0" AnchorPane.topAnchor="200.0"/>
    <PasswordField promptText="Enter password" prefWidth="240.0" AnchorPane.leftAnchor="60.0" AnchorPane.topAnchor="230.0"/>
    <CheckBox text="Remember me" AnchorPane.leftAnchor="60.0" AnchorPane.topAnchor="280.0"/>
    <Button text="Sign in" AnchorPane.leftAnchor="60.0" AnchorPane.topAnchor="320.0">
        <cursor>
            <Cursor fx:constant="HAND"/>
        </cursor>
    </Button>
    <Button text="Cancel" AnchorPane.leftAnchor="160.0" AnchorPane.topAnchor="320.0"/>
</AnchorPane>
''';

/// An empty AnchorPane used as the starting point for new project scenes.
const String _emptySceneFxml = '''<?xml version="1.0" encoding="UTF-8"?>
<?import javafx.scene.control.*?>
<?import javafx.scene.layout.*?>
<AnchorPane xmlns="http://javafx.com/javafx/17.0.2" xmlns:fx="http://javafx.com/fxml/1" prefWidth="800.0" prefHeight="600.0">
</AnchorPane>
''';
