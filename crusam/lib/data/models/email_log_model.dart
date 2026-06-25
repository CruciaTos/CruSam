// lib/data/models/email_log_model.dart
//
// One row per email send attempt, for any document type the app sends.
// entity_type/entity_id point back at the source record — e.g.
// entity_type='invoice', entity_id=<vouchers.id> for Phase 1.

enum EmailLogStatus {
  pending,
  sent,
  failed;

  static EmailLogStatus fromString(String s) => EmailLogStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => EmailLogStatus.pending,
      );
}

class EmailLogModel {
  final int?            id;
  final String          entityType;
  final int             entityId;
  final String          recipientTo;
  final String          recipientCc;
  final String          subject;
  final EmailLogStatus  status;
  final String?         gmailMessageId;
  final String?         gmailThreadId;
  final String?         errorMessage;
  final String          sentBy;
  final String          attemptedAt;
  final String?         sentAt;

  const EmailLogModel({
    this.id,
    required this.entityType,
    required this.entityId,
    required this.recipientTo,
    this.recipientCc    = '',
    required this.subject,
    this.status         = EmailLogStatus.pending,
    this.gmailMessageId,
    this.gmailThreadId,
    this.errorMessage,
    this.sentBy         = '',
    this.attemptedAt    = '',
    this.sentAt,
  });

  EmailLogModel copyWith({
    int?           id,
    EmailLogStatus? status,
    String?        gmailMessageId,
    String?        gmailThreadId,
    String?        errorMessage,
    String?        sentAt,
  }) => EmailLogModel(
        id:             id ?? this.id,
        entityType:     entityType,
        entityId:       entityId,
        recipientTo:    recipientTo,
        recipientCc:    recipientCc,
        subject:        subject,
        status:         status ?? this.status,
        gmailMessageId: gmailMessageId ?? this.gmailMessageId,
        gmailThreadId:  gmailThreadId  ?? this.gmailThreadId,
        errorMessage:   errorMessage   ?? this.errorMessage,
        sentBy:         sentBy,
        attemptedAt:    attemptedAt,
        sentAt:         sentAt ?? this.sentAt,
      );

  Map<String, dynamic> toDbMap() => {
        if (id != null) 'id': id,
        'entity_type':      entityType,
        'entity_id':        entityId,
        'recipient_to':     recipientTo,
        'recipient_cc':     recipientCc,
        'subject':          subject,
        'status':           status.name,
        'gmail_message_id': gmailMessageId,
        'gmail_thread_id':  gmailThreadId,
        'error_message':    errorMessage,
        'sent_by':          sentBy,
        if (attemptedAt.isNotEmpty) 'attempted_at': attemptedAt,
        'sent_at':          sentAt,
      };

  factory EmailLogModel.fromDbMap(Map<String, dynamic> m) => EmailLogModel(
        id:             m['id'] as int?,
        entityType:     (m['entity_type']      as String?) ?? '',
        entityId:       (m['entity_id']        as int?)    ?? 0,
        recipientTo:    (m['recipient_to']     as String?) ?? '',
        recipientCc:    (m['recipient_cc']     as String?) ?? '',
        subject:        (m['subject']          as String?) ?? '',
        status:         EmailLogStatus.fromString((m['status'] as String?) ?? 'pending'),
        gmailMessageId: m['gmail_message_id']  as String?,
        gmailThreadId:  m['gmail_thread_id']   as String?,
        errorMessage:   m['error_message']     as String?,
        sentBy:         (m['sent_by']          as String?) ?? '',
        attemptedAt:    (m['attempted_at']     as String?) ?? '',
        sentAt:         m['sent_at']           as String?,
      );
}
