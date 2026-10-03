import 'package:sepot/models/attachment.dart';
import 'package:sepot/models/call_log.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/models/poll.dart';
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

/// Stav odeslané (mojí) zprávy. Potvrzení přečtení je volitelné (default
/// vypnuto) a reciproční — kdo ho nesdílí, „přečteno" neuvidí ani sám.
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
  /// Kdy mou zprávu dostal / přečetl který příjemce (fingerprint → čas).
  /// 1:1 má nejvýš jeden záznam, skupina jeden na člena — z toho se
  /// skládá „Info o zprávě". Čas je z hodin příjemce (pole `ts` doručenky).
  final Map<String, DateTime> deliveredTo;
  final Map<String, DateTime> readBy;

  /// Anketa (textová zpráva, `content` nese záložní text pro starší appky).
  final Poll? poll;

  /// Fingerprinty lidí zmíněných přes @ ve skupině — zmínka projde i přes
  /// ztlumení skupiny.
  final List<String> mentions;

  /// Lokální záznam hovoru — taková zpráva nemá text ani přílohu.
  final CallLog? callLog;

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
    this.deliveredTo = const {},
    this.readBy = const {},
    this.poll,
    this.mentions = const [],
    this.callLog,
  });

  /// Vytvoř textovou zprávu
  factory Message.text({
    required String senderId,
    required String recipientId,
    required String content,
    String? replyToId,
    int? disappearAfterSeconds,
    MessageStatus status = MessageStatus.sending,
    Poll? poll,
    List<String> mentions = const [],
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
      poll: poll,
      mentions: mentions,
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
    Map<String, DateTime>? deliveredTo,
    Map<String, DateTime>? readBy,
    Poll? poll,
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
      deliveredTo: deliveredTo ?? this.deliveredTo,
      readBy: readBy ?? this.readBy,
      poll: poll ?? this.poll,
      mentions: mentions,
      callLog: callLog,
    );
  }

  /// Nejdřívější doručení / přečtení napříč příjemci (null = zatím nic).
  DateTime? get firstDeliveredAt => _earliest(deliveredTo.values);
  DateTime? get firstReadAt => _earliest(readBy.values);

  static DateTime? _earliest(Iterable<DateTime> times) => times.isEmpty
      ? null
      : times.reduce((a, b) => a.isBefore(b) ? a : b);

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
        'deliveredTo': _timesToJson(deliveredTo),
        'readBy': _timesToJson(readBy),
        'poll': poll?.toJson(),
        if (mentions.isNotEmpty) 'mentions': mentions,
        if (callLog != null) 'call': callLog!.toJson(),
      };

  static Map<String, int> _timesToJson(Map<String, DateTime> times) =>
      times.map((k, v) => MapEntry(k, v.millisecondsSinceEpoch));

  /// Tolerantní čtení: starší záznamy pole nemají, vadné položky se
  /// přeskočí — kvůli nim nesmí spadnout načtení celé konverzace.
  static Map<String, DateTime> _timesFromJson(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.key is String && e.value is int)
          e.key as String: DateTime.fromMillisecondsSinceEpoch(e.value as int),
    };
  }

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
      deliveredTo: _timesFromJson(json['deliveredTo']),
      readBy: _timesFromJson(json['readBy']),
      poll: Poll.fromJson(json['poll']),
      mentions: mentionsFromWire(json['mentions']),
      callLog: CallLog.fromJson(json['call']),
    );
  }
}

/// Zmínky z drátu i z úložiště: jen řetězce a rozumný počet — obálka od
/// cizího klienta nesmí rozbít zprávu ani nafouknout úložiště.
List<String> mentionsFromWire(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<String>().take(Group.maxMembers).toList();
}
