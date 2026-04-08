enum AuthProviderType { google, manual }

class UserModel {
  final int? id;
  final String fullName;
  final String firstName;
  final String lastName;
  final String username;
  final String email;
  final String phone;
  final String altEmail;
  final String dob;
  final String gender;
  final String pronouns;
  final String avatarPath;
  final AuthProviderType authProvider;
  final String createdAt;

  const UserModel({
    this.id,
    this.fullName = '',
    this.firstName = '',
    this.lastName = '',
    this.username = '',
    this.email = '',
    this.phone = '',
    this.altEmail = '',
    this.dob = '',
    this.gender = '',
    this.pronouns = '',
    this.avatarPath = '',
    this.authProvider = AuthProviderType.manual,
    this.createdAt = '',
  });

  String get displayName {
    if (fullName.trim().isNotEmpty) return fullName.trim();
    final composed = '${firstName.trim()} ${lastName.trim()}'.trim();
    if (composed.isNotEmpty) return composed;
    if (username.trim().isNotEmpty) return username.trim();
    if (email.trim().isNotEmpty) return email.trim();
    return 'User';
  }

  String get initials {
    final parts = displayName.split(' ').where((e) => e.trim().isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) {
      final p = parts.first.trim();
      return p.length >= 2 ? p.substring(0, 2).toUpperCase() : p.substring(0, 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  UserModel copyWith({
    int? id,
    String? fullName,
    String? firstName,
    String? lastName,
    String? username,
    String? email,
    String? phone,
    String? altEmail,
    String? dob,
    String? gender,
    String? pronouns,
    String? avatarPath,
    AuthProviderType? authProvider,
    String? createdAt,
  }) => UserModel(
    id: id ?? this.id,
    fullName: fullName ?? this.fullName,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    username: username ?? this.username,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    altEmail: altEmail ?? this.altEmail,
    dob: dob ?? this.dob,
    gender: gender ?? this.gender,
    pronouns: pronouns ?? this.pronouns,
    avatarPath: avatarPath ?? this.avatarPath,
    authProvider: authProvider ?? this.authProvider,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, dynamic> toDbMap() => {
    if (id != null) 'id': id,
    'full_name': fullName,
    'first_name': firstName,
    'last_name': lastName,
    'username': username,
    'email': email,
    'phone': phone,
    'alt_email': altEmail,
    'dob': dob,
    'gender': gender,
    'pronouns': pronouns,
    'avatar_path': avatarPath,
    'auth_provider': authProvider.name,
    'created_at': createdAt,
  };

  factory UserModel.fromDbMap(Map<String, dynamic> m) {
    final providerRaw = (m['auth_provider'] as String?)?.toLowerCase();
    final provider = providerRaw == AuthProviderType.google.name
        ? AuthProviderType.google
        : AuthProviderType.manual;

    return UserModel(
      id: m['id'] as int?,
      fullName: (m['full_name'] as String?) ?? '',
      firstName: (m['first_name'] as String?) ?? '',
      lastName: (m['last_name'] as String?) ?? '',
      username: (m['username'] as String?) ?? '',
      email: (m['email'] as String?) ?? '',
      phone: (m['phone'] as String?) ?? '',
      altEmail: (m['alt_email'] as String?) ?? '',
      dob: (m['dob'] as String?) ?? '',
      gender: (m['gender'] as String?) ?? '',
      pronouns: (m['pronouns'] as String?) ?? '',
      avatarPath: (m['avatar_path'] as String?) ?? '',
      authProvider: provider,
      createdAt: (m['created_at'] as String?) ?? '',
    );
  }
}