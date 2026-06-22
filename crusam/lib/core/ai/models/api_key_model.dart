// lib/core/agent/models/api_key_model.dart
//
// Represents one issued Agent API key. The raw secret is NEVER persisted —
// only its salted SHA-256 hash. The raw value is shown to the caller exactly
// once, at creation time, the same way GitHub/Stripe show personal access
// tokens.

enum AgentScope {
  readContext,        // GET /v1/context
  writeVoucher,       // add/update/delete voucher rows, save/discard/approve_voucher, set_voucher_field
  writeEmployee,      // add/update/delete_employee
  writeCompanyConfig, // set_company_config, set_company_filter, set_salary_meta, set_month_year, set_days_present
  admin,              // implies every other scope; manage keys / view audit log
}

extension AgentScopeX on AgentScope {
  String get id => switch (this) {
        AgentScope.readContext        => 'read:context',
        AgentScope.writeVoucher       => 'write:voucher',
        AgentScope.writeEmployee      => 'write:employee',
        AgentScope.writeCompanyConfig => 'write:company_config',
        AgentScope.admin              => 'admin',
      };

  static AgentScope? fromId(String id) {
    for (final s in AgentScope.values) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// Maps a tool-executor action name -> the scope required to call it.
/// Keep this in sync with AiToolExecutor's action switch statement.
const Map<String, AgentScope> kActionScopeMap = {
  'update_employee':      AgentScope.writeEmployee,
  'delete_employee':      AgentScope.writeEmployee,
  'add_employee':         AgentScope.writeEmployee,
  'add_voucher_row':      AgentScope.writeVoucher,
  'update_voucher_row':   AgentScope.writeVoucher,
  'delete_voucher_row':   AgentScope.writeVoucher,
  'save_voucher':         AgentScope.writeVoucher,
  'discard_voucher':      AgentScope.writeVoucher,
  'approve_voucher':      AgentScope.writeVoucher,
  'set_voucher_field':    AgentScope.writeVoucher,
  'set_voucher_metadata': AgentScope.writeVoucher,
  'set_company_config':   AgentScope.writeCompanyConfig,
  'set_company_filter':   AgentScope.writeCompanyConfig,
  'set_month_year':       AgentScope.writeCompanyConfig,
  'set_days_present':     AgentScope.writeCompanyConfig,
  'set_salary_meta':      AgentScope.writeCompanyConfig,
};

/// Actions that ALWAYS require human approval inside the app, regardless of
/// the calling key's scope — they're destructive or financially irreversible
/// enough that no API key should trigger them unattended. Expand this set
/// freely (e.g. add 'approve_voucher' or 'delete_voucher_row') if you want
/// stricter defaults.
const Set<String> kAlwaysRequiresApproval = {
  'delete_employee',
  'set_company_config',
};

class ApiKeyModel {
  final int? id;
  final String label;          // human-readable name, e.g. "n8n payroll bot"
  final String keyId;          // public prefix shown in UI, e.g. "ck_8f2a3c91"
  final String secretHash;     // sha256("$salt:$rawSecret")
  final String salt;
  final List<AgentScope> scopes;
  final int rateLimitPerMinute;
  final bool revoked;
  final String createdAt;
  final String? lastUsedAt;
  final String? expiresAt;     // null = never expires

  const ApiKeyModel({
    this.id,
    required this.label,
    required this.keyId,
    required this.secretHash,
    required this.salt,
    required this.scopes,
    this.rateLimitPerMinute = 60,
    this.revoked = false,
    required this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
  });

  bool get isExpired {
    if (expiresAt == null) return false;
    final dt = DateTime.tryParse(expiresAt!);
    return dt != null && DateTime.now().toUtc().isAfter(dt);
  }

  bool hasScope(AgentScope s) =>
      scopes.contains(AgentScope.admin) || scopes.contains(s);

  Map<String, dynamic> toDbMap() => {
        if (id != null) 'id': id,
        'label': label,
        'key_id': keyId,
        'secret_hash': secretHash,
        'salt': salt,
        'scopes': scopes.map((s) => s.id).join(','),
        'rate_limit_per_minute': rateLimitPerMinute,
        'revoked': revoked ? 1 : 0,
        'created_at': createdAt,
        'last_used_at': lastUsedAt,
        'expires_at': expiresAt,
      };

  factory ApiKeyModel.fromDbMap(Map<String, dynamic> m) => ApiKeyModel(
        id: m['id'] as int?,
        label: (m['label'] as String?) ?? '',
        keyId: (m['key_id'] as String?) ?? '',
        secretHash: (m['secret_hash'] as String?) ?? '',
        salt: (m['salt'] as String?) ?? '',
        scopes: ((m['scopes'] as String?) ?? '')
            .split(',')
            .map(AgentScopeX.fromId)
            .whereType<AgentScope>()
            .toList(),
        rateLimitPerMinute: (m['rate_limit_per_minute'] as int?) ?? 60,
        revoked: ((m['revoked'] as int?) ?? 0) == 1,
        createdAt: (m['created_at'] as String?) ?? '',
        lastUsedAt: m['last_used_at'] as String?,
        expiresAt: m['expires_at'] as String?,
      );
}