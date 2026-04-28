import 'package:flutter/foundation.dart';
import '../data/models/user_model.dart';
import '../data/repositories/auth_repository_impl.dart';

class AuthNotifier extends ChangeNotifier {
  AuthNotifier._() {
    // Immediately restore session on first access so the router never
    // sees isLoggedIn == false before the DB has been checked.
    checkSession();
  }

  static final instance = AuthNotifier._();

  final _repo = AuthRepositoryImpl();

  UserModel? _user;
  // Starts true so any router guard waits for checkSession() to complete
  // before deciding whether to show login or dashboard.
  bool _isLoading = true;
  String? _error;

  UserModel? get user      => _user;
  bool       get isLoading => _isLoading;
  bool       get isLoggedIn => _user != null;
  String?    get error     => _error;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> checkSession() async {
    _isLoading = true;
    notifyListeners();
    try {
      _user = await _repo.getCurrentUser();
    } catch (_) {
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> login(String email, String password) async {
    _error = null;
    _isLoading = true;
    notifyListeners();
    try {
      _user = await _repo.signInManual(
        email: email, password: password, fullName: '',
      );
      return true;
    } catch (e) {
      _error = '$e'.replaceFirst('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register(String email, String password, String fullName) async {
    _error = null;
    _isLoading = true;
    notifyListeners();
    try {
      _user = await _repo.registerUser(
        email: email, password: password, fullName: fullName,
      );
      return true;
    } catch (e) {
      _error = '$e'.replaceFirst('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _repo.signOut();
    _user = null;
    notifyListeners();
  }

  Future<bool> updateProfile(UserModel updated, {String? newPassword}) async {
    try {
      _user = await _repo.updateProfile(updated, newPassword: newPassword);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}