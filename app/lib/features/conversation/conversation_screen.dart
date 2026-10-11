import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:intl/intl.dart';
import 'package:sepot/core/calls/call_controller.dart';
import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/l10n/error_messages.dart';
import 'package:sepot/core/l10n/l10n.dart';
import 'package:sepot/core/services/image_processor.dart';
import 'package:sepot/core/theme/app_theme.dart';
import 'package:sepot/core/utils/text_fold.dart';
import 'package:sepot/features/calls/call_log_text.dart';
import 'package:sepot/features/conversation/chat_actions.dart';
import 'package:sepot/features/conversation/forward_sheet.dart';
import 'package:sepot/features/conversation/widgets/attachment_content.dart';
import 'package:sepot/features/conversation/widgets/create_poll_sheet.dart';
import 'package:sepot/features/conversation/widgets/poll_content.dart';
import 'package:sepot/features/profile/profile_widgets.dart';
import 'package:sepot/models/contact.dart';
import 'package:sepot/models/conversation.dart';
import 'package:sepot/models/group.dart';
import 'package:sepot/models/identity.dart';
import 'package:sepot/features/conversation/photo_preview_screen.dart';
import 'package:sepot/models/call_log.dart';
import 'package:sepot/models/message.dart';
import 'package:sepot/providers/contacts_provider.dart';
import 'package:sepot/providers/drafts_provider.dart';
import 'package:sepot/providers/conversations_provider.dart';
import 'package:sepot/providers/groups_provider.dart';
import 'package:sepot/providers/identity_provider.dart';
import 'package:sepot/providers/messaging_provider.dart';
import 'package:sepot/providers/storage_provider.dart';
import 'package:sepot/widgets/avatar.dart';
import 'package:sepot/widgets/e2e_badge.dart';
import 'package:sepot/widgets/glass.dart';
import 'package:sepot/widgets/message_status_icon.dart';

enum _AttachAction { gallery, camera, document, poll }

/// Chat obrazovka — zprávy s kontaktem
class ConversationScreen extends ConsumerStatefulWidget {
  final String contactId;

  const ConversationScreen({
    super.key,
    required this.contactId,
    this.startSearch = false,
  });

  /// Otevřít rovnou v režimu hledání (akce „Hledat“ z profilu).
  final bool startSearch;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen>
    with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  bool _isSending = false;
  Message? _replyingTo; // aktivní odpověď (nad inputem)
  String? _editingId; // id právě upravované zprávy

  /// Poznámky pro sebe: nic nejde do sítě, takže ani „píše…“, reakce,
  /// ankety, fajfky nebo smazání pro všechny.
  bool get _isNotes => ConversationsNotifier.isNotes(widget.contactId);

  // @zmínky ve skupině: kdo byl vložen z nabídky (fingerprint → jméno)
  // a rozepsaný dotaz za „@“ před kurzorem (null = nabídka zavřená).
  final _mentions = <String, String>{};
  int? _mentionStart;
  String _mentionQuery = '';
  static const _mentionSuggestionLimit = 5;

  // Rozepsaná zpráva: ukládá se s krátkým zpožděním, aby přežila i zabití
  // appky. Při úpravě staré zprávy se koncept odloží a pak vrátí.
  late final DraftsNotifier _drafts;
  Timer? _draftTimer;
  String? _draftBeforeEdit;
  static const _draftSaveDelay = Duration(milliseconds: 800);

  // Nahrávání hlasové zprávy
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  Duration _recordDur = Duration.zero;
  Timer? _recordTimer;
  String? _recordPath;

  // Hledání v konverzaci: shody od nejnovější, _matchIndex = aktuální.
  bool _searching = false;
  List<String> _matches = const [];
  int _matchIndex = 0;

  // Řádek „N nových zpráv“ — zachycený PŘED označením za přečtené.
  String? _firstUnreadId;
  int _unreadAtOpen = 0;

  // Tlačítko „dolů“: počet zpráv, které přišly, když jsem byl výš.
  bool _showJump = false;
  int _messageCount = 0;
  int _awayFrom = 0;

  // Klíče bublin pro skok na zprávu (citace, hledání) a krátké zvýraznění.
  final _keys = <String, GlobalKey>{};
  String? _flashId;
  Timer? _flashTimer;

  /// Malá sada emoji pro rychlé reakce.
  static const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  /// Vzdálenost od konce, od které se ukáže „dolů“.
  static const _jumpThreshold = 320.0;

