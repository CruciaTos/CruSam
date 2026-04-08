import '../models/user_model.dart';

abstract class AuthRepository {
  Future<UserModel?> getCurrentUser();

  Future<UserModel> signInWithGoogle();

  Future<UserModel> signInManual({
    required String email,
    required String password,
    required String fullName,
  });

  Future<void> signOut();

  Future<UserModel> updateProfile(UserModel user, {String? newPassword});
}