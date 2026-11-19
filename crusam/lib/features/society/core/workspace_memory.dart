import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

bool isSocietyLocation(String? path) {
  if (path == null || path.isEmpty) return false;
  return path == '/society' || path.startsWith('/society/');
}

class WorkspaceMemory {
  WorkspaceMemory._();
  static final WorkspaceMemory instance = WorkspaceMemory._();

  static const String keyLastCrusamPath = 'workspace.last_crusam_path';
  static const String keyLastSocietyPath = 'workspace.last_society_path';

  static const String defaultCrusamPath = '/dashboard';
  static const String defaultSocietyPath = '/society/overview';

  String _lastCrusamPath = defaultCrusamPath;
  String _lastSocietyPath = defaultSocietyPath;
  bool _initialized = false;

  String get lastCrusamPath => _lastCrusamPath;
  String get lastSocietyPath => _lastSocietyPath;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final c = prefs.getString(keyLastCrusamPath);
      if (c != null && c.isNotEmpty && !isSocietyLocation(c)) {
        _lastCrusamPath = _cleanPath(c);
      }
      final s = prefs.getString(keyLastSocietyPath);
      if (s != null && s.isNotEmpty && isSocietyLocation(s)) {
        _lastSocietyPath = _cleanPath(s);
      }
      _initialized = true;
    } catch (_) {
      // Fallback to defaults
    }
  }

  String _cleanPath(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.path.isNotEmpty) {
      return uri.path;
    }
    return raw;
  }

  void recordLocation(String rawPath) {
    final clean = _cleanPath(rawPath);
    if (isSocietyLocation(clean)) {
      _lastSocietyPath = clean;
      unawaited(_persist(keyLastSocietyPath, clean));
    } else {
      _lastCrusamPath = clean;
      unawaited(_persist(keyLastCrusamPath, clean));
    }
  }

  Future<void> record(String rawPath) async {
    final clean = _cleanPath(rawPath);
    if (isSocietyLocation(clean)) {
      _lastSocietyPath = clean;
      await _persist(keyLastSocietyPath, clean);
    } else {
      _lastCrusamPath = clean;
      await _persist(keyLastCrusamPath, clean);
    }
  }

  Future<void> _persist(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }

  void resetForTest() {
    _lastCrusamPath = defaultCrusamPath;
    _lastSocietyPath = defaultSocietyPath;
    _initialized = false;
  }
}
