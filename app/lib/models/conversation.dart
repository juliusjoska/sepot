import 'package:sepot/models/message.dart';

/// Konverzace s kontaktem
///
/// Odpovídá Rust: Conversation
class Conversation {
  final String contactId;
  final List<Message> messages;
  DateTime lastActivity;
  int? disappearAfterSeconds; // Globální nastavení mizících zpráv

  /// Ztlumení, archivace a připnutí — čistě LOKÁLNÍ (neopouští zařízení).
  bool muted;
  DateTime? mutedUntil; // null + muted = navždy; jinak dočasně
  bool archived;
  bool pinned; // připnutý nahoře v seznamu chatů (lokální)

  Conversation({
    required this.contactId,
    List<Message>? messages,
    DateTime? lastActivity,
    this.disappearAfterSeconds,
    this.muted = false,
    this.mutedUntil,
    this.archived = false,
    this.pinned = false,
  })  : messages = messages ?? [],
        lastActivity = lastActivity ?? DateTime.now();

  /// Je konverzace teď ztlumená? (dočasné ztlumení sama vyprší)
  bool get isMuted =>
      muted && (mutedUntil == null || mutedUntil!.isAfter(DateTime.now()));

  /// Poslední zpráva
  Message? get lastMessage => messages.isEmpty ? null : messages.last;

  /// Počet nepřečtených zpráv
  int unreadCount(String myId) {
    return messages
        .where((m) => !m.isRead && m.senderId != myId)
        .length;
  }

  /// Přidej zprávu. Vrací false, když už zpráva s tímhle id v konverzaci je.
  ///
  /// Id zprávy nese odesílatel (pole `id` na drátě), takže opakované doručení
  /// téhož obsahu — retry odesílatele po výpadku spojení nebo redelivery
  /// z fronty relaye — nesmí založit druhou bublinu.
  bool addMessage(Message message) {
    if (messages.any((m) => m.id == message.id)) return false;
    messages.add(message);
    lastActivity = DateTime.now();
    return true;
  }

  /// Nahraď zprávu se stejným id (změna stavu přílohy, doručenka…).
  /// Neexistující id se tiše ignoruje (zpráva mohla být smazána).
  ///
  /// Přečtení je jednosměrné: aktualizace nesmí vrátit už přečtenou zprávu
  /// mezi nepřečtené. Volající často drží kopii zprávy načtenou před
  /// otevřením chatu (stahování přílohy, dodatečné odeslání) a bez téhle
  /// pojistky by zápis po návratu ze stahování obnovil odznak nepřečtených.
  void updateMessage(Message message) {
    final index = messages.indexWhere((m) => m.id == message.id);
    if (index < 0) return;
    messages[index] = messages[index].isRead && !message.isRead
        ? message.copyWith(isRead: true)
        : message;
  }

  /// Označ všechny zprávy jako přečtené
  void markAllRead(String myId) {
    for (var i = 0; i < messages.length; i++) {
      if (!messages[i].isRead && messages[i].senderId != myId) {
        messages[i] = messages[i].copyWith(isRead: true);
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'contactId': contactId,
        'messages': messages.map((m) => m.toJson()).toList(),
        'lastActivity': lastActivity.toIso8601String(),
        'disappearAfterSeconds': disappearAfterSeconds,
        'muted': muted,
        'mutedUntil': mutedUntil?.toIso8601String(),
        'archived': archived,
        'pinned': pinned,
      };

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      contactId: json['contactId'] as String,
      messages: (json['messages'] as List<dynamic>?)
              ?.map((m) => Message.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      lastActivity: DateTime.parse(json['lastActivity'] as String),
      disappearAfterSeconds: json['disappearAfterSeconds'] as int?,
      // Defaulty — legacy JSON bez těchto klíčů musí projít
      muted: json['muted'] as bool? ?? false,
      mutedUntil: json['mutedUntil'] == null
          ? null
          : DateTime.parse(json['mutedUntil'] as String),
      archived: json['archived'] as bool? ?? false,
      pinned: json['pinned'] as bool? ?? false,
    );
  }
}
