import 'package:sepot/models/attachment.dart';
import 'package:uuid/uuid.dart';

/// Typy zpráv — odpovídá Rust: MessageType
enum MessageType {
  text,
  image,
  file,
  readReceipt,
  typing,
  keyExchange,
}

/// Stav odeslané (mojí) zprávy — poctivá hranice: read receipts zatím
/// NEjsou (design: default OFF), takže „přečteno" se nezobrazuje.
///   sending   — lokálně zařazeno, čeká na potvrzení relaye (⏱)
///   sent      — relay přijal, příjemce byl offline → v jeho frontě (✓)
///   delivered — doručeno na zařízení příjemce (✓✓)
///   read      — příjemce zprávu přečetl (✓✓ barevně; jen když obě strany
///               mají zapnuté potvrzení přečtení)
///   failed    — odeslání selhalo (✕, klepnout pro opakování)
enum MessageStatus { sending, sent, delivered, read, failed }

/// Zpráva v konverzaci
///
/// Odpovídá Rust: PlaintextMessage + StoredMessage
class Message {
  final String id;
  final String senderId;
  final String recipientId;
  final MessageType type;
  final String? content; // Text zprávy (u příloh volitelný popisek)
  final String? fileName; // Pro typ file
  final int? fileSize;
  final String? replyToId;
  final DateTime timestamp;
  final bool isRead;
  final bool isDelivered;
  final MessageStatus status; // stav odeslání (jen u mých zpráv)
  final int? disappearAfterSeconds; // Mizící zprávy
  final AttachmentMeta? attachment; // image/file — klíč+blob_id+stav
  final DateTime? editedAt; // zpráva byla upravena
  final bool isDeleted; // smazáno pro všechny (tombstone)
  /// Reakce: fingerprint odesílatele reakce → emoji. Prázdné = žádné.
  final Map<String, String> reactions;

  const Message({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.type,
    this.content,
    this.fileName,
    this.fileSize,
    this.replyToId,
    required this.timestamp,
    this.isRead = false,
    this.isDelivered = false,
    this.status = MessageStatus.sent,
    this.disappearAfterSeconds,
    this.attachment,
    this.editedAt,
    this.isDeleted = false,
    this.reactions = const {},
  });

  /// Vytvoř textovou zprávu
  factory Message.text({
    required String senderId,
    required String recipientId,
    required String content,
    String? replyToId,
    int? disappearAfterSeconds,
    MessageStatus status = MessageStatus.sending,
  }) {
    return Message(
      id: const Uuid().v4(),
      senderId: senderId,
      recipientId: recipientId,
      type: MessageType.text,
      content: content,
      replyToId: replyToId,
      timestamp: DateTime.now(),
      status: status,
      disappearAfterSeconds: disappearAfterSeconds,
    );
  }

  /// Vytvoř zprávu s přílohou (obrázek/dokument dle meta.isImage)
  factory Message.attachment({
    required String senderId,
    required String recipientId,
    required AttachmentMeta attachment,
    String? caption,
    String? id,
    int? disappearAfterSeconds,
    MessageStatus status = MessageStatus.sending,
  }) {
    return Message(
      id: id ?? const Uuid().v4(),
      senderId: senderId,
      recipientId: recipientId,
      type: attachment.isImage ? MessageType.image : MessageType.file,
      content: caption,
      fileName: attachment.name,
      fileSize: attachment.size,
      timestamp: DateTime.now(),
      attachment: attachment,
      status: status,
      disappearAfterSeconds: disappearAfterSeconds,
    );
  }

  /// Vytvoř read receipt
  factory Message.readReceipt({
    required String senderId,
    required String recipientId,
    required String messageId,
  }) {
    return Message(
      id: const Uuid().v4(),
      senderId: senderId,
      recipientId: recipientId,
      type: MessageType.readReceipt,
      content: messageId,
      timestamp: DateTime.now(),
    );
  }

  /// Kopie s aktualizovanými hodnotami
  Message copyWith({
    String? content,
    bool? isRead,
    bool? isDelivered,
    MessageStatus? status,
    AttachmentMeta? attachment,
    DateTime? editedAt,
    bool? isDeleted,
    Map<String, String>? reactions,
  }) {
    return Message(
      id: id,
      senderId: senderId,
      recipientId: recipientId,
      type: type,
      content: content ?? this.content,
      fileName: fileName,
      fileSize: fileSize,
      replyToId: replyToId,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      isDelivered: isDelivered ?? this.isDelivered,
      status: status ?? this.status,
      disappearAfterSeconds: disappearAfterSeconds,
      attachment: attachment ?? this.attachment,
      editedAt: editedAt ?? this.editedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      reactions: reactions ?? this.reactions,
    );
  }

  /// Má zpráva mizet?
  bool get isDisappearing => disappearAfterSeconds != null;

  /// Je zpráva odeslána mnou?
  bool isMine(String myId) => senderId == myId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'recipientId': recipientId,
        'type': type.name,
        'content': content,
        'fileName': fileName,
        'fileSize': fileSize,
        'replyToId': replyToId,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
        'isDelivered': isDelivered,
        'status': status.name,
        'disappearAfterSeconds': disappearAfterSeconds,
        'attachment': attachment?.toJson(),
        'editedAt': editedAt?.toIso8601String(),
        'isDeleted': isDeleted,
        'reactions': reactions,
      };

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      recipientId: json['recipientId'] as String,
      type: MessageType.values.byName(json['type'] as String),
      content: json['content'] as String?,
      fileName: json['fileName'] as String?,
      fileSize: json['fileSize'] as int?,
      replyToId: json['replyToId'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: json['isRead'] as bool? ?? false,
      isDelivered: json['isDelivered'] as bool? ?? false,
      // Legacy záznamy bez 'status' → odvoď z isDelivered
      status: MessageStatus.values.asNameMap()[json['status'] as String?] ??
          ((json['isDelivered'] as bool? ?? false)
              ? MessageStatus.delivered
              : MessageStatus.sent),
      disappearAfterSeconds: json['disappearAfterSeconds'] as int?,
      attachment: json['attachment'] == null
          ? null
          : AttachmentMeta.fromJson(
              json['attachment'] as Map<String, dynamic>),
      editedAt: json['editedAt'] == null
          ? null
          : DateTime.parse(json['editedAt'] as String),
      isDeleted: json['isDeleted'] as bool? ?? false,
      reactions: (json['reactions'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          const {},
    );
  }
}
