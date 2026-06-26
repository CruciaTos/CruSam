// lib/core/updater/update_notifier.dart

import 'package:flutter/foundation.dart';

import 'update_model.dart';
import 'update_service.dart';

enum UpdateState { idle, checking, downloading, launching, error }

class UpdateNotifier extends ChangeNotifier {
  UpdateNotifier._();

  static final UpdateNotifier instance = UpdateNotifier._();

  UpdateState _state = UpdateState.idle;
  UpdateInfo? _info;
  double _downloadProgress = 0;
  String? _errorMessage;

  UpdateState get state => _state;
  UpdateInfo? get info => _info;
  double get downloadProgress => _downloadProgress;
  String? get errorMessage => _errorMessage;

  bool get hasUpdate => _info?.updateAvailable ?? false;
  bool get isForced => _info?.force ?? false;
  bool get isBusy =>
      _state == UpdateState.checking ||
      _state == UpdateState.downloading ||
      _state == UpdateState.launching;

  Future<void> checkForUpdate() async {
    if (_state == UpdateState.checking) return;

    _errorMessage = null;
    _setState(UpdateState.checking);

    try {
      _info = await UpdateService.checkForUpdate();
      _setState(UpdateState.idle);
    } catch (e) {
      _info = null;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setState(UpdateState.error);
    }
  }

  Future<void> downloadAndInstall() async {
    final info = _info;
    if (info == null || !info.updateAvailable) return;
    if (_state == UpdateState.downloading || _state == UpdateState.launching) {
      return;
    }

    _errorMessage = null;
    _downloadProgress = 0;
    _setState(UpdateState.downloading);

    try {
      final zipPath = await UpdateService.downloadUpdate(
        info.downloadUrl,
        (progress) {
          _downloadProgress = progress;
          notifyListeners();
        },
      );

      // Set launching state BEFORE attempting launch so the UI reflects it.
      _setState(UpdateState.launching);

      // Pass info.latestVersion so updater.exe can write installed_version.txt.
      // That file is what fixes the "still shows 1.0.0 after update" problem.
      final launchError = await UpdateService.launchUpdaterAndExit(
        zipPath,
        info.latestVersion,
      );
      if (launchError != null) {
        _errorMessage = launchError;
        _setState(UpdateState.error);
      }
      // If launchError == null the process called exit(0); we never reach here.
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setState(UpdateState.error);
    }
  }

  void clearError() {
    _errorMessage = null;
    _setState(UpdateState.idle);
  }

  void _setState(UpdateState state) {
    _state = state;
    notifyListeners();
  }
}