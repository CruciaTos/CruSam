import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/user_model.dart';
import 'auth_repository.dart';
import 'package:crusam/data/db/database_helper.dart';

class AuthRepositoryImpl implements AuthRepository {
  static const _salt = 'crusam_aarti_2025_secure';

  String _hash(String password) {
    final bytes = utf8.encode('$_salt:$password');
    return sha256.convert(bytes).toString();
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    final id = await DatabaseHelper.instance.getSessionUserId();
    if (id == null) return null;
    final map = await DatabaseHelper.instance.getUserById(id);
    if (map == null) return null;
    return UserModel.fromDbMap(map);
  }

  @override
  Future<UserModel> signInWithGoogle() {
    throw UnimplementedError('Google sign-in not supported on desktop');
  }

  @override
  Future<UserModel> signInManual({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final map = await DatabaseHelper.instance.getUserByEmail(email);
    if (map == null) throw Exception('No account found with this email.');
    final stored = map['password_hash'] as String? ?? '';
    if (stored != _hash(password)) throw Exception('Incorrect password. Please try again.');
    final user = UserModel.fromDbMap(map);
    await DatabaseHelper.instance.setSessionUserId(user.id!);
    return user;
  }

  Future<UserModel> registerUser({
    required String email,
    required String fullName,
    required String password,
  }) async {
    final existing = await DatabaseHelper.instance.getUserByEmail(email);
    if (existing != null) throw Exception('An account with this email already exists.');
    final now = DateTime.now().toIso8601String();
    final data = <String, dynamic>{
      'full_name': fullName,
      'first_name': fullName.split(' ').first,
      'last_name': fullName.split(' ').skip(1).join(' '),
      'email': email,
      'auth_provider': AuthProviderType.manual.name,
      'password_hash': _hash(password),
      'created_at': now,
    };
    final id = await DatabaseHelper.instance.insertUser(data);
    await DatabaseHelper.instance.setSessionUserId(id);
    return UserModel(
      id: id,
      fullName: fullName,
      email: email,
      authProvider: AuthProviderType.manual,
      createdAt: now,
    );
  }

  @override
  Future<void> signOut() async {
    await DatabaseHelper.instance.setSessionUserId(null);
  }

  @override
  Future<UserModel> updateProfile(UserModel user, {String? newPassword}) async {
    final data = user.toDbMap();
    if (newPassword != null && newPassword.isNotEmpty) {
      data['password_hash'] = _hash(newPassword);
    }
    await DatabaseHelper.instance.updateUser(user.id!, data);
    return user;
  }
}