  /// Zprávy od stejného člověka do téhle pauzy tvoří jeden blok.
  static const _clusterGap = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searching = widget.startSearch;
    _drafts = ref.read(draftsProvider.notifier);
    _restoreDraft();
    _messageController.addListener(_scheduleDraftSave);
    _conversations = ref.read(conversationsProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _captureUnreadAndMark());
  }

  /// Notifier zachycený v initState: v dispose už `ref` použít nejde.
  late final ConversationsNotifier _conversations;

  /// Zpráva, která přijde do otevřeného chatu, je přečtená, jen když ji
  /// uživatel opravdu vidí: appka v popředí a tahle obrazovka navrchu
  /// (ne pod profilem kontaktu nebo náhledem fotky).
  bool get _isSeenNow =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      (_route?.isCurrent ?? false);

  // Route uložená v didChangeDependencies: lifecycle callback může přijít
  // i ve chvíli, kdy je element už deaktivovaný a hledat předka nesmí.
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  void _markIfSeen() {
    if (!mounted || !_isSeenNow) return;
    _conversations.markAsRead(widget.contactId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Zprávy, které přišly se zhasnutým displejem nad otevřeným chatem,
    // uživatel uvidí až po návratu do appky.
    if (state == AppLifecycleState.resumed) _markIfSeen();
  }

  /// Zapamatuje si první nepřečtenou zprávu a teprve pak konverzaci označí
  /// za přečtenou — jinak by řádek „nové zprávy“ nikdy nebylo kam dát.
  Future<void> _captureUnreadAndMark() async {
    final myId = ref.read(identityProvider).valueOrNull?.id ?? '';
    final conv =
        await ref.read(storageProvider).loadConversation(widget.contactId);
    final unread =
        conv?.messages.where((m) => !m.isRead && !m.isMine(myId)).toList() ??
            const <Message>[];
    if (mounted && unread.isNotEmpty) {
      setState(() {
        _firstUnreadId = unread.first.id;
        _unreadAtOpen = unread.length;
      });
    }
    await ref.read(conversationsProvider.notifier).markAsRead(widget.contactId);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final away = _scrollController.offset > _jumpThreshold;
    if (away == _showJump) return;
    setState(() {
      _showJump = away;
      _awayFrom = _messageCount;
    });
  }

  Future<void> _restoreDraft() async {
    final draft = (await ref.read(draftsProvider.future))[widget.contactId];
    if (!mounted || draft == null || _messageController.text.isNotEmpty) {
      return;
    }
    _messageController.text = draft;
  }

  void _scheduleDraftSave() {
    if (_editingId != null) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(_draftSaveDelay, _saveDraft);
  }

  void _saveDraft() {
    if (_editingId != null) return;
    _drafts.set(widget.contactId, _messageController.text);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Odchod z chatu: všechno, co bylo na obrazovce, je přečtené – i zprávy
    // dorazivší těsně před odchodem, které listener nestihl označit.
    _conversations.markAsRead(widget.contactId);
    _draftTimer?.cancel();
    // Odchod z chatu uprostřed úpravy = koncept je ten odložený, ne text
    // upravované zprávy.
    _drafts.set(widget.contactId,
        _editingId != null ? (_draftBeforeEdit ?? '') : _messageController.text);
    _messageController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _recordTimer?.cancel();
    _flashTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/chats');
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider).valueOrNull ?? [];
    final contact = contacts
        .where((c) => c.publicIdentity.id == widget.contactId)
        .firstOrNull;
    final conversationAsync = ref.watch(conversationProvider(widget.contactId));
    // Nová příchozí zpráva v otevřeném chatu se rovnou čte; jinak by po
    // návratu do seznamu svítila jako nepřečtená.
    // První načtení vynechá: to obslouží _captureUnreadAndMark, které si
    // nejdřív zapamatuje řádek „N nových zpráv“.
    ref.listen(conversationProvider(widget.contactId), (prev, next) {
      if (prev?.valueOrNull == null) return;
      final conv = next.valueOrNull;
      final myId = ref.read(identityProvider).valueOrNull?.id;
      if (conv == null || myId == null || conv.unreadCount(myId) == 0) return;
      _markIfSeen();
    });
    final identity = ref.watch(identityProvider).valueOrNull;
    // Skupinová konverzace: contactId == gid
    final group = ref.watch(groupProvider(widget.contactId)).valueOrNull;

    // Fingerprint → jméno pro popisky autorů. Členy, kteří ještě nejsou
    // v kontaktech (roster je zakládá až s první zprávou), zkrátíme na id.
    String autorJmeno(String fingerprint) {
      if (fingerprint == identity?.id) return context.l10n.groupsYou;
      final jmeno = contacts
          .where((c) => c.publicIdentity.id == fingerprint)
          .firstOrNull
          ?.displayName;
      if (jmeno == null) {
        return 'SEP-${fingerprint.substring(0, fingerprint.length.clamp(0, 10))}';
      }
      return jmeno.isEmpty ? context.l10n.commonUnknownContact : jmeno;
    }

    final Widget bottom;
    if (group?.left == true) {
      bottom = _buildBanner(context.l10n.groupsLeftBanner);
    } else if (contact?.blocked == true) {
      bottom = _buildBanner(
        context.l10n.chatBlockedBanner,
        action: TextButton(
          onPressed: () => setContactBlocked(context, ref, contact!, false),
          child: Text(context.l10n.chatUnblock),
        ),
      );
    } else {
      bottom = _buildComposer();
    }

    _updateMatches(conversationAsync.valueOrNull?.messages ?? const []);
    final writers =
        ref.watch(typingProvider).valueOrNull?[widget.contactId] ?? const {};
    final header = _searching
        ? _buildSearchHeader()
        : _isNotes
            ? _buildNotesHeader()
            : group != null
                ? _buildGroupHeader(group, autorJmeno, writers)
                : _buildContactHeader(contact, typing: writers.isNotEmpty);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: SepotColors.background,
        body: ChatWallpaper(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: conversationAsync.when(
                        data: (conversation) => _buildMessageList(
                          conversation?.messages ?? const [],
                          identity,
                          group: group,
                          autorJmeno: autorJmeno,
                          typing: writers.isNotEmpty,
                        ),
                        loading: () => const Center(
                          child: CircularProgressIndicator(
                              color: SepotColors.ember),
                        ),
                        error: (e, _) =>
                            Center(child: Text(describeError(context.l10n, e))),
                      ),
                    ),
                    Positioned(top: 0, left: 0, right: 0, child: header),
                    if (_showJump)
                      Positioned(
                        right: 14,
                        bottom: 10,
                        child: _buildJumpButton(conversationAsync.valueOrNull,
                            identity?.id ?? ''),
                      ),
                  ],
                ),
              ),
              bottom,
            ],
          ),
        ),
      ),
    );
  }

  // ── Hlavička ──────────────────────────────────────────────────────────

  Widget _buildHeaderFrame({required List<Widget> children}) {
    return GlassSurface(
      border: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: SepotColors.glassBorder)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              4, MediaQuery.paddingOf(context).top + 6, 4, 8),
          child: SizedBox(height: 50, child: Row(children: children)),
        ),
      ),
    );
  }

  Widget _backButton() => IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: _goBack,
      );

  Widget _searchButton() => IconButton(
        tooltip: context.l10n.chatSearchHint,
        icon: const Icon(Icons.search_rounded, color: SepotColors.textSecondary),
        onPressed: () => setState(() {
          _searching = true;
          _searchController.clear();
          _matches = const [];
          _matchIndex = 0;
        }),
      );

  /// Klepnutí na jméno/avatar otevře profil (jako v ostatních messengerech).
  Widget _headerIdentity({
    required Widget avatar,
    required String title,
    required Widget subtitle,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Semantics(
        button: true,
        label: context.l10n.chatOpenProfile,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                avatar,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 1),
                      subtitle,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Podtitulek „píše…“ — přebíjí stav ověření, dokud protistrana píše.
  Widget _typingLabel(String text) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: SepotColors.ember),
      );

  void _startCall(Contact contact, {required bool video}) {
    final call = ref.read(callProvider);
    if (call.busy) {
      context.push('/call');
      return;
    }
    ref.read(callProvider.notifier).startCall(contact, video: video);
  }

  Widget _buildNotesHeader() {
    return _buildHeaderFrame(children: [
      _backButton(),
      _headerIdentity(
        avatar: const NotesAvatar(size: 40),
        title: context.l10n.notesTitle,
        subtitle: Text(
          context.l10n.notesSubtitle,
          style: const TextStyle(
              fontSize: 12, color: SepotColors.textSecondary),
        ),
        onTap: () {},
      ),
      _searchButton(),
    ]);
  }

  Widget _buildContactHeader(Contact? contact, {bool typing = false}) {
    final name = (contact == null || contact.displayName.isEmpty)
        ? context.l10n.commonUnknownContact
        : contact.displayName;
    final verified = contact?.verified ?? false;
    return _buildHeaderFrame(children: [
      _backButton(),
      _headerIdentity(
        avatar: SepotAvatar(
            name: name, seed: widget.contactId, size: 40, verified: verified),
        title: name,
        // Stav ověření místo syrového ID (UX-FLOWS §3.1)
        subtitle: typing
            ? _typingLabel(context.l10n.chatTyping)
            : Text(
                verified
                    ? context.l10n.verifyVerified
                    : context.l10n.verifyUnverified,
                style: TextStyle(
                  fontSize: 12,
                  color:
                      verified ? SepotColors.sage : SepotColors.textSecondary,
                ),
              ),
        onTap: () => _openProfile('/contact/${widget.contactId}'),
      ),
      if (contact != null && !contact.blocked) ...[
        IconButton(
          tooltip: context.l10n.callVoice,
          icon: const Icon(Icons.call_outlined,
              color: SepotColors.textSecondary),
          onPressed: () => _startCall(contact, video: false),
        ),
        IconButton(
          tooltip: context.l10n.callVideo,
          icon: const Icon(Icons.videocam_outlined,
              color: SepotColors.textSecondary),
          onPressed: () => _startCall(contact, video: true),
        ),
      ],
      _searchButton(),
      if (contact != null)
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: SepotColors.textSecondary),
          onSelected: (value) {
            switch (value) {
              case 'profile':
                _openProfile('/contact/${widget.contactId}');
              case 'disappearing':
                configureDisappearing(context, ref, widget.contactId);
              case 'block':
                setContactBlocked(context, ref, contact, true);
              case 'unblock':
                setContactBlocked(context, ref, contact, false);
              case 'report':
                reportAndBlock(context, ref, contact);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
                value: 'profile', child: Text(context.l10n.chatOpenProfile)),
            PopupMenuItem(
                value: 'disappearing',
                child: Text(context.l10n.chatDisappearingMessages)),
            const PopupMenuDivider(),
            if (contact.blocked)
              PopupMenuItem(
                  value: 'unblock',
                  child: Text(context.l10n.chatMenuUnblockContact))
            else ...[
              PopupMenuItem(
                  value: 'block',
                  child: Text(context.l10n.chatMenuBlockContact)),
              PopupMenuItem(
                value: 'report',
                child: Text(context.l10n.reportAndBlock,
                    style: const TextStyle(color: SepotColors.error)),
              ),
            ],
          ],
        ),
    ]);
  }

  /// Skupinová hlavička: jména členů místo stavu
  /// ověření — ověřují se jednotliví členové, skupina safety number nemá.
  Widget _buildGroupHeader(Group group, String Function(String) autorJmeno,
      Set<String> writers) {
    final myId = ref.read(identityProvider).valueOrNull?.id;
    final jmena = [
      if (group.memberIds.contains(myId)) context.l10n.groupsYou,
      for (final f in group.memberIds)
        if (f != myId) autorJmeno(f).split(' ').first,
    ].join(', ');
    return _buildHeaderFrame(children: [
      _backButton(),
      _headerIdentity(
        avatar: SepotGroupAvatar(seed: group.id, size: 40),
        title: group.name,
        subtitle: writers.isNotEmpty
            ? _typingLabel(writers.length == 1
                ? context.l10n.chatTypingNamed(
                    autorJmeno(writers.first).split(' ').first)
                : context.l10n.chatTypingSeveral)
            : Text(
                group.left ? context.l10n.groupsYouLeftGroup : jmena,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: SepotColors.textSecondary),
              ),
        onTap: () => _openProfile('/group/${group.id}'),
      ),
      _searchButton(),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: SepotColors.textSecondary),
        onSelected: (value) async {
          switch (value) {
            case 'profile':
              _openProfile('/group/${group.id}');
            case 'add':
              context.push('/group/${group.id}/add');
            case 'disappearing':
              configureDisappearing(context, ref, widget.contactId);
            case 'leave':
              if (await leaveGroup(context, ref, group) && mounted) _goBack();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
              value: 'profile', child: Text(context.l10n.groupsProfile)),
          if (!group.left) ...[
            // Stejné pravidlo jako v profilu skupiny: přidává správce, ostatní
            // jen dokud je ve skupině někdo s verzí bez správců.
            if (group.isAdmin(myId ?? '') || !group.isEnforced(myId ?? ''))
              PopupMenuItem(
                  value: 'add', child: Text(context.l10n.groupsAddMembers)),
            PopupMenuItem(
                value: 'disappearing',
                child: Text(context.l10n.chatDisappearingMessages)),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'leave',
              child: Text(context.l10n.groupsLeave,
                  style: const TextStyle(color: SepotColors.error)),
            ),
          ],
        ],
      ),
    ]);
  }

  Widget _buildSearchHeader() {
    final total = _matches.length;
    final hasQuery = _searchController.text.trim().isNotEmpty;
    return _buildHeaderFrame(children: [
      IconButton(
        tooltip: context.l10n.commonCancel,
        icon: const Icon(Icons.close_rounded),
        onPressed: () => setState(() {
          _searching = false;
          _searchController.clear();
          _matches = const [];
        }),
      ),
      Expanded(
        child: TextField(
          controller: _searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() => _matchIndex = 0),
          onSubmitted: (_) {
            if (_matches.isNotEmpty) _goToMatch(_matchIndex);
          },
          decoration: InputDecoration(
            hintText: context.l10n.chatSearchHint,
            filled: true,
            fillColor: SepotColors.surface,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: SepotColors.ember, width: 1.5),
            ),
          ),
        ),
      ),
      if (hasQuery)
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            total == 0
                ? context.l10n.chatSearchNoMatches
                : context.l10n.chatSearchCounter(_matchIndex + 1, total),
            style:
                const TextStyle(fontSize: 12, color: SepotColors.textSecondary),
          ),
        ),
      // Shody jsou od nejnovější: „nahoru“ = starší = vyšší index.
      IconButton(
        tooltip: context.l10n.chatSearchOlder,
        icon: const Icon(Icons.keyboard_arrow_up_rounded),
        onPressed: _matchIndex < total - 1
            ? () => _goToMatch(_matchIndex + 1)
            : null,
      ),
      IconButton(
        tooltip: context.l10n.chatSearchNewer,
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
        onPressed: _matchIndex > 0 ? () => _goToMatch(_matchIndex - 1) : null,
      ),
    ]);
  }

  /// Profil otevřený z chatu se „Zprávou“ jen vrací; „Hledat“ vrátí
  /// požadavek zapnout tady hledání.
  Future<void> _openProfile(String path) async {
    final result = await context.push<ProfileResult>('$path?from=chat');
    if (result == ProfileResult.openSearch && mounted) {
      setState(() {
        _searching = true;
        _searchController.clear();
        _matchIndex = 0;
      });
    }
  }

  void _goToMatch(int index) {
    if (index < 0 || index >= _matches.length) return;
    setState(() => _matchIndex = index);
    _scrollToMessage(_matches[index]);
  }

  /// Doskroluje k zprávě a krátce ji zvýrazní. Seznam staví bubliny líně,
  /// takže vzdálenou zprávu nejdřív „najde“ postupným posunem nahoru;
  /// když dojde na začátek, zkusí to ještě jednou odspodu (cíl byl níž).
  Future<void> _scrollToMessage(String id) async {
    for (var pass = 0; pass < 2; pass++) {
      for (var step = 0; step < 120; step++) {
        final ctx = _keys[id]?.currentContext;
        if (ctx != null && ctx.mounted) {
          await Scrollable.ensureVisible(
            ctx,
            alignment: 0.5,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          );
          _flash(id);
          return;
        }
        if (!_scrollController.hasClients) return;
        final pos = _scrollController.position;
        if (pos.pixels >= pos.maxScrollExtent) break;
        _scrollController.jumpTo(math.min(
            pos.pixels + pos.viewportDimension * 0.9, pos.maxScrollExtent));
        await WidgetsBinding.instance.endOfFrame;
      }
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  void _flash(String id) {
    _flashTimer?.cancel();
    setState(() => _flashId = id);
    _flashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _flashId = null);
    });
  }

  // ── Seznam zpráv ──────────────────────────────────────────────────────

  /// Shody hledání (text i popisek u fotky), od nejnovější. Počítá se
  /// PŘED stavbou hlavičky, jinak by počítadlo ukazovalo předchozí dotaz.
  void _updateMatches(List<Message> messages) {
    final query = _searching ? _searchController.text.trim() : '';
    if (query.isEmpty) {
      _matches = const [];
      return;
    }
    final q = fold(query);
    _matches = [
      for (final m in messages.reversed)
        if (!m.isDeleted && m.content != null && fold(m.content!).contains(q))
          m.id,
    ];
    if (_matchIndex >= _matches.length) _matchIndex = 0;
  }

  bool _joins(Message? a, Message b) =>
      a != null &&
      a.senderId == b.senderId &&
      a.isDeleted == b.isDeleted &&
      _isSameDay(a.timestamp, b.timestamp) &&
      a.timestamp.difference(b.timestamp).abs() < _clusterGap;

  Widget _buildMessageList(
    List<Message> messages,
    LocalIdentity? identity, {
    required Group? group,
    required String Function(String) autorJmeno,
    bool typing = false,
  }) {
    _messageCount = messages.length;
    final myId = identity?.id ?? '';
    final top = MediaQuery.paddingOf(context).top + 72;

    final query = _searching ? _searchController.text.trim() : '';
    final currentMatch = _matches.isEmpty ? null : _matches[_matchIndex];

    if (messages.isEmpty) {
      return Padding(padding: EdgeInsets.only(top: top), child: _buildEmptyChat());
    }

    final lastMineId =
        messages.lastWhere((m) => m.isMine(myId), orElse: () => messages.first).id;

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(12, 8, 12, top),
      reverse: true,
      itemCount: messages.length + (typing ? 1 : 0),
      itemBuilder: (context, rawIndex) {
        // Seznam je obrácený: položka 0 je dole — tam patří „píše…“.
        if (typing && rawIndex == 0) return const _TypingBubble();
        final index = typing ? rawIndex - 1 : rawIndex;
        final n = messages.length;
        final msg = messages[n - 1 - index];
        final older = index == n - 1 ? null : messages[n - 2 - index];
        final newer = index == 0 ? null : messages[n - index];
        final isMine = msg.isMine(myId);
        final showDate =
            older == null || !_isSameDay(msg.timestamp, older.timestamp);
        final first = showDate || !_joins(older, msg);
        final last = newer == null ||
            !_isSameDay(msg.timestamp, newer.timestamp) ||
            !_joins(newer, msg);
        final repliedTo = msg.replyToId == null
            ? null
            : messages.where((m) => m.id == msg.replyToId).firstOrNull;

        final callLog = msg.callLog;
        if (callLog != null) {
          return KeyedSubtree(
            key: _keys.putIfAbsent(msg.id, GlobalKey.new),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDate) _buildDateDivider(msg.timestamp),
                _buildCallLogRow(msg, callLog, isMine),
              ],
            ),
          );
        }

        Widget bubble = _MessageBubble(
          message: msg,
          isMine: isMine,
          contactId: widget.contactId,
          repliedTo: repliedTo,
          clusterFirst: first,
          clusterLast: last,
          query: query,
          highlighted: msg.id == currentMatch || msg.id == _flashId,
          onLongPress: () => _showMessageActions(msg, isMine),
          showStatus: !_isNotes,
          onToggleReaction: (emoji) => _toggleReaction(msg, emoji),
          onTapQuote: repliedTo == null
              ? null
              : () => _scrollToMessage(repliedTo.id),
          repliedToAuthor:
              repliedTo == null ? null : autorJmeno(repliedTo.senderId),
          myId: myId,
          nameOf: autorJmeno,
          onVote: group?.left == true ? null : (c) => _vote(msg, c),
        );
        if (!msg.isDeleted) {
          bubble = _SwipeToReply(
            onReply: () => setState(() {
              _replyingTo = msg;
              _editingId = null;
            }),
            child: bubble,
          );
        }

        // Ve skupině má cizí blok avatar autora u poslední bubliny.
        final groupIncoming = group != null && !isMine;
        if (groupIncoming) {
          bubble = Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 34,
                child: last
                    ? SepotAvatar(
                        name: autorJmeno(msg.senderId),
                        seed: msg.senderId,
                        size: 28)
                    : null,
              ),
              Expanded(child: bubble),
            ],
          );
        }

        return KeyedSubtree(
          key: _keys.putIfAbsent(msg.id, GlobalKey.new),
          child: Padding(
            padding: EdgeInsets.only(top: first ? 8 : 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDate) _buildDateDivider(msg.timestamp),
                if (msg.id == _firstUnreadId) _buildUnreadDivider(),
                if (groupIncoming && first)
                  Padding(
                    padding: const EdgeInsets.only(left: 46, bottom: 3),
                    child: Text(
                      autorJmeno(msg.senderId),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: SepotTint.of(msg.senderId).ink,
                      ),
                    ),
                  ),
                bubble,
                if (group == null &&
                    !_isNotes &&
                    isMine &&
                    msg.id == lastMineId)
                  _buildReceiptCaption(msg),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Záznam hovoru: na straně, kdo volal, s časem; klepnutí volá zpět.
  Widget _buildCallLogRow(Message msg, CallLog log, bool isMine) {
    final label = callLogLabel(context.l10n, log);
    final contact = ref
        .read(contactsProvider)
        .valueOrNull
        ?.where((c) => c.publicIdentity.id == widget.contactId)
        .firstOrNull;
    final color = label.alert ? SepotColors.error : SepotColors.textSecondary;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Material(
          color: SepotColors.surfaceVariant,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: contact == null || contact.blocked
                ? null
                : () => _startCall(contact, video: log.video),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(label.icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Text(label.text,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: label.alert
                              ? SepotColors.error
                              : SepotColors.textPrimary)),
                  const SizedBox(width: 10),
                  Text(
                    DateFormat.Hm(Localizations.localeOf(context).toString())
                        .format(msg.timestamp),
                    style: const TextStyle(
                        fontSize: 11, color: SepotColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnreadDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
              child: Container(
                  height: 1, color: SepotColors.ember.withValues(alpha: 0.45))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              context.l10n.chatUnreadDivider(_unreadAtOpen),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: SepotColors.ember),
            ),
          ),
          Expanded(
              child: Container(
                  height: 1, color: SepotColors.ember.withValues(alpha: 0.45))),
        ],
      ),
    );
  }

  Widget _buildJumpButton(Conversation? conv, String myId) {
    final fresh = conv == null
        ? 0
        : conv.messages.skip(_awayFrom).where((m) => !m.isMine(myId)).length;
    return Semantics(
      button: true,
      label: context.l10n.chatJumpToLatest,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _scrollController.animateTo(0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic);
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GlassSurface(
              borderRadius: BorderRadius.circular(24),
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.keyboard_arrow_down_rounded, size: 26),
              ),
            ),
            if (fresh > 0)
              Positioned(
                top: -6,
                right: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: SepotColors.ember,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$fresh',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: SepotColors.emberInk),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Plovoucí lišta místo pole pro psaní (blokovaný kontakt, opuštěná
  /// skupina).
  Widget _buildBanner(String text, {Widget? action}) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, color: SepotColors.textSecondary),
            ),
            ?action,
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const E2EBadge(),
          const SizedBox(height: 16),
          Text(
            context.l10n.chatEmptyEncrypted,
            style: const TextStyle(
                fontSize: 14, color: SepotColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.chatEmptyNoOneElse,
            style: const TextStyle(
                fontSize: 14, color: SepotColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildDateDivider(DateTime date) {
    final now = DateTime.now();
    String text;

    if (_isSameDay(date, now)) {
      text = context.l10n.commonToday;
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      text = context.l10n.commonYesterday;
    } else {
      text = DateFormat.yMMMd(Localizations.localeOf(context).toString())
          .format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: GlassSurface(
          borderRadius: BorderRadius.circular(14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: SepotColors.textEmphasis,
            ),
          ),
        ),
      ),
    );
  }

  // ── Pole pro psaní ────────────────────────────────────────────────────

  /// Najde „@dotaz“ těsně před kurzorem — jen na začátku slova, aby
  /// e-mailová adresa nabídku neotevírala.
  void _updateMentionQuery() {
    final group = ref.read(groupProvider(widget.contactId)).valueOrNull;
    final sel = _messageController.selection;
    final text = _messageController.text;
    int? start;
    if (group != null && sel.isCollapsed && sel.baseOffset > 0) {
      final before = text.substring(0, sel.baseOffset);
      final at = before.lastIndexOf('@');
      final query = at < 0 ? '' : before.substring(at + 1);
      final wordStart = at == 0 || (at > 0 && before[at - 1].trim().isEmpty);
      if (at >= 0 && wordStart && !query.contains('\n') && query.length <= 30) {
        start = at;
        _mentionQuery = query;
      }
    }
    _mentionStart = start;
  }

  Widget _buildMentionSuggestions() {
    final group = ref.read(groupProvider(widget.contactId)).valueOrNull;
    final myId = ref.read(identityProvider).valueOrNull?.id;
    final contacts = ref.read(contactsProvider).valueOrNull ?? const [];
    if (group == null) return const SizedBox.shrink();
    final q = fold(_mentionQuery);
    final candidates = <(String, String)>[
      for (final fp in group.memberIds)
        if (fp != myId)
          (
            fp,
            contacts
                    .where((c) => c.publicIdentity.id == fp)
                    .firstOrNull
                    ?.displayName ??
                ''
          ),
    ]
        .where((c) => c.$2.isNotEmpty && fold(c.$2).contains(q))
        .take(_mentionSuggestionLimit)
        .toList();
    if (candidates.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (fp, name) in candidates)
              ListTile(
                dense: true,
                leading: SepotAvatar(name: name, seed: fp, size: 30),
                title: Text(name,
                    style: const TextStyle(color: SepotColors.textPrimary)),
                onTap: () => _insertMention(fp, name),
              ),
          ],
        ),
      ),
    );
  }

  void _insertMention(String fingerprint, String name) {
    final start = _mentionStart;
    if (start == null) return;
    final text = _messageController.text;
    final end = _messageController.selection.baseOffset;
    final inserted = '@$name ';
    _messageController.value = TextEditingValue(
      text: text.replaceRange(start, end, inserted),
      selection: TextSelection.collapsed(offset: start + inserted.length),
    );
    setState(() {
      _mentions[fingerprint] = name;
      _mentionStart = null;
    });
  }

  /// Zmínky, které v odesílaném textu opravdu zůstaly (uživatel mohl
  /// vloženou zmínku smazat nebo přepsat).
  List<String> _mentionsIn(String text) => [
        for (final e in _mentions.entries)
          if (text.contains('@${e.value}')) e.key,
      ];

  Widget _buildComposer() {
    final hasText =
        _messageController.text.trim().isNotEmpty || _editingId != null;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_mentionStart != null) _buildMentionSuggestions(),
          if (_replyingTo != null || _editingId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GlassSurface(
                borderRadius: BorderRadius.circular(16),
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: _buildComposeBanner(),
              ),
            ),
          if (_isRecording)
            GlassSurface(
              borderRadius: BorderRadius.circular(27),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: _buildRecordingBar(),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: GlassSurface(
                    borderRadius: BorderRadius.circular(27),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 54),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: context.l10n.chatAttach,
                            icon: const Icon(Icons.add_rounded,
                                size: 24, color: SepotColors.textSecondary),
                            onPressed: (_isSending || _editingId != null)
                                ? null
                                : () => _pickAndSendAttachment(),
                          ),
                          Expanded(
                            // `filled: false` PŘEBÍJÍ globální
                            // InputDecorationTheme (jinak vnořené pole).
                            child: TextField(
                              controller: _messageController,
                              onChanged: (text) {
                                _updateMentionQuery();
                                setState(() {});
                                if (text.trim().isNotEmpty &&
                                    _editingId == null &&
                                    !_isNotes) {
                                  ref
                                      .read(messagingServiceProvider)
                                      .sendTyping(widget.contactId);
                                }
                              },
                              decoration: InputDecoration(
                                hintText: context.l10n.chatMessageHint,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 10),
                              ),
                              style: const TextStyle(fontSize: 16),
                              maxLines: 5,
                              minLines: 1,
                              textCapitalization:
                                  TextCapitalization.sentences,
                            ),
                          ),
                          if (!hasText)
                            IconButton(
                              tooltip: context.l10n.attachmentTakePhoto,
                              icon: const Icon(Icons.photo_camera_outlined,
                                  size: 22, color: SepotColors.textSecondary),
                              onPressed: _isSending
                                  ? null
                                  : () => _pickAndSendAttachment(
                                      preset: _AttachAction.camera),
                            )
                          else
                            const SizedBox(width: 12),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildSendButton(hasText),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSendButton(bool hasText) {
    final icon = hasText
        ? (_editingId != null ? Icons.check_rounded : Icons.arrow_upward_rounded)
        : Icons.mic_rounded;
    final label = hasText
        ? (_editingId != null ? context.l10n.commonSave : context.l10n.chatSend)
        : context.l10n.chatRecordVoice;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: SepotColors.ember,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _isSending
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  hasText ? _sendMessage() : _startRecording();
                },
          child: SizedBox(
            width: 54,
            height: 54,
            child: _isSending
                ? const Padding(
                    padding: EdgeInsets.all(17),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: SepotColors.emberInk),
                  )
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(icon,
                        key: ValueKey(icon),
                        size: 24,
                        color: SepotColors.emberInk),
                  ),
          ),
        ),
      ),
    );
  }

  String _fmtRec(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Lišta při nahrávání hlasové zprávy: zahodit · čas · odeslat.
  Widget _buildRecordingBar() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.delete_outline, color: SepotColors.error),
          onPressed: _cancelRecording,
          tooltip: context.l10n.chatDiscardRecording,
        ),
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: SepotColors.error),
        ),
        const SizedBox(width: 10),
        Text(_fmtRec(_recordDur),
            style: const TextStyle(
                color: SepotColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()])),
        const SizedBox(width: 12),
        Text(context.l10n.chatRecording,
            style: const TextStyle(
                color: SepotColors.textSecondary, fontSize: 13)),
        const Spacer(),
        Material(
          color: SepotColors.ember,
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: context.l10n.chatSend,
            icon: const Icon(Icons.arrow_upward_rounded,
                color: SepotColors.emberInk),
            onPressed: _stopAndSend,
          ),
        ),
      ],
    );
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.chatMicPermissionMissing)),
          );
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
            encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100),
        path: path,
      );
      _recordPath = path;
      setState(() {
        _isRecording = true;
        _recordDur = Duration.zero;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordDur += const Duration(seconds: 1));
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .chatRecordingFailed(describeError(context.l10n, e)))),
        );
      }
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    final p = _recordPath;
    if (p != null) {
      try {
        await File(p).delete();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordPath = null;
      });
    }
  }

  Future<void> _stopAndSend() async {
    _recordTimer?.cancel();
    final dur = _recordDur;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    setState(() => _isRecording = false);
    if (path == null) return;
    final file = File(path);
    try {
      // Moc krátké klepnutí — zahoď (uživatel to nechtěl poslat)
      if (dur.inMilliseconds < 800) {
        await file.delete();
        return;
      }
      final bytes = await file.readAsBytes();
      await ref.read(conversationsProvider.notifier).sendVoiceMessage(
            widget.contactId,
            bytes: bytes,
            durationMs: dur.inMilliseconds,
          );
      ref.invalidate(conversationProvider(widget.contactId));
      await file.delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .chatVoiceSendFailed(describeError(context.l10n, e)))),
        );
      }
    }
  }

  /// Banner nad inputem: aktivní odpověď nebo režim úpravy.
  Widget _buildComposeBanner() {
    final editing = _editingId != null;
    final preview = editing
        ? _messageController.text
        : (_replyingTo?.isDeleted ?? false
            ? context.l10n.chatDeletedMessagePreview
            : (_replyingTo?.attachment?.isAudio == true
                ? context.l10n.chatVoiceMessagePreview
                : (_replyingTo?.content?.isNotEmpty == true
                    ? _replyingTo!.content!
                    : (_replyingTo?.type == MessageType.image
                        ? context.l10n.chatPhotoPreview
                        : context.l10n.chatAttachmentPreview))));
    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: SepotColors.ember,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    editing
                        ? context.l10n.chatEditingMessage
                        : context.l10n.chatReply,
                    style: const TextStyle(
                        fontSize: 12,
                        color: SepotColors.ember,
                        fontWeight: FontWeight.w600)),
                Text(preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: SepotColors.textSecondary)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: SepotColors.textMuted,
            onPressed: () => setState(() {
              _replyingTo = null;
              if (editing) _finishEditing();
            }),
          ),
        ],
      ),
    );
  }

  /// Akční menu zprávy (long-press): odpovědět / reagovat / upravit /
  /// smazat / kopírovat.
  void _showMessageActions(Message msg, bool isMine) {
    if (msg.isDeleted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SepotColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Řádek rychlých reakcí
            if (!_isNotes) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final e in _quickReactions)
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          _toggleReaction(msg, e);
                        },
                        child: Text(e, style: const TextStyle(fontSize: 28)),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: SepotColors.border),
            ],
            if (isMine && !_isNotes)
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(context.l10n.chatActionInfo),
                onTap: () {
                  Navigator.pop(ctx);
                  _showMessageInfo(msg);
                },
              ),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: Text(context.l10n.chatActionReply),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _replyingTo = msg;
                  _editingId = null;
                });
              },
            ),
            // Anketa se nepřeposílá: hlasy patří lidem z původního chatu.
            if (msg.poll == null)
              ListTile(
                leading: const Icon(Icons.shortcut_rounded),
                title: Text(context.l10n.chatActionForward),
                onTap: () {
                  Navigator.pop(ctx);
                  forwardMessage(context, ref, msg, fromId: widget.contactId);
                },
              ),
            if (msg.type == MessageType.text && !msg.isDeleted)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(context.l10n.commonCopy),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: msg.content ?? ''));
                },
              ),
            if (isMine && msg.type == MessageType.text && msg.poll == null)
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: Text(context.l10n.commonEdit),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    if (_editingId == null) {
                      _draftBeforeEdit = _messageController.text;
                    }
                    _editingId = msg.id;
                    _replyingTo = null;
                    _messageController.text = msg.content ?? '';
                  });
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(context.l10n.chatDeleteForMe),
              onTap: () {
                Navigator.pop(ctx);
                ref
                    .read(conversationsProvider.notifier)
                    .deleteLocalMessage(widget.contactId, msg.id);
                ref.invalidate(conversationProvider(widget.contactId));
              },
            ),
            if (isMine && !msg.isDeleted && !_isNotes)
              ListTile(
                leading: const Icon(Icons.delete_forever,
                    color: SepotColors.error),
                title: Text(context.l10n.chatDeleteForEveryone,
                    style: const TextStyle(color: SepotColors.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  ref
                      .read(conversationsProvider.notifier)
                      .deleteMessage(widget.contactId, msg.id);
                  ref.invalidate(conversationProvider(widget.contactId));
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Čas doručení/přečtení: dnes jen hodina, jinak i datum.
  String _formatWhen(DateTime t) {
    final locale = Localizations.localeOf(context).toString();
    final time = DateFormat.Hm(locale).format(t);
    return _isSameDay(t, DateTime.now())
        ? time
        : '${DateFormat.MMMd(locale).format(t)} $time';
  }

  /// Drobný řádek pod mou poslední zprávou v 1:1 — kdy ji protistrana
  /// dostala / přečetla, bez nutnosti otevírat Info.
  Widget _buildReceiptCaption(Message msg) {
    final readAt = msg.firstReadAt;
    final deliveredAt = msg.firstDeliveredAt;
    final text = readAt != null
        ? context.l10n.chatStatusReadAt(_formatWhen(readAt))
        : deliveredAt != null
            ? context.l10n.chatStatusDeliveredAt(_formatWhen(deliveredAt))
            : null;
    if (text == null || msg.isDeleted) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 4, top: 1, bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: readAt != null ? SepotColors.mist : SepotColors.textMuted,
          ),
        ),
      ),
    );
  }

  /// Info o mé zprávě: kdy odešla a kdy ji kdo dostal / přečetl. Ve
  /// skupině po členech — ✓✓ v bublině tam svítí až za všechny.
  Future<void> _showMessageInfo(Message msg) async {
    final group = await ref.read(groupProvider(widget.contactId).future);
    final contacts = ref.read(contactsProvider).valueOrNull ?? const [];
    final myId = ref.read(identityProvider).valueOrNull?.id;
    final receiptsOn = await ref
            .read(storageProvider)
            .getSetting<bool>('read_receipts_enabled') ??
        false;
    if (!mounted) return;

    final recipients = group != null
        ? group.memberIds.where((f) => f != myId).toList()
        : [widget.contactId];
    String jmeno(String f) {
      final c = contacts.where((c) => c.id == f).firstOrNull;
      if (c == null) return 'SEP-${f.substring(0, f.length.clamp(0, 10))}';
      return c.displayName.isEmpty
          ? context.l10n.commonUnknownContact
          : c.displayName;
    }

    Widget radek(IconData icon, String label, DateTime? t, {Color? color}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color ?? SepotColors.textMuted),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    fontSize: 13, color: SepotColors.textSecondary)),
            const Spacer(),
            Text(
              t == null ? context.l10n.messageInfoPending : _formatWhen(t),
              style: TextStyle(
                fontSize: 13,
                color: t == null
                    ? SepotColors.textMuted
                    : SepotColors.textPrimary,
              ),
            ),
          ],
        ),
      );
    }

    final odeslano = msg.status == MessageStatus.sending ||
            msg.status == MessageStatus.failed
        ? null
        : msg.timestamp;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: SepotColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            children: [
              Text(context.l10n.chatActionInfo,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              radek(Icons.north_east_rounded, context.l10n.messageInfoSent,
                  odeslano),
              for (final f in recipients) ...[
                if (group != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SepotAvatar(name: jmeno(f), size: 24),
                      const SizedBox(width: 8),
                      Text(jmeno(f),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                radek(Icons.done_all_rounded,
                    context.l10n.messageInfoDelivered, msg.deliveredTo[f]),
                if (receiptsOn)
                  radek(Icons.visibility_outlined, context.l10n.messageInfoRead,
                      msg.readBy[f],
                      color: msg.readBy[f] != null ? SepotColors.mist : null),
              ],
              if (!receiptsOn) ...[
                const SizedBox(height: 12),
                Text(context.l10n.messageInfoReadReceiptsOff,
                    style: const TextStyle(
                        fontSize: 12, color: SepotColors.textMuted)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleReaction(Message msg, String emoji) async {
    final mine = ref.read(identityProvider).valueOrNull?.fingerprint.display;
    final already = mine != null && msg.reactions[mine] == emoji;
    await ref
        .read(conversationsProvider.notifier)
        .reactToMessage(widget.contactId, msg.id, already ? null : emoji);
    ref.invalidate(conversationProvider(widget.contactId));
  }

  Future<void> _pickAndSendAttachment({_AttachAction? preset}) async {
    final action = preset ?? await showModalBottomSheet<_AttachAction>(
      context: context,
      backgroundColor: SepotColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final (icon, label, value) in [
              (
                Icons.photo_library_outlined,
                context.l10n.attachmentGallery,
                _AttachAction.gallery
              ),
              (
                Icons.photo_camera_outlined,
                context.l10n.attachmentTakePhoto,
                _AttachAction.camera
              ),
              (
                Icons.description_outlined,
                context.l10n.attachmentDocument,
                _AttachAction.document
              ),
              if (!_isNotes)
                (
                  Icons.bar_chart_rounded,
                  context.l10n.pollAttach,
                  _AttachAction.poll
                ),
            ])
              ListTile(
                leading: Icon(icon, color: SepotColors.ember),
                title: Text(label),
                onTap: () => Navigator.pop(context, value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == _AttachAction.poll) {
      await _createPoll();
      return;
    }

    Uint8List? bytes;
    var fileName = '';
    String? mime;
    String? caption;
    try {
      switch (action) {
        case _AttachAction.gallery:
        case _AttachAction.camera:
          // maxWidth/Height 2048 = strop ImageProcessoru; menší vstup šetří
          // RAM při náhledu i finálním renderu úprav.
          final picked = await ImagePicker().pickImage(
            source: action == _AttachAction.gallery
                ? ImageSource.gallery
                : ImageSource.camera,
            maxWidth: 2048,
            maxHeight: 2048,
            imageQuality: 92,
          );
          if (picked == null) return;
          final pickedBytes = await picked.readAsBytes();
          if (!mounted) return;
          // Nic neodchází rovnou z kamery — náhled s úpravami a potvrzením.
          final preview = await Navigator.of(context).push<PhotoPreviewResult>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => PhotoPreviewScreen(
                bytes: pickedBytes,
                fileName: picked.name,
                mime: picked.mimeType,
              ),
            ),
          );
          if (preview == null || !mounted) return;
          bytes = preview.bytes;
          fileName = preview.fileName;
          mime = preview.mime;
          caption = preview.caption;
        case _AttachAction.poll:
          return; // obslouženo výš, jen kvůli úplnosti switche
        case _AttachAction.document:
          final result = await FilePicker.pickFiles(withData: true);
          final file = result?.files.firstOrNull;
          if (file == null || file.bytes == null) return;
          if (file.size > AppConstants.maxAttachmentBytes) {
            if (mounted) {
              _showError(context.l10n.attachmentTooLarge(
                  AppConstants.maxAttachmentBytes ~/ (1024 * 1024)));
            }
            return;
          }
          final mimeGuess =
              lookupMimeType(file.name, headerBytes: file.bytes);
          if (mimeGuess != null &&
              mimeGuess.startsWith('image/') &&
              !await ImageProcessor.canStripMetadata(file.bytes!)) {
            if (!mounted || !await _confirmOriginalWithMetadata()) return;
          }
          bytes = file.bytes;
          fileName = file.name;
      }
    } catch (e) {
      if (mounted) {
        _showError(
            context.l10n.attachmentPickFailed(describeError(context.l10n, e)));
      }
      return;
    }
    if (bytes == null) return;

    setState(() => _isSending = true);
    try {
      await ref.read(conversationsProvider.notifier).sendAttachment(
            widget.contactId,
            bytes: bytes,
            fileName: fileName,
            mime: mime,
            caption: caption,
          );
      ref.invalidate(conversationProvider(widget.contactId));
    } catch (e) {
      if (mounted) {
        _showError(
            context.l10n.attachmentSendFailed(describeError(context.l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _createPoll() async {
    final poll = await showCreatePollSheet(context);
    if (poll == null || !mounted) return;
    // Záložní text pro starší verze appky — uvidí otázku i možnosti.
    final fallback = [
      context.l10n.pollFallback(poll.question),
      for (final o in poll.options) '• $o',
      context.l10n.pollFallbackUpdate,
    ].join('\n');
    try {
      await ref
          .read(conversationsProvider.notifier)
          .sendPoll(widget.contactId, poll, fallback);
      ref.invalidate(conversationProvider(widget.contactId));
    } catch (e) {
      if (!mounted) return;
      _showError(context.l10n.chatSendFailed(describeError(context.l10n, e)));
    }
  }

  Future<void> _vote(Message msg, List<int> choice) async {
    try {
      await ref
          .read(conversationsProvider.notifier)
          .votePoll(widget.contactId, msg.id, choice);
      ref.invalidate(conversationProvider(widget.contactId));
    } catch (e) {
      if (!mounted) return;
      _showError(context.l10n.chatSendFailed(describeError(context.l10n, e)));
    }
  }

  Future<bool> _confirmOriginalWithMetadata() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.attachmentKeepsMetadataTitle),
        content: Text(context.l10n.attachmentKeepsMetadataBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.attachmentSendOriginal),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Konec úpravy (odeslání i zrušení) vrátí do pole odložený koncept.
  void _finishEditing() {
    _editingId = null;
    _messageController.text = _draftBeforeEdit ?? '';
    _draftBeforeEdit = null;
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final editingId = _editingId;
    final replyToId = _replyingTo?.id;
    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final notifier = ref.read(conversationsProvider.notifier);
      if (editingId != null) {
        await notifier.editMessage(widget.contactId, editingId, text);
      } else {
        await notifier.sendMessage(widget.contactId, text,
            replyToId: replyToId, mentions: _mentionsIn(text));
      }
      if (mounted) {
        setState(() {
          _replyingTo = null;
          _mentions.clear();
          _mentionStart = null;
          if (editingId != null) _finishEditing();
        });
      }
      ref.invalidate(conversationProvider(widget.contactId));
    } catch (e) {
      if (mounted) {
        _messageController.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  context.l10n.chatSendFailed(describeError(context.l10n, e)))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

/// Šířka bubliny: textové zprávy se scalují podle obsahu (IntrinsicWidth),
/// obrázky/přílohy zůstávají „plné" — AspectRatio potřebuje šířku od rodiče.
class _CompactWidth extends StatelessWidget {
  const _CompactWidth({required this.compact, required this.child});

  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      compact ? IntrinsicWidth(child: child) : child;
}

/// Tři pulzující tečky dole v chatu, dokud protistrana píše.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          label: context.l10n.chatTyping,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: SepotColors.bubbleReceived,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
                bottomLeft: Radius.circular(6),
              ),
            ),
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 5),
                    Opacity(
                      // Vlna: každá tečka o třetinu periody později.
                      opacity: 0.35 +
                          0.65 *
                              (0.5 +
                                  0.5 *
                                      math.sin(2 *
                                          math.pi *
                                          (_pulse.value - i / 3))),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: SepotColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Odpověď tahem doprava: bublina se posune, objeví se šipka a po
/// překročení prahu jemně cvakne. Pustit = odpovědět.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.onReply, required this.child});

  final VoidCallback onReply;
  final Widget child;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  static const _max = 84.0;
  static const _trigger = 58.0;

  // Kontroler vzniká až při prvním tahu. Dřív ho `late final` vytvořil
  // teprve dispose() u bublin, které nikdo netáhl – nad deaktivovaným
  // elementem, což v debug buildu padá na hledání TickerMode.
  AnimationController? _backCtl;
  AnimationController get _back => _backCtl ??= AnimationController(
      vsync: this, duration: const Duration(milliseconds: 180))
    ..addListener(() => setState(() => _dx = _from * (1 - _back.value)));
  double _dx = 0;
  double _from = 0;
  bool _armed = false;

  @override
  void dispose() {
    _backCtl?.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d) {
    if (_back.isAnimating) _back.stop();
    setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, _max));
    final armed = _dx >= _trigger;
    if (armed && !_armed) HapticFeedback.selectionClick();
    _armed = armed;
  }

  void _end(DragEndDetails _) {
    if (_armed) widget.onReply();
    _armed = false;
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dx / _trigger).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (_dx > 0)
            Opacity(
              opacity: progress,
              child: Transform.scale(
                scale: 0.6 + 0.4 * progress,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SepotColors.ember.withValues(alpha: 0.18),
                  ),
                  child: const Icon(Icons.reply_rounded,
                      size: 19, color: SepotColors.ember),
                ),
              ),
            ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}

/// Bublina se zprávou (text, obrázek, dokument, hlas).
class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final String contactId;
  final Message? repliedTo; // zpráva, na kterou tahle odpovídá
  final String? repliedToAuthor;

  /// Pozice v bloku zpráv od stejného člověka — určuje zaoblení rohů.
  final bool clusterFirst;
  final bool clusterLast;

  /// Hledaný text ke zvýraznění (prázdný = nic).
  final String query;

  /// Aktuální shoda hledání / cíl skoku z citace.
  final bool highlighted;
  final VoidCallback? onLongPress;
  final VoidCallback? onTapQuote;
  final void Function(String emoji)? onToggleReaction;

  /// Fajfky doručení — v poznámkách pro sebe nedávají smysl.
  final bool showStatus;

  /// Pro anketu: můj otisk, jména hlasujících a hlasování.
  final String myId;
  final String Function(String fingerprint)? nameOf;
  final void Function(List<int> choice)? onVote;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.contactId,
    this.repliedTo,
    this.repliedToAuthor,
    this.clusterFirst = true,
    this.clusterLast = true,
    this.query = '',
    this.highlighted = false,
    this.onLongPress,
    this.onTapQuote,
    this.onToggleReaction,
    this.showStatus = true,
    this.myId = '',
    this.nameOf,
    this.onVote,
  });

  /// Ztlumený inkoust pro metadata na ember bublině.
  static const _inkSoft = Color(0x9E2B120A);

  static const _radius = Radius.circular(20);
  static const _joined = Radius.circular(6);

  /// Zvýraznění shody hledání (jantar — odlišné od korálu i od textu).
  static const _matchColor = SepotColors.warning;

  BorderRadius get _shape {
    // Strana „ocásku“ (moje vpravo, cizí vlevo): uvnitř bloku malé rohy,
    // navenek velké — blok pak čte jako jeden celek.
    final top = clusterFirst ? _radius : _joined;
    return isMine
        ? BorderRadius.only(
            topLeft: _radius,
            bottomLeft: _radius,
            topRight: top,
            bottomRight: _joined)
        : BorderRadius.only(
            topRight: _radius,
            bottomRight: _radius,
            topLeft: top,
            bottomLeft: _joined);
  }

  @override
  Widget build(BuildContext context) {
    final hasAttachment = !message.isDeleted &&
        message.attachment != null &&
        (message.type == MessageType.image ||
            message.type == MessageType.file);
    if (message.type != MessageType.text &&
        !hasAttachment &&
        !message.isDeleted) {
      return const SizedBox.shrink();
    }
    final isImage = hasAttachment && message.type == MessageType.image;
    final isAudio = hasAttachment && message.attachment!.isAudio;
    final poll = message.isDeleted ? null : message.poll;
    final ink = isMine ? SepotColors.emberInk : SepotColors.textPrimary;
    final metaColor = isMine ? _inkSoft : SepotColors.textSecondary;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: message.isDeleted
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    onLongPress?.call();
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: isImage
                  ? const EdgeInsets.all(4)
                  : const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              // Anketa potřebuje pevnou šířku — pruhy výsledků se měří
              // proti ní, podle obsahu by každá anketa byla jinak široká.
              width: poll != null
                  ? MediaQuery.sizeOf(context).width * 0.76
                  : null,
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.78,
              ),
              decoration: BoxDecoration(
                color: isMine
                    ? SepotColors.bubbleSent
                    : SepotColors.bubbleReceived,
                borderRadius: _shape,
                boxShadow: highlighted
                    ? const [BoxShadow(color: _matchColor, spreadRadius: 2)]
                    : null,
              ),
              child: _CompactWidth(
                compact: !isImage && !hasAttachment && poll == null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.isDeleted)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.block,
                              size: 14, color: ink.withValues(alpha: .6)),
                          const SizedBox(width: 6),
                          Text(context.l10n.chatMessageDeleted,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontStyle: FontStyle.italic,
                                  color: ink.withValues(alpha: .7))),
                        ],
                      )
                    else ...[
                      if (repliedTo != null) _buildQuote(context, ink),
                      if (isImage)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ImageAttachmentContent(
                              contactId: contactId, message: message),
                        )
                      else if (isAudio)
                        AudioAttachmentContent(
                            contactId: contactId,
                            message: message,
                            isMine: isMine)
                      else if (hasAttachment)
                        DocumentAttachmentContent(
                            contactId: contactId, message: message),
                      if (poll != null)
                        PollContent(
                          poll: poll,
                          onEmber: isMine,
                          myId: myId,
                          nameOf: nameOf ?? (f) => f,
                          onVote: onVote,
                        )
                      else if (message.content != null &&
                          message.content!.isNotEmpty)
                        Padding(
                          padding: isImage
                              ? const EdgeInsets.fromLTRB(9, 7, 9, 0)
                              : hasAttachment
                                  ? const EdgeInsets.only(top: 6, bottom: 2)
                                  : EdgeInsets.zero,
                          child: Text.rich(
                            _highlight(message.content!, ink),
                            style: TextStyle(
                                fontSize: 15.5, color: ink, height: 1.38),
                          ),
                        ),
                    ],
                    const SizedBox(height: 3),
                    Padding(
                      padding: isImage
                          ? const EdgeInsets.fromLTRB(9, 0, 9, 4)
                          : EdgeInsets.zero,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (message.editedAt != null && !message.isDeleted)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(context.l10n.chatEdited,
                                  style:
                                      TextStyle(fontSize: 11, color: metaColor)),
                            ),
                          if (message.isDisappearing)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.timer_outlined,
                                  size: 12, color: metaColor),
                            ),
                          Text(
                            DateFormat.Hm(
                                    Localizations.localeOf(context).toString())
                                .format(message.timestamp),
                            style: TextStyle(fontSize: 11, color: metaColor),
                          ),
                          if (isMine && showStatus && !message.isDeleted) ...[
                            const SizedBox(width: 5),
                            MessageStatusIcon(
                                status: message.status, onEmber: true),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (message.reactions.isNotEmpty) _buildReactions(),
        ],
      ),
    );
  }

  /// Text s vyznačenými shodami hledání (bez ohledu na diakritiku).
  TextSpan _highlight(String text, Color ink) {
    if (query.isEmpty) return TextSpan(text: text);
    final hits = foldedIndexes(text, query);
    if (hits.isEmpty) return TextSpan(text: text);
    final len = query.length;
    final spans = <TextSpan>[];
    var pos = 0;
    for (final h in hits) {
      if (h < pos) continue;
      if (h > pos) spans.add(TextSpan(text: text.substring(pos, h)));
      final end = math.min(h + len, text.length);
      spans.add(TextSpan(
        text: text.substring(h, end),
        style: const TextStyle(
          backgroundColor: _matchColor,
          color: SepotColors.background,
          fontWeight: FontWeight.w600,
        ),
      ));
      pos = end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return TextSpan(children: spans);
  }

  Widget _buildQuote(BuildContext context, Color ink) {
    final r = repliedTo!;
    final preview = r.isDeleted
        ? context.l10n.chatDeletedMessagePreview
        : (r.attachment?.isAudio == true
            ? context.l10n.chatVoiceMessagePreview
            : (r.content?.isNotEmpty == true
                ? r.content!
                : (r.type == MessageType.image
                    ? context.l10n.chatPhotoPreview
                    : context.l10n.chatAttachmentPreview)));
    final accent = isMine ? SepotColors.emberInk : SepotTint.of(r.senderId).ink;
    return GestureDetector(
      onTap: onTapQuote,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(9, 6, 10, 6),
        decoration: BoxDecoration(
          color: isMine
              ? SepotColors.emberInk.withValues(alpha: 0.13)
              : Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (repliedToAuthor != null)
              Text(repliedToAuthor!,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accent)),
            Text(preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 13, color: ink.withValues(alpha: .8))),
          ],
        ),
      ),
    );
  }

  /// Seskupené reakce (emoji × počet) — přesahují spodní hranu bubliny.
  Widget _buildReactions() {
    final counts = <String, int>{};
    for (final e in message.reactions.values) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
    return Transform.translate(
      offset: const Offset(0, -6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Wrap(
          spacing: 4,
          children: [
            for (final entry in counts.entries)
              GestureDetector(
                onTap: () => onToggleReaction?.call(entry.key),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: SepotColors.border,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: SepotColors.background, width: 2),
                  ),
                  child: Text(
                    entry.value > 1 ? '${entry.key} ${entry.value}' : entry.key,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
