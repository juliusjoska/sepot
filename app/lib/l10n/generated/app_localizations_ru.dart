// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Šepot';

  @override
  String get settingsLanguage => 'Язык приложения';

  @override
  String get languageSystem => 'Как в системе';

  @override
  String get commonUnknownContact => 'Неизвестный';

  @override
  String get verifyVerified => 'Подтверждён';

  @override
  String get verifyUnverified => 'Не подтверждён';

  @override
  String get chatMenuVerifyContact => 'Подтвердить контакт';

  @override
  String get chatDisappearingMessages => 'Исчезающие сообщения';

  @override
  String get chatMenuUnblockContact => 'Разблокировать контакт';

  @override
  String get chatMenuBlockContact => 'Заблокировать контакт';

  @override
  String get reportAndBlock => 'Пожаловаться и заблокировать';

  @override
  String errorGeneric(String error) {
    return 'Ошибка: $error';
  }

  @override
  String get groupsYouLeftGroup => 'Вы больше не в группе';

  @override
  String groupsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count участника',
      many: '$count участников',
      few: '$count участника',
      one: '$count участник',
    );
    return '$_temp0';
  }

  @override
  String get groupsMembers => 'Участники';

  @override
  String get groupsRename => 'Переименовать группу';

  @override
  String get groupsLeave => 'Покинуть группу';

  @override
  String get groupsLeftBanner =>
      'Вы больше не в группе. История сохранится, но новые сообщения приходить не будут.';

  @override
  String get groupsYou => 'Вы';

  @override
  String get groupsFounder => 'Создатель';

  @override
  String get groupsAdmin => 'Администратор';

  @override
  String get groupsMakeAdmin => 'Сделать администратором';

  @override
  String get groupsDismissAdmin => 'Снять роль администратора';

  @override
  String get groupsRemoveMember => 'Удалить из группы';

  @override
  String groupsRemoveMemberConfirmTitle(String name) {
    return 'Удалить $name из группы?';
  }

  @override
  String get groupsRemoveMemberConfirmBody =>
      'Новые сообщения группы перестанут приходить. Прежняя история сохранится.';

  @override
  String get groupsRemoveAction => 'Удалить';

  @override
  String get groupsViewContact => 'Открыть контакт';

  @override
  String get groupsAdminOnlyHint =>
      'Название, участников и администраторов группы меняют только администраторы.';

  @override
  String get groupsAdminOnlyCompatHint =>
      'Переименовать группу и менять администраторов могут только администраторы. Добавлять людей пока может любой, потому что у кого-то в группе старая версия Šepot.';

  @override
  String groupsAdminActionFailed(String error) {
    return 'Не удалось внести изменение: $error';
  }

  @override
  String get groupsResyncNotice =>
      'Группа сверяется с администратором. Изменения состава могут появиться с задержкой.';

  @override
  String get groupsRejectedChangeNotice =>
      'Кто-то без прав попытался изменить группу. Изменение не применено.';

  @override
  String get errorGroupNotAdmin =>
      'Это может сделать только администратор группы.';

  @override
  String get errorGroupLastAdmin =>
      'Вы единственный администратор. Сначала назначьте администратором кого-то ещё.';

  @override
  String get groupsNameHint => 'Название группы';

  @override
  String get commonCancel => 'Отмена';

  @override
  String get commonSave => 'Сохранить';

  @override
  String groupsRenameFailed(String error) {
    return 'Не удалось переименовать группу: $error';
  }

  @override
  String get groupsLeaveConfirmTitle => 'Покинуть группу?';

  @override
  String get groupsLeaveConfirmBody =>
      'Остальные увидят, что вы больше не в группе. История у вас сохранится, но новые сообщения приходить не будут, а вернуться можно только по новому приглашению.';

  @override
  String get groupsLeaveAction => 'Покинуть';

  @override
  String groupsLeaveFailed(String error) {
    return 'Не удалось покинуть группу: $error';
  }

  @override
  String get chatBlockedBanner =>
      'Контакт заблокирован. Вы не получаете от него сообщения и не можете ему писать.';

  @override
  String get chatUnblock => 'Разблокировать';

  @override
  String chatContactBlocked(String name) {
    return 'Контакт $name заблокирован';
  }

  @override
  String chatContactUnblocked(String name) {
    return 'Контакт $name разблокирован';
  }

  @override
  String reportAndBlockBody(String name) {
    return 'Мы заблокируем контакт $name, и вы перестанете получать от него сообщения. Затем мы предложим форму, в которой вы опишете, что произошло, — мы не видим содержимое сообщений, поэтому без вашего описания ничего об этом не знаем.';
  }

  @override
  String get chatEmptyEncrypted => 'Сообщения защищены сквозным шифрованием.';

  @override
  String get chatEmptyNoOneElse => 'Никто другой не может их прочитать.';

  @override
  String get commonToday => 'Сегодня';

  @override
  String get commonYesterday => 'Вчера';

  @override
  String get chatMessageHint => 'Напишите сообщение…';

  @override
  String get chatDiscardRecording => 'Удалить запись';

  @override
  String get chatRecording => 'Идёт запись…';

  @override
  String get chatMicPermissionMissing => 'Нет доступа к микрофону';

  @override
  String chatRecordingFailed(String error) {
    return 'Не удалось начать запись: $error';
  }

  @override
  String chatVoiceSendFailed(String error) {
    return 'Не удалось отправить голосовое сообщение: $error';
  }

  @override
  String get chatDeletedMessagePreview => 'Удалённое сообщение';

  @override
  String get chatVoiceMessagePreview => '🎤 Голосовое сообщение';

  @override
  String get chatPhotoPreview => '📷 Фото';

  @override
  String get chatAttachmentPreview => '📎 Вложение';

  @override
  String get chatEditingMessage => 'Редактирование сообщения';

  @override
  String get chatReply => 'Ответ';

  @override
  String get chatActionReply => 'Ответить';

  @override
  String get chatActionForward => 'Переслать';

  @override
  String get forwardTitle => 'Переслать в…';

  @override
  String get forwardSearchHint => 'Найти контакт или группу';

  @override
  String get forwardEmpty => 'Ничего не найдено';

  @override
  String forwardDone(String name) {
    return 'Переслано: $name';
  }

  @override
  String forwardFailed(String error) {
    return 'Не удалось переслать: $error';
  }

  @override
  String get commonCopy => 'Копировать';

  @override
  String get commonEdit => 'Изменить';

  @override
  String get chatDeleteForMe => 'Удалить у меня';

  @override
  String get chatDeleteForEveryone => 'Удалить у всех';

  @override
  String get commonOff => 'Выключено';

  @override
  String get chatDisappearing30s => '30 секунд';

  @override
  String get chatDisappearing5m => '5 минут';

  @override
  String get chatDisappearing1h => '1 час';

  @override
  String get chatDisappearing1d => '1 день';

  @override
  String get chatDisappearing1w => '1 неделя';

  @override
  String get chatDisappearingDescription =>
      'Новые сообщения будут удаляться по истечении заданного срока и у вас, и у собеседника.';

  @override
  String get chatDisappearingDisabled => 'Исчезающие сообщения выключены';

  @override
  String chatDisappearingEnabled(String duration) {
    return 'Новые сообщения исчезнут через: $duration';
  }

  @override
  String get attachmentGallery => 'Фото из галереи';

  @override
  String get attachmentTakePhoto => 'Сделать фото';

  @override
  String get attachmentDocument => 'Документ';

  @override
  String attachmentTooLarge(int maxMb) {
    return 'Файл слишком большой (макс. $maxMb МБ)';
  }

  @override
  String get attachmentKeepsMetadataTitle => 'Фото будет с геолокацией';

  @override
  String get attachmentKeepsMetadataBody =>
      'Из этого формата фото (например, HEIC) я не могу удалить метаданные. Оно будет отправлено в оригинале, включая место съёмки и данные о телефоне. Безопаснее отправить его через Галерею — там метаданные удаляются.';

  @override
  String get attachmentSendOriginal => 'Отправить оригинал';

  @override
  String attachmentPickFailed(String error) {
    return 'Не удалось выбрать вложение: $error';
  }

  @override
  String attachmentSendFailed(String error) {
    return 'Не удалось отправить вложение: $error';
  }

  @override
  String chatSendFailed(String error) {
    return 'Не удалось отправить: $error';
  }

  @override
  String get chatMessageDeleted => 'Сообщение удалено';

  @override
  String get chatEdited => 'изменено';

  @override
  String get errorTrustRootChanged =>
      'Trust root релея изменился! Соединение отклонено.';

  @override
  String get errorRelayUnavailable => 'Релей недоступен (sender certificate)';

  @override
  String get errorNotYetRegistered =>
      'Šepot ещё подключается к релею — попробуйте отправить сообщение через пару секунд.';

  @override
  String get errorContactLinkIncomplete =>
      'Ссылка неполная — собеседник создал её до подключения. Попросите у него новую ссылку sepot://.';

  @override
  String errorAttachmentTooLarge(int maxMb) {
    return 'Вложение слишком большое (макс. $maxMb МБ)';
  }

  @override
  String get errorGroupNeedsMember => 'В группе должен быть хотя бы 1 участник';

  @override
  String get errorAttachmentUnavailable =>
      'Вложения больше нет на этом телефоне';

  @override
  String errorGroupMaxMembers(int maxMembers) {
    return 'Максимальное число участников группы — $maxMembers';
  }

  @override
  String errorMemberNoDeliveryAddress(String displayName) {
    return 'У контакта $displayName нет адреса доставки — запросите новую ссылку';
  }

  @override
  String get errorContactNoDeliveryAddress =>
      'У контакта нет адреса доставки — попросите у него новую ссылку sepot://';

  @override
  String get errorIdentityKeyMismatch =>
      'Ключ идентификации с релея НЕ СОВПАДАЕТ с контактом — возможен MITM! Сообщение не отправлено.';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsSectionGeneral => 'Общие';

  @override
  String get settingsSectionSecurity => 'Безопасность';

  @override
  String get settingsChangePinTitle => 'Изменить PIN';

  @override
  String get settingsChangePinSubtitle => '6-значный PIN для разблокировки';

  @override
  String get settingsAutoLockTitle => 'Автоблокировка';

  @override
  String get settingsAutoLock5min => 'Через 5 минут';

  @override
  String get settingsDecoyPinTitle => 'PIN принуждения';

  @override
  String get settingsDecoyPinSetSubtitle =>
      'Установлен — откроет пустое приложение';

  @override
  String get settingsDecoyPinUnsetSubtitle =>
      'Второй PIN, открывающий пустое приложение';

  @override
  String get settingsSectionNotifications => 'Уведомления';

  @override
  String get settingsSectionConnection => 'Подключение';

  @override
  String get settingsSectionPrivacy => 'Конфиденциальность';

  @override
  String get settingsReadReceiptsTitle => 'Отчёты о прочтении';

  @override
  String get settingsReadReceiptsSubtitle =>
      'Показывать собеседнику, что сообщения прочитаны (по умолчанию выключено)';

  @override
  String get settingsScreenSecurityTitle => 'Защита экрана';

  @override
  String get settingsScreenSecuritySubtitle =>
      'Блокировать скриншоты и скрывать содержимое в списке недавних приложений';

  @override
  String get settingsSectionBackup => 'Резервная копия ключей';

  @override
  String get settingsSeedPhraseTitle => 'Фраза восстановления';

  @override
  String get settingsSeedPhraseSubtitle =>
      '24 слова для восстановления идентичности';

  @override
  String get settingsBackupExportTitle => 'Резервная копия истории';

  @override
  String get settingsBackupExportSubtitle =>
      'Зашифрованный файл с контактами и сообщениями';

  @override
  String get settingsBackupImportTitle => 'Восстановить из копии';

  @override
  String get settingsBackupImportSubtitle =>
      'Загрузить резервную копию (только вашей идентичности)';

  @override
  String get settingsSectionSafety => 'Защита от злоупотреблений';

  @override
  String get settingsReportAbuseTitle => 'Сообщить о нарушении';

  @override
  String get settingsReportAbuseSubtitle =>
      'Домогательства, мошенничество, угроза ребёнку';

  @override
  String get settingsChildSafetyTitle => 'Стандарты защиты детей';

  @override
  String get settingsChildSafetySubtitle =>
      'Как мы противодействуем насилию над детьми';

  @override
  String get settingsSectionAbout => 'О приложении';

  @override
  String get commonAppName => 'Šepot';

  @override
  String settingsVersion(String version) {
    return 'Версия $version';
  }

  @override
  String get settingsLicenseTitle => 'Лицензия';

  @override
  String get settingsLicenseSubtitle => 'AGPL-3.0';

  @override
  String get settingsPrivacyPolicyTitle => 'Политика конфиденциальности';

  @override
  String get settingsPrivacyPolicySubtitle =>
      'Что мы о вас знаем (и чего не знаем)';

  @override
  String get settingsTermsTitle => 'Условия использования';

  @override
  String get settingsTermsSubtitle => 'sepot.cz/podminky';

  @override
  String get settingsDataDeletionTitle => 'Удаление данных';

  @override
  String get settingsDataDeletionSubtitle => 'Как запросить удаление данных';

  @override
  String get settingsDeleteAllDataButton => 'Удалить все данные';

  @override
  String settingsLicenseBody(String supportEmail) {
    return 'Šepot распространяется по лицензии GNU Affero General Public License версии 3 (AGPL-3.0). Приложение использует библиотеку libsignal, также под AGPL-3.0.\n\nЧтобы получить исходный код этой версии, напишите на $supportEmail, и мы вам его отправим.';
  }

  @override
  String get commonClose => 'Закрыть';

  @override
  String get settingsIdCopied => 'ID скопирован';

  @override
  String settingsFingerprint(String fingerprint) {
    return 'Отпечаток: $fingerprint';
  }

  @override
  String get backupShareSubject => 'Šepot — зашифрованная резервная копия';

  @override
  String backupExportFailed(String error) {
    return 'Не удалось создать резервную копию: $error';
  }

  @override
  String backupRestoredCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Из резервной копии восстановлено $count чата',
      many: 'Из резервной копии восстановлено $count чатов',
      few: 'Из резервной копии восстановлены $count чата',
      one: 'Из резервной копии восстановлен $count чат',
    );
    return '$_temp0';
  }

  @override
  String backupImportFailed(String error) {
    return 'Не удалось восстановить из копии: $error';
  }

  @override
  String get settingsDecoyPinExplain =>
      'При вводе этого PIN приложение откроется пустым — без ваших контактов и сообщений. Он должен отличаться от обычного PIN.';

  @override
  String get commonConfirm => 'Подтвердить';

  @override
  String get commonSet => 'Установить';

  @override
  String get settingsDecoyPinEnabled => 'PIN принуждения установлен';

  @override
  String get settingsDecoyPinConflict =>
      'PIN принуждения должен отличаться от обычного';

  @override
  String get settingsDecoyPinDisabled => 'PIN принуждения отключён';

  @override
  String get settingsSeedPhraseNotFound => 'Фраза восстановления не найдена';

  @override
  String get settingsSeedPhraseWarning =>
      'Эти слова — единственная резервная копия вашей идентичности. Никому их не показывайте!';

  @override
  String settingsSeedWordChip(int index, String word) {
    return '$index. $word';
  }

  @override
  String get settingsAboutTagline => 'Šepot — приватный мессенджер';

  @override
  String get settingsAboutBody =>
      'E2E-шифрованный мессенджер с открытым исходным кодом.\n\nКриптография:\n• X25519 (обмен ключами)\n• XChaCha20-Poly1305 (шифрование)\n• Ed25519 (подписи)\n\n© 2026 ajtak.it';

  @override
  String get settingsDeleteAccountTitle => 'Удалить аккаунт и все данные?';

  @override
  String get settingsDeleteAccountBody =>
      'Это действие необратимо. Все сообщения, контакты и ключи будут удалены с этого устройства, а аккаунт будет снят с регистрации на сервере. Без фразы восстановления вы потеряете свою идентичность навсегда.';

  @override
  String get settingsDeleteAccountServerOffline =>
      'Сервер сейчас недоступен — данные на устройстве удалены, но регистрация на сервере осталась. Остальное удалим по запросу на podpora@sepot.cz.';

  @override
  String get settingsDeleteAllConfirm => 'Удалить всё';

  @override
  String groupsCreateFailed(String error) {
    return 'Не удалось создать группу: $error';
  }

  @override
  String get groupsNewGroupTitle => 'Новая группа';

  @override
  String get groupsCreateAction => 'Создать';

  @override
  String groupsMembersCounter(int selectedCount, int maxMembers) {
    return 'Участники ($selectedCount/$maxMembers)';
  }

  @override
  String get groupsEmptyContactsHint =>
      'Сначала добавьте контакты — группа состоит из людей, с которыми вы уже можете переписываться.';

  @override
  String get groupsMemberMissingAddress =>
      'Нет адреса доставки — запросите новую ссылку';

  @override
  String attachmentSizeBytes(int bytes) {
    return '$bytes Б';
  }

  @override
  String attachmentSizeKb(String kilobytes) {
    return '$kilobytes КБ';
  }

  @override
  String attachmentSizeMb(String megabytes) {
    return '$megabytes МБ';
  }

  @override
  String get attachmentDownloadFailedTapToRetry =>
      'Не удалось скачать — нажмите, чтобы повторить';

  @override
  String get attachmentDownloadFailed => 'Не удалось скачать';

  @override
  String get attachmentDownloading => 'Скачивание…';

  @override
  String get attachmentSharedFileFallbackName => 'файл';

  @override
  String attachmentOpenFailed(String error) {
    return 'Не удалось открыть вложение: $error';
  }

  @override
  String get commonFile => 'Файл';

  @override
  String get chatListNewConversation => 'Новый чат';

  @override
  String get chatListReadReceiptPreview => 'Прочитано';

  @override
  String get chatListDraft => 'Черновик';

  @override
  String get notesTitle => 'Заметки для себя';

  @override
  String get notesSubtitle => 'Только на этом телефоне, в зашифрованном виде';

  @override
  String get callVoice => 'Позвонить';

  @override
  String get callVideo => 'Видеозвонок';

  @override
  String get callStatusRinging => 'Вызов…';

  @override
  String get callIncomingVoice => 'Входящий звонок';

  @override
  String get callIncomingVideo => 'Входящий видеозвонок';

  @override
  String get callStatusConnecting => 'Соединение…';

  @override
  String get callEnded => 'Звонок завершён';

  @override
  String get callEndedBusy => 'Занято';

  @override
  String get callEndedRejected => 'Звонок отклонён';

  @override
  String get callEndedUnanswered => 'Нет ответа';

  @override
  String get callEndedFailed => 'Не удалось соединиться';

  @override
  String get callEncrypted => 'Сквозное шифрование';

  @override
  String get callAccept => 'Принять';

  @override
  String get callReject => 'Отклонить';

  @override
  String get callMute => 'Выключить микрофон';

  @override
  String get callSpeaker => 'Динамик';

  @override
  String get callCamera => 'Выключить камеру';

  @override
  String get callSwitchCamera => 'Сменить камеру';

  @override
  String get callHangUp => 'Завершить';

  @override
  String get callLogMissed => 'Пропущенный звонок';

  @override
  String get callLogUnanswered => 'Звонок без ответа';

  @override
  String get callLogRejected => 'Отклонённый звонок';

  @override
  String get callLogBusy => 'Занято';

  @override
  String get callLogFailed => 'Звонок не удался';

  @override
  String callLogVoice(String duration) {
    return 'Звонок · $duration';
  }

  @override
  String callLogVideo(String duration) {
    return 'Видеозвонок · $duration';
  }

  @override
  String get chatListTimeNow => 'сейчас';

  @override
  String chatListTimeMinutes(int minutes) {
    return '$minutes мин';
  }

  @override
  String get qrScanTitle => 'Сканировать QR-код';

  @override
  String get qrScanInstruction => 'Наведите камеру на QR-код контакта';

  @override
  String get qrScanHint => 'QR-код содержит открытый ключ контакта';

  @override
  String get qrNewContactTitle => 'Новый контакт';

  @override
  String qrContactAdded(String name) {
    return 'Контакт $name добавлен';
  }

  @override
  String get commonAdd => 'Добавить';

  @override
  String get onboardingWelcomeTitle => 'Добро пожаловать в Šepot';

  @override
  String get onboardingWelcomeSubtitle =>
      'Приватный мессенджер со сквозным шифрованием.\nБез номера телефона. Без электронной почты.\nТолько ваши ключи.';

  @override
  String get onboardingStart => 'Начать';

  @override
  String get onboardingRestoreExisting =>
      'У меня уже есть аккаунт — восстановить из фразы';

  @override
  String get onboardingEncryptionTitle => 'Ваши сообщения, ваши ключи';

  @override
  String get onboardingFeatureSignalTitle => 'Протокол Signal';

  @override
  String get onboardingFeatureSignalSubtitle =>
      'X3DH + Double Ratchet, forward secrecy';

  @override
  String get onboardingFeaturePqTitle => 'Постквантовая защита';

  @override
  String get onboardingFeaturePqSubtitle => 'Kyber (PQXDH) с первого сообщения';

  @override
  String get onboardingFeatureLocalKeysTitle =>
      'Ключи только на вашем устройстве';

  @override
  String get onboardingFeatureLocalKeysSubtitle => 'Ни у одного сервера их нет';

  @override
  String get onboardingFeatureDisappearingSubtitle => 'Удаляются автоматически';

  @override
  String get commonContinue => 'Продолжить';

  @override
  String get onboardingIdentityTitle => 'Создайте свою идентичность';

  @override
  String get onboardingIdentitySubtitle =>
      'Без почты и телефона. Только имя и криптографические ключи.';

  @override
  String get onboardingDisplayNameLabel => 'Отображаемое имя';

  @override
  String get onboardingDisplayNameHint => 'Например, Иван';

  @override
  String onboardingSeedPhraseWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'эти $count слова',
      many: 'эти $count слов',
      few: 'эти $count слова',
      one: 'это $count слово',
    );
    return 'Запишите $_temp0. Это единственная резервная копия ваших ключей!';
  }

  @override
  String get onboardingSeedSavedConfirm =>
      'Подтверждаю: фраза надёжно сохранена';

  @override
  String get onboardingGenerateKeys => 'Сгенерировать ключи';

  @override
  String get verifyMismatchTitle => 'Номера НЕ СОВПАДАЮТ';

  @override
  String verifyMatchBody(String contactName) {
    return 'Ключи совпадают. $contactName — подтверждённый контакт.';
  }

  @override
  String get verifyMismatchBody =>
      'Номера безопасности не совпадают. Возможно, кто-то перехватывает соединение (MITM), либо вы сканируете код другого контакта. НЕ отправляйте конфиденциальные сообщения и повторите сверку по другому каналу.';

  @override
  String get commonUnderstood => 'Понятно';

  @override
  String get verifyManualConfirmTitle => 'Отметить как подтверждённый?';

  @override
  String get verifyManualConfirmBody =>
      'Подтверждайте только в том случае, если вы сверили цифры с собеседником по другому надёжному каналу (лично, по звонку…) и они совпадают.';

  @override
  String get verifyManualConfirmAction => 'Совпадают, подтвердить';

  @override
  String get verifyTitle => 'Подтверждение контакта';

  @override
  String get verifyContactVerifiedBanner => 'Контакт подтверждён';

  @override
  String verifyIntro(String contactName) {
    return 'Сравните этот номер с тем, который видит $contactName. Если номера совпадают, ваше шифрование никто не прослушивает. Быстрее всего — взаимно отсканировать QR-коды.';
  }

  @override
  String get verifyScanButton => 'Сканировать код собеседника';

  @override
  String get verifyManualButton => 'Цифры совпадают — отметить вручную';

  @override
  String get verifyUnverifyButton => 'Отменить подтверждение';

  @override
  String get verifyScanScreenTitle => 'Отсканируйте QR для сверки';

  @override
  String get reportTitle => 'Пожаловаться';

  @override
  String get reportSubmitted => 'Жалоба отправлена';

  @override
  String get reportSubmittedChildSafety =>
      'Такие жалобы мы рассматриваем в первую очередь. Если ребёнок в непосредственной опасности, немедленно обратитесь в местную полицию или на телефон доверия.';

  @override
  String get reportSubmittedThanks =>
      'Спасибо. Мы рассмотрим её как можно скорее.';

  @override
  String get commonDone => 'Готово';

  @override
  String get reportPanelE2eNotice =>
      'Сообщения защищены сквозным шифрованием, поэтому их содержимое нам не видно даже сейчас. Пожалуйста, опишите своими словами, что произошло. Не вставляйте сюда содержимое сообщений или ссылки на него — мы не имеем права его хранить, и для рассмотрения оно нам не нужно.';

  @override
  String get reportPanelCsamWarning =>
      'НЕ ОТПРАВЛЯЙТЕ нам материалы, изображающие сексуальное насилие над детьми. Их хранение уголовно наказуемо в том числе для нас, и для жалобы они не нужны. Такие материалы следует передавать напрямую в местную полицию или на официальную горячую линию по борьбе с CSAM. Нам напишите только то, что произошло, — мы заблокируем аккаунт и передадим дело дальше.';

  @override
  String get reportPanelIpNotice =>
      'Жалоба отправляется не через релей, а на наш веб-сервер. При отправке он узнает ваш IP-адрес.';

  @override
  String get reportCategoryHeading => 'О чём жалоба';

  @override
  String get reportDescriptionHeading => 'Что произошло';

  @override
  String get reportAttachContactId => 'Приложить ID нарушителя';

  @override
  String reportAttachContactIdNamed(String contactName) {
    return 'Приложить ID контакта $contactName';
  }

  @override
  String get reportReplyToHeading => 'Как с вами связаться (необязательно)';

  @override
  String get reportReplyToHint => 'e-mail на случай уточняющих вопросов';

  @override
  String get reportSubmitButton => 'Отправить жалобу';

  @override
  String get contactsTitle => 'Контакты';

  @override
  String get contactsAddContact => 'Добавить контакт';

  @override
  String get contactsSearchHint => 'Поиск контактов...';

  @override
  String get contactsEmpty => 'Пока нет контактов';

  @override
  String get contactsNoResults => 'Ничего не найдено';

  @override
  String get contactsShareCardTitle => 'Поделитесь своим Šepot ID';

  @override
  String get contactsShareCardSubtitle =>
      'Покажите QR-код или отправьте ссылку';

  @override
  String get contactsAddDialogPrompt =>
      'Вставьте строку обмена (share string) контакта:';

  @override
  String get contactsShareStringHint => 'Вставить share string...';

  @override
  String get contactsInvalidShareString => 'Недействительный share string';

  @override
  String contactsAdded(String name) {
    return 'Контакт $name добавлен';
  }

  @override
  String get verifyContactSubtitle => 'Сверка номера безопасности';

  @override
  String get contactsDeleteContact => 'Удалить контакт';

  @override
  String get pinConfirmTitle => 'Подтвердите PIN';

  @override
  String get pinSetupTitle => 'Задайте PIN';

  @override
  String get pinConfirmSubtitle => 'Введите PIN ещё раз для подтверждения';

  @override
  String get pinSetupSubtitle => '6-значный PIN для разблокировки приложения';

  @override
  String get pinSetupFailed => 'Не удалось установить PIN. Попробуйте ещё раз.';

  @override
  String get pinMismatchRetry => 'PIN-коды не совпадают. Попробуйте ещё раз.';

  @override
  String get pinChangeCurrentTitle => 'Введите текущий PIN';

  @override
  String get pinChangeCurrentSubtitle => 'Мы проверим его, разблокировав ключ';

  @override
  String get pinChangeNewTitle => 'Введите новый PIN';

  @override
  String get pinChangeNewSubtitle => '6 цифр';

  @override
  String get pinChangeConfirmTitle => 'Подтвердите новый PIN';

  @override
  String get pinChangeConfirmSubtitle => 'Введите его ещё раз';

  @override
  String get pinWrong => 'Неверный PIN.';

  @override
  String get pinChangeMustDiffer => 'Новый PIN должен отличаться от текущего.';

  @override
  String get pinMismatch => 'PIN-коды не совпадают.';

  @override
  String get pinDecoyConflict =>
      'Этот PIN уже используется режимом принуждения. Выберите другой.';

  @override
  String get pinChangeFailed => 'Не удалось изменить PIN. Попробуйте ещё раз.';

  @override
  String get pinChanged => 'PIN изменён';

  @override
  String get errorCryptoInitTitle => 'Криптографическое ядро не запустилось';

  @override
  String get errorStartupTitle => 'Šepot не запустился';

  @override
  String get errorScreenNotRenderedTitle => 'Этот экран не отрисовался';

  @override
  String get errorStartupBody =>
      'Что-то пошло не так прямо при запуске. Пожалуйста, отправьте мне этот текст (удерживайте палец и скопируйте) — это поможет найти ошибку.';

  @override
  String get errorContactFooter =>
      'sepot.cz · напишите мне через контакты на сайте';

  @override
  String get pinUnlockTitle => 'Разблокируйте Šepot';

  @override
  String get pinEnterPin => 'Введите PIN';

  @override
  String get pinUnlockWithBiometrics => 'Разблокировать биометрией';

  @override
  String get pinWrong2 => 'Неверный PIN';

  @override
  String get pinUnlockError => 'Ошибка разблокировки';

  @override
  String get pushTitle => 'Push-уведомления';

  @override
  String get pushModeOffDesc =>
      'Сообщения загрузятся только после открытия приложения.';

  @override
  String get pushModeUp => 'UnifiedPush (без Google)';

  @override
  String get pushModeUpDesc =>
      'Без сервисов Google — требуется приложение ntfy (F-Droid/Play).';

  @override
  String get pushModeFcm => 'Google (FCM, по умолчанию)';

  @override
  String get pushModeFcmDesc =>
      'Надёжно и без дополнительных приложений. Push-токен устройства передаётся Google; содержимое сообщений — никогда.';

  @override
  String pushSetupFailed(String error) {
    return 'Не удалось настроить push: $error';
  }

  @override
  String get pushHintOff =>
      'Сообщения придут, только когда откроешь Šepot — сигналы не настроены.';

  @override
  String get pushHintFailed =>
      'Сигналы не работают: сообщения увидишь только после открытия Šepot.';

  @override
  String get pushRegistrationFailed =>
      'Сигналы не приходят — дистрибьютор отклонил регистрацию. Попробуй выключить и снова включить push.';

  @override
  String get pushNoDistributorTitle => 'Нет дистрибьютора';

  @override
  String get pushNoDistributorBody =>
      'Для уведомлений без сервисов Google установите дистрибьютор UnifiedPush, например ntfy (F-Droid или Play). Затем включите push снова.';

  @override
  String get commonOk => 'OK';

  @override
  String get pushPickDistributorTitle => 'Выберите дистрибьютора';

  @override
  String pushSubtitleUnifiedPush(String distributor) {
    return 'UnifiedPush · $distributor';
  }

  @override
  String get pushNoDistributorFallback => 'без дистрибьютора';

  @override
  String get pushSubtitleFcm => 'Google (FCM)';

  @override
  String get restoreErrorNameRequired => 'Введите отображаемое имя.';

  @override
  String restoreErrorWordCount(int wordCount, int requiredWords) {
    String _temp0 = intl.Intl.pluralLogic(
      wordCount,
      locale: localeName,
      other: 'Во фразе $wordCount слова, а нужно $requiredWords.',
      many: 'Во фразе $wordCount слов, а нужно $requiredWords.',
      few: 'Во фразе $wordCount слова, а нужно $requiredWords.',
      one: 'Во фразе $wordCount слово, а нужно $requiredWords.',
    );
    return '$_temp0';
  }

  @override
  String get restoreErrorInvalidPhrase =>
      'Фраза недействительна — проверьте слова и их порядок.';

  @override
  String restoreErrorFailed(String error) {
    return 'Не удалось восстановить: $error';
  }

  @override
  String get restoreTitle => 'Восстановить аккаунт';

  @override
  String get restoreHeading => 'Введите свою фразу восстановления';

  @override
  String restoreIntro(int wordCount) {
    String _temp0 = intl.Intl.pluralLogic(
      wordCount,
      locale: localeName,
      other: '$wordCount слова',
      many: '$wordCount слов',
      few: '$wordCount слова',
      one: '$wordCount слово',
    );
    return '$_temp0 из резервной копии, сделанной при создании аккаунта. Фраза восстановит вашу идентичность (тот же код SEP, контакты по-прежнему вас узнают).';
  }

  @override
  String get restoreHistoryWarning =>
      'История сообщений не восстановится — она хранится только на исходном устройстве.';

  @override
  String get restorePhraseHint => 'слово1 слово2 слово3 …';

  @override
  String restoreWordCountHelper(int wordCount, int requiredWords) {
    return '$wordCount / $requiredWords слов';
  }

  @override
  String chatListArchivedCount(int count) {
    return 'Архив ($count)';
  }

  @override
  String get chatListEmptyTitle => 'Пока нет чатов';

  @override
  String get chatListEmptySubtitle => 'Добавьте контакт и начните шептаться!';

  @override
  String get chatListUnmute => 'Включить звук';

  @override
  String get chatListMute => 'Отключить звук';

  @override
  String get chatListArchive => 'Архивировать';

  @override
  String get qrShareTitle => 'Мой Šepot ID';

  @override
  String get qrShareConnectingTitle => 'Подключение к релею…';

  @override
  String get qrShareConnectingBody =>
      'Ваш QR-код и ссылка появятся, как только Šepot подключится в первый раз. Подождите пару секунд.';

  @override
  String get qrIdentityNotFound => 'Идентичность не найдена';

  @override
  String get commonCopiedToClipboard => 'Скопировано в буфер обмена';

  @override
  String qrShareInviteMessage(String shareString) {
    return 'Добавьте меня в Šepot!\n\n$shareString';
  }

  @override
  String get commonShare => 'Поделиться';

  @override
  String get qrShareInfo =>
      'Контакт отсканирует ваш QR-код или вставит строку обмена в приложение.';

  @override
  String get reportCategoryChildSafety => 'Угроза ребёнку';

  @override
  String get reportCategoryChildSafetyHint =>
      'Опишите ситуацию своими словами. Не вставляйте содержимое сообщений или ссылки на материалы.';

  @override
  String get reportCategoryHarassment => 'Домогательства или угрозы';

  @override
  String get reportCategoryHarassmentHint =>
      'Кто-то запугивает вас, угрожает или домогается.';

  @override
  String get reportCategorySpam => 'Спам';

  @override
  String get reportCategorySpamHint =>
      'Нежелательные сообщения, массовые рассылки.';

  @override
  String get reportCategoryFraud => 'Мошенничество';

  @override
  String get reportCategoryFraudHint =>
      'Попытка выманить деньги, ключи или личные данные.';

  @override
  String get reportCategoryOther => 'Другое';

  @override
  String get reportCategoryOtherHint => 'Что-то ещё, о чём нам стоит знать.';

  @override
  String get reportErrorEmptyDescription =>
      'Пожалуйста, напишите, что произошло.';

  @override
  String reportErrorConnection(String supportEmail) {
    return 'Не удалось связаться с сервером. Попробуйте ещё раз или напишите на $supportEmail.';
  }

  @override
  String reportErrorRateLimited(String supportEmail) {
    return 'Из вашей сети поступило слишком много жалоб. Попробуйте через час или напишите на $supportEmail.';
  }

  @override
  String reportErrorServer(int statusCode, String supportEmail) {
    return 'Не удалось отправить (код $statusCode). Пожалуйста, напишите на $supportEmail.';
  }

  @override
  String get settingsAutoLockNever => 'Никогда';

  @override
  String get settingsAutoLock1min => 'Через 1 минуту';

  @override
  String get settingsAutoLock15min => 'Через 15 минут';

  @override
  String torToggleFailed(String error) {
    return 'Не удалось переключить Tor: $error';
  }

  @override
  String get torConnectionTitle => 'Подключение через Tor';

  @override
  String get torDialogBody =>
      'Трафик на сервер пойдёт через сеть Tor (это скроет ваш IP-адрес). Требуется установленное и запущенное приложение Orbot с активным SOCKS-прокси на порту 9050.\n\nБез работающего Orbot сообщения не будут ни отправляться, ни приниматься. Соединение обычно медленнее.';

  @override
  String get commonTurnOn => 'Включить';

  @override
  String get torSubtitleOff =>
      'Прямое зашифрованное соединение (WSS). Включите, чтобы скрыть IP через Tor.';

  @override
  String get torStatusConnected => 'Подключено через Tor (.onion).';

  @override
  String get torStatusConnecting => 'Подключение через Tor… (Orbot запущен?)';

  @override
  String get torStatusWaiting => 'Через Tor — ожидание Orbot (SOCKS 9050).';

  @override
  String get biometricsPinRequiredFirst =>
      'Сначала задайте PIN — биометрия лишь дополняет его.';

  @override
  String get biometricsStorageLocked =>
      'Хранилище заблокировано — разблокируйте приложение PIN-кодом.';

  @override
  String get biometricsNotAvailable => 'На устройстве не настроена биометрия.';

  @override
  String get biometricsEnrollPromptReason =>
      'Подтвердите включение биометрической разблокировки';

  @override
  String biometricsSetupFailed(String error) {
    return 'Не удалось настроить биометрию: $error';
  }

  @override
  String get biometricsTileTitle => 'Биометрия';

  @override
  String get biometricsTileSubtitle =>
      'Разблокировка отпечатком пальца / лицом (PIN остаётся запасным способом)';

  @override
  String get backupErrorCorruptedFile => 'Файл резервной копии повреждён';

  @override
  String get backupErrorUnknownFormat =>
      'Нераспознанный формат резервной копии';

  @override
  String get backupErrorWrongIdentity =>
      'Не удалось расшифровать копию — она принадлежит другой идентичности?';

  @override
  String attachmentSharedImageFilename(String ext) {
    return 'sepot-image.$ext';
  }

  @override
  String get attachmentDecryptFailed => 'Не удалось расшифровать вложение';

  @override
  String get pushActionOpen => 'Открыть';

  @override
  String get pushChannelMessagesName => 'Сообщения';

  @override
  String get pushChannelMessagesDescription =>
      'Уведомления о новых сообщениях (без содержимого)';

  @override
  String pushNewMessageFrom(String senderName) {
    return 'Новое сообщение от $senderName';
  }

  @override
  String get pushNewMessages => 'У вас новые сообщения';

  @override
  String get archiveTitle => 'Архив';

  @override
  String get archiveEmpty => 'Нет архивированных чатов';

  @override
  String get archiveUnarchive => 'Вернуть из архива';

  @override
  String restoreErrorMnemonicWordCount(int count, int expected) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Во фразе $count слова, ожидается $expected',
      many: 'Во фразе $count слов, ожидается $expected',
      few: 'Во фразе $count слова, ожидается $expected',
      one: 'Во фразе $count слово, ожидается $expected',
    );
    return '$_temp0';
  }

  @override
  String restoreErrorInvalidMnemonic(String message) {
    return 'Недействительная фраза: $message';
  }

  @override
  String get contactsErrorAlreadyExists => 'Контакт уже существует';

  @override
  String get commonAppTagline => 'Приватный мессенджер';

  @override
  String get commonE2eBadgeCompact => 'E2E';

  @override
  String get commonE2eBadgeFull => 'Сквозное шифрование';

  @override
  String get photoPreviewCaptionHint => 'Добавить подпись…';

  @override
  String get photoPreviewDraw => 'Рисовать';

  @override
  String get photoPreviewAddText => 'Добавить текст';

  @override
  String get photoPreviewRotate => 'Повернуть';

  @override
  String get photoPreviewUndo => 'Отменить';

  @override
  String get photoPreviewSend => 'Отправить';

  @override
  String get photoPreviewTextDialogTitle => 'Текст на фото';

  @override
  String get photoPreviewRemoveText => 'Удалить';

  @override
  String get photoPreviewDecodeFailed => 'Не удалось загрузить фото';

  @override
  String get chatActionInfo => 'Сведения о сообщении';

  @override
  String get messageInfoSent => 'Отправлено';

  @override
  String get messageInfoDelivered => 'Доставлено';

  @override
  String get messageInfoRead => 'Прочитано';

  @override
  String get messageInfoPending => 'ещё нет';

  @override
  String get messageInfoReadReceiptsOff =>
      'Время прочтения видно, только если вы сами делитесь отчётами о прочтении (Настройки).';

  @override
  String chatStatusReadAt(String time) {
    return 'Прочитано $time';
  }

  @override
  String chatStatusDeliveredAt(String time) {
    return 'Доставлено $time';
  }

  @override
  String get groupsAddMembers => 'Добавить участников';

  @override
  String get groupsAddMembersAction => 'Добавить';

  @override
  String groupsAddMembersFailed(String error) {
    return 'Не удалось добавить: $error';
  }

  @override
  String get groupsNoContactsToAdd =>
      'Все ваши контакты уже в группе. Сначала добавьте нового человека в контакты по QR-коду.';

  @override
  String get navChats => 'Чаты';

  @override
  String get chatListNewChat => 'Новый чат';

  @override
  String get chatListSearchHint => 'Поиск по чатам и сообщениям';

  @override
  String get chatFilterAll => 'Все';

  @override
  String get chatFilterUnread => 'Непрочитанные';

  @override
  String get chatFilterGroups => 'Группы';

  @override
  String get chatFilterArchive => 'Архив';

  @override
  String get chatListNoResults => 'Ничего не найдено.';

  @override
  String get chatListFilterEmpty => 'Здесь пока ничего нет.';

  @override
  String get chatListPin => 'Закрепить';

  @override
  String get chatListUnpin => 'Открепить';

  @override
  String get chatOpenProfile => 'Открыть профиль';

  @override
  String get groupsProfile => 'Информация о группе';

  @override
  String get chatSearchHint => 'Поиск в чате';

  @override
  String get chatSearchNoMatches => 'Нет';

  @override
  String chatSearchCounter(int current, int total) {
    return '$current из $total';
  }

  @override
  String get chatSearchOlder => 'Предыдущее совпадение';

  @override
  String get chatSearchNewer => 'Следующее совпадение';

  @override
  String chatUnreadDivider(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count новых сообщений',
      few: '$count новых сообщения',
      one: '$count новое сообщение',
    );
    return '$_temp0';
  }

  @override
  String get chatJumpToLatest => 'К последним сообщениям';

  @override
  String get chatAttach => 'Прикрепить';

  @override
  String get chatSend => 'Отправить';

  @override
  String get chatRecordVoice => 'Записать голосовое';

  @override
  String get profileSharedMedia => 'Общие медиа';

  @override
  String get profileMessage => 'Написать';

  @override
  String get profileSearch => 'Поиск';

  @override
  String get profileUnmute => 'Включить звук';

  @override
  String get profileDisappearing => 'Исчезание';

  @override
  String get profileCommonGroups => 'Общие группы';

  @override
  String get profileSafetyNumber => 'Код безопасности';

  @override
  String get profileSafetyNumberHint => 'Сравните лично или по QR-коду';

  @override
  String get profileVerifiedInPerson => 'Проверено лично';

  @override
  String get profileVerifyNow => 'Проверить контакт';

  @override
  String get profileAdd => 'Добавить';

  @override
  String profileGroupSubtitle(String members, String date) {
    return 'Группа · $members · создана $date';
  }

  @override
  String profileMembersOfMax(int count, int max) {
    return '$count из $max';
  }

  @override
  String get chatTyping => 'печатает…';

  @override
  String chatTypingNamed(String name) {
    return '$name печатает…';
  }

  @override
  String get chatTypingSeveral => 'Несколько человек печатают…';

  @override
  String get settingsTypingTitle => 'Индикатор набора';

  @override
  String get settingsTypingSubtitle =>
      'Взаимно — не делитесь, не видите (по умолчанию выкл.)';

  @override
  String get pollAttach => 'Опрос';

  @override
  String get pollCreateTitle => 'Новый опрос';

  @override
  String get pollQuestion => 'Вопрос';

  @override
  String pollOptionHint(int number) {
    return 'Вариант $number';
  }

  @override
  String get pollAddOption => 'Добавить вариант';

  @override
  String get pollRemoveOption => 'Удалить вариант';

  @override
  String get pollAllowMultiple => 'Разрешить несколько ответов';

  @override
  String get pollSingle => 'Опрос';

  @override
  String get pollMulti => 'Опрос, несколько ответов';

  @override
  String pollVoters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count голосов',
      few: '$count голоса',
      one: '$count голос',
      zero: 'пока нет голосов',
    );
    return '$_temp0';
  }

  @override
  String pollFallback(String question) {
    return 'Опрос: $question';
  }

  @override
  String get pollFallbackUpdate => 'Обновите Šepot, чтобы голосовать.';

  @override
  String get profilePhotoEdit => 'Изменить фото профиля';

  @override
  String get profilePhotoPick => 'Выбрать фото';

  @override
  String get profilePhotoRemove => 'Удалить фото';

  @override
  String get profilePhotoHint =>
      'Фото увидят только ваши собеседники — зашифровано, как и сообщения. Геоданные и метаданные не отправляются.';

  @override
  String profilePhotoFailed(String error) {
    return 'Не удалось установить фото: $error';
  }
}
