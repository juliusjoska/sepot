// This is a generated file - do not edit.
//
// Generated from sepot.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'sepot.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'sepot.pbenum.dart';

class Envelope extends $pb.GeneratedMessage {
  factory Envelope({
    $core.List<$core.int>? dstAddress,
    $core.List<$core.int>? msgUuid,
    ContentHint? contentHint,
    $core.List<$core.int>? payload,
  }) {
    final result = create();
    if (dstAddress != null) result.dstAddress = dstAddress;
    if (msgUuid != null) result.msgUuid = msgUuid;
    if (contentHint != null) result.contentHint = contentHint;
    if (payload != null) result.payload = payload;
    return result;
  }

  Envelope._();

  factory Envelope.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Envelope.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Envelope',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'dstAddress', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'msgUuid', $pb.PbFieldType.OY)
    ..aE<ContentHint>(3, _omitFieldNames ? '' : 'contentHint',
        enumValues: ContentHint.values)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Envelope clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Envelope copyWith(void Function(Envelope) updates) =>
      super.copyWith((message) => updates(message as Envelope)) as Envelope;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Envelope create() => Envelope._();
  @$core.override
  Envelope createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Envelope getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Envelope>(create);
  static Envelope? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get dstAddress => $_getN(0);
  @$pb.TagNumber(1)
  set dstAddress($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDstAddress() => $_has(0);
  @$pb.TagNumber(1)
  void clearDstAddress() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get msgUuid => $_getN(1);
  @$pb.TagNumber(2)
  set msgUuid($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMsgUuid() => $_has(1);
  @$pb.TagNumber(2)
  void clearMsgUuid() => $_clearField(2);

  @$pb.TagNumber(3)
  ContentHint get contentHint => $_getN(2);
  @$pb.TagNumber(3)
  set contentHint(ContentHint value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasContentHint() => $_has(2);
  @$pb.TagNumber(3)
  void clearContentHint() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get payload => $_getN(3);
  @$pb.TagNumber(4)
  set payload($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPayload() => $_has(3);
  @$pb.TagNumber(4)
  void clearPayload() => $_clearField(4);
}

class Ack extends $pb.GeneratedMessage {
  factory Ack({
    $core.List<$core.int>? msgUuid,
  }) {
    final result = create();
    if (msgUuid != null) result.msgUuid = msgUuid;
    return result;
  }

  Ack._();

  factory Ack.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Ack.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Ack',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'msgUuid', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ack clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ack copyWith(void Function(Ack) updates) =>
      super.copyWith((message) => updates(message as Ack)) as Ack;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Ack create() => Ack._();
  @$core.override
  Ack createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Ack getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Ack>(create);
  static Ack? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get msgUuid => $_getN(0);
  @$pb.TagNumber(1)
  set msgUuid($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMsgUuid() => $_has(0);
  @$pb.TagNumber(1)
  void clearMsgUuid() => $_clearField(1);
}

class Receipt extends $pb.GeneratedMessage {
  factory Receipt({
    $core.List<$core.int>? msgUuid,
    Receipt_Status? status,
  }) {
    final result = create();
    if (msgUuid != null) result.msgUuid = msgUuid;
    if (status != null) result.status = status;
    return result;
  }

  Receipt._();

  factory Receipt.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Receipt.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Receipt',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'msgUuid', $pb.PbFieldType.OY)
    ..aE<Receipt_Status>(2, _omitFieldNames ? '' : 'status',
        enumValues: Receipt_Status.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Receipt clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Receipt copyWith(void Function(Receipt) updates) =>
      super.copyWith((message) => updates(message as Receipt)) as Receipt;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Receipt create() => Receipt._();
  @$core.override
  Receipt createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Receipt getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Receipt>(create);
  static Receipt? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get msgUuid => $_getN(0);
  @$pb.TagNumber(1)
  set msgUuid($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMsgUuid() => $_has(0);
  @$pb.TagNumber(1)
  void clearMsgUuid() => $_clearField(1);

  @$pb.TagNumber(2)
  Receipt_Status get status => $_getN(1);
  @$pb.TagNumber(2)
  set status(Receipt_Status value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);
}

class Auth extends $pb.GeneratedMessage {
  factory Auth({
    $core.List<$core.int>? deviceUuid,
    $core.List<$core.int>? nonceClient,
  }) {
    final result = create();
    if (deviceUuid != null) result.deviceUuid = deviceUuid;
    if (nonceClient != null) result.nonceClient = nonceClient;
    return result;
  }

  Auth._();

  factory Auth.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Auth.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Auth',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'deviceUuid', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'nonceClient', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Auth clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Auth copyWith(void Function(Auth) updates) =>
      super.copyWith((message) => updates(message as Auth)) as Auth;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Auth create() => Auth._();
  @$core.override
  Auth createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Auth getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Auth>(create);
  static Auth? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get deviceUuid => $_getN(0);
  @$pb.TagNumber(1)
  set deviceUuid($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceUuid() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceUuid() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get nonceClient => $_getN(1);
  @$pb.TagNumber(2)
  set nonceClient($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNonceClient() => $_has(1);
  @$pb.TagNumber(2)
  void clearNonceClient() => $_clearField(2);
}

class Challenge extends $pb.GeneratedMessage {
  factory Challenge({
    $core.List<$core.int>? nonceServer,
  }) {
    final result = create();
    if (nonceServer != null) result.nonceServer = nonceServer;
    return result;
  }

  Challenge._();

  factory Challenge.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Challenge.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Challenge',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'nonceServer', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Challenge clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Challenge copyWith(void Function(Challenge) updates) =>
      super.copyWith((message) => updates(message as Challenge)) as Challenge;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Challenge create() => Challenge._();
  @$core.override
  Challenge createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Challenge getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Challenge>(create);
  static Challenge? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get nonceServer => $_getN(0);
  @$pb.TagNumber(1)
  set nonceServer($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNonceServer() => $_has(0);
  @$pb.TagNumber(1)
  void clearNonceServer() => $_clearField(1);
}

class AuthProof extends $pb.GeneratedMessage {
  factory AuthProof({
    $core.List<$core.int>? signature,
  }) {
    final result = create();
    if (signature != null) result.signature = signature;
    return result;
  }

  AuthProof._();

  factory AuthProof.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AuthProof.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AuthProof',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'signature', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AuthProof clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AuthProof copyWith(void Function(AuthProof) updates) =>
      super.copyWith((message) => updates(message as AuthProof)) as AuthProof;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AuthProof create() => AuthProof._();
  @$core.override
  AuthProof createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AuthProof getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AuthProof>(create);
  static AuthProof? _defaultInstance;

  /// XEdDSA podpis device klíčem nad: nonce_client || nonce_server || "sepot-auth-v1"
  @$pb.TagNumber(1)
  $core.List<$core.int> get signature => $_getN(0);
  @$pb.TagNumber(1)
  set signature($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSignature() => $_has(0);
  @$pb.TagNumber(1)
  void clearSignature() => $_clearField(1);
}

class PrekeysLow extends $pb.GeneratedMessage {
  factory PrekeysLow({
    $core.int? remaining,
  }) {
    final result = create();
    if (remaining != null) result.remaining = remaining;
    return result;
  }

  PrekeysLow._();

  factory PrekeysLow.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PrekeysLow.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PrekeysLow',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'remaining', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrekeysLow clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrekeysLow copyWith(void Function(PrekeysLow) updates) =>
      super.copyWith((message) => updates(message as PrekeysLow)) as PrekeysLow;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PrekeysLow create() => PrekeysLow._();
  @$core.override
  PrekeysLow createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PrekeysLow getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PrekeysLow>(create);
  static PrekeysLow? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get remaining => $_getIZ(0);
  @$pb.TagNumber(1)
  set remaining($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRemaining() => $_has(0);
  @$pb.TagNumber(1)
  void clearRemaining() => $_clearField(1);
}

class Error extends $pb.GeneratedMessage {
  factory Error({
    $core.int? code,
    $core.String? message,
  }) {
    final result = create();
    if (code != null) result.code = code;
    if (message != null) result.message = message;
    return result;
  }

  Error._();

  factory Error.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Error.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Error',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'code', fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Error clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Error copyWith(void Function(Error) updates) =>
      super.copyWith((message) => updates(message as Error)) as Error;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Error create() => Error._();
  @$core.override
  Error createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Error getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Error>(create);
  static Error? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get code => $_getIZ(0);
  @$pb.TagNumber(1)
  set code($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);
}

class Ping extends $pb.GeneratedMessage {
  factory Ping() => create();

  Ping._();

  factory Ping.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Ping.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Ping',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ping clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ping copyWith(void Function(Ping) updates) =>
      super.copyWith((message) => updates(message as Ping)) as Ping;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Ping create() => Ping._();
  @$core.override
  Ping createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Ping getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Ping>(create);
  static Ping? _defaultInstance;
}

class Pong extends $pb.GeneratedMessage {
  factory Pong() => create();

  Pong._();

  factory Pong.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Pong.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Pong',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Pong clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Pong copyWith(void Function(Pong) updates) =>
      super.copyWith((message) => updates(message as Pong)) as Pong;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Pong create() => Pong._();
  @$core.override
  Pong createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Pong getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Pong>(create);
  static Pong? _defaultInstance;
}

/// Potvrzení úspěšné WS autentizace — teprve po něm smí klient hlásit
/// „připojeno" a posílat obálky (fronta se vylévá hned po něm).
class AuthOk extends $pb.GeneratedMessage {
  factory AuthOk() => create();

  AuthOk._();

  factory AuthOk.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AuthOk.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AuthOk',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AuthOk clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AuthOk copyWith(void Function(AuthOk) updates) =>
      super.copyWith((message) => updates(message as AuthOk)) as AuthOk;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AuthOk create() => AuthOk._();
  @$core.override
  AuthOk createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AuthOk getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AuthOk>(create);
  static AuthOk? _defaultInstance;
}

/// ── Push registrace (§4) ───────────────────────────────────────────────
/// Posílá se JEN přes autentizovaný WS (endpoint se nikdy neposílá
/// neautentizovaně a jde stejnou cestou jako provoz — klidně přes Tor).
/// Relay endpoint NIKDY neloguje. Budíček je vždy prázdný „ťuk" — žádný
/// obsah ani odesílatel neopustí sealed-sender kanál.
class RegisterPush extends $pb.GeneratedMessage {
  factory RegisterPush({
    RegisterPush_Platform? platform,
    $core.List<$core.int>? endpoint,
    $core.List<$core.int>? voipToken,
  }) {
    final result = create();
    if (platform != null) result.platform = platform;
    if (endpoint != null) result.endpoint = endpoint;
    if (voipToken != null) result.voipToken = voipToken;
    return result;
  }

  RegisterPush._();

  factory RegisterPush.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RegisterPush.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RegisterPush',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..aE<RegisterPush_Platform>(1, _omitFieldNames ? '' : 'platform',
        enumValues: RegisterPush_Platform.values)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'endpoint', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'voipToken', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterPush clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RegisterPush copyWith(void Function(RegisterPush) updates) =>
      super.copyWith((message) => updates(message as RegisterPush))
          as RegisterPush;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RegisterPush create() => RegisterPush._();
  @$core.override
  RegisterPush createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RegisterPush getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RegisterPush>(create);
  static RegisterPush? _defaultInstance;

  @$pb.TagNumber(1)
  RegisterPush_Platform get platform => $_getN(0);
  @$pb.TagNumber(1)
  set platform(RegisterPush_Platform value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPlatform() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlatform() => $_clearField(1);

  /// UnifiedPush/WebPush endpoint URL (utf-8 bytes), nebo FCM/APNs token.
  /// Prázdné, když platform=NONE.
  @$pb.TagNumber(2)
  $core.List<$core.int> get endpoint => $_getN(1);
  @$pb.TagNumber(2)
  set endpoint($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEndpoint() => $_has(1);
  @$pb.TagNumber(2)
  void clearEndpoint() => $_clearField(2);

  /// iOS: PushKit VoIP token pro příchozí hovory (vedle běžného APNs tokenu
  /// v `endpoint`). Prázdné = zařízení VoIP push nemá.
  @$pb.TagNumber(3)
  $core.List<$core.int> get voipToken => $_getN(2);
  @$pb.TagNumber(3)
  set voipToken($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasVoipToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearVoipToken() => $_clearField(3);
}

/// Dočasné údaje k TURN serveru pro hovory (REST schéma coturnu). Vydává je
/// relay jen přihlášenému zařízení, aby TURN nebyl otevřený pro kohokoli.
class TurnRequest extends $pb.GeneratedMessage {
  factory TurnRequest() => create();

  TurnRequest._();

  factory TurnRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TurnRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TurnRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TurnRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TurnRequest copyWith(void Function(TurnRequest) updates) =>
      super.copyWith((message) => updates(message as TurnRequest))
          as TurnRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TurnRequest create() => TurnRequest._();
  @$core.override
  TurnRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TurnRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TurnRequest>(create);
  static TurnRequest? _defaultInstance;
}

class TurnCredentials extends $pb.GeneratedMessage {
  factory TurnCredentials({
    $core.Iterable<$core.String>? urls,
    $core.String? username,
    $core.String? credential,
    $core.int? ttlSeconds,
  }) {
    final result = create();
    if (urls != null) result.urls.addAll(urls);
    if (username != null) result.username = username;
    if (credential != null) result.credential = credential;
    if (ttlSeconds != null) result.ttlSeconds = ttlSeconds;
    return result;
  }

  TurnCredentials._();

  factory TurnCredentials.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TurnCredentials.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TurnCredentials',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'urls')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..aOS(3, _omitFieldNames ? '' : 'credential')
    ..aI(4, _omitFieldNames ? '' : 'ttlSeconds', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TurnCredentials clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TurnCredentials copyWith(void Function(TurnCredentials) updates) =>
      super.copyWith((message) => updates(message as TurnCredentials))
          as TurnCredentials;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TurnCredentials create() => TurnCredentials._();
  @$core.override
  TurnCredentials createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TurnCredentials getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TurnCredentials>(create);
  static TurnCredentials? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get urls => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get credential => $_getSZ(2);
  @$pb.TagNumber(3)
  set credential($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCredential() => $_has(2);
  @$pb.TagNumber(3)
  void clearCredential() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get ttlSeconds => $_getIZ(3);
  @$pb.TagNumber(4)
  set ttlSeconds($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTtlSeconds() => $_has(3);
  @$pb.TagNumber(4)
  void clearTtlSeconds() => $_clearField(4);
}

class SignedPreKey extends $pb.GeneratedMessage {
  factory SignedPreKey({
    $core.int? keyId,
    $core.List<$core.int>? publicKey,
    $core.List<$core.int>? signature,
  }) {
    final result = create();
    if (keyId != null) result.keyId = keyId;
    if (publicKey != null) result.publicKey = publicKey;
    if (signature != null) result.signature = signature;
    return result;
  }

  SignedPreKey._();

  factory SignedPreKey.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SignedPreKey.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SignedPreKey',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'keyId', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'publicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'signature', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignedPreKey clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SignedPreKey copyWith(void Function(SignedPreKey) updates) =>
      super.copyWith((message) => updates(message as SignedPreKey))
          as SignedPreKey;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SignedPreKey create() => SignedPreKey._();
  @$core.override
  SignedPreKey createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SignedPreKey getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SignedPreKey>(create);
  static SignedPreKey? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get keyId => $_getIZ(0);
  @$pb.TagNumber(1)
  set keyId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKeyId() => $_has(0);
  @$pb.TagNumber(1)
  void clearKeyId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get publicKey => $_getN(1);
  @$pb.TagNumber(2)
  set publicKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPublicKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearPublicKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get signature => $_getN(2);
  @$pb.TagNumber(3)
  set signature($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSignature() => $_has(2);
  @$pb.TagNumber(3)
  void clearSignature() => $_clearField(3);
}

class KyberPreKey extends $pb.GeneratedMessage {
  factory KyberPreKey({
    $core.int? keyId,
    $core.List<$core.int>? publicKey,
    $core.List<$core.int>? signature,
    $core.bool? isLastResort,
  }) {
    final result = create();
    if (keyId != null) result.keyId = keyId;
    if (publicKey != null) result.publicKey = publicKey;
    if (signature != null) result.signature = signature;
    if (isLastResort != null) result.isLastResort = isLastResort;
    return result;
  }

  KyberPreKey._();

  factory KyberPreKey.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory KyberPreKey.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'KyberPreKey',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'keyId', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'publicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'signature', $pb.PbFieldType.OY)
    ..aOB(4, _omitFieldNames ? '' : 'isLastResort')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KyberPreKey clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KyberPreKey copyWith(void Function(KyberPreKey) updates) =>
      super.copyWith((message) => updates(message as KyberPreKey))
          as KyberPreKey;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static KyberPreKey create() => KyberPreKey._();
  @$core.override
  KyberPreKey createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static KyberPreKey getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<KyberPreKey>(create);
  static KyberPreKey? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get keyId => $_getIZ(0);
  @$pb.TagNumber(1)
  set keyId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKeyId() => $_has(0);
  @$pb.TagNumber(1)
  void clearKeyId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get publicKey => $_getN(1);
  @$pb.TagNumber(2)
  set publicKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPublicKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearPublicKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get signature => $_getN(2);
  @$pb.TagNumber(3)
  set signature($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSignature() => $_has(2);
  @$pb.TagNumber(3)
  void clearSignature() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isLastResort => $_getBF(3);
  @$pb.TagNumber(4)
  set isLastResort($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIsLastResort() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsLastResort() => $_clearField(4);
}

class OneTimePreKey extends $pb.GeneratedMessage {
  factory OneTimePreKey({
    $core.int? keyId,
    $core.List<$core.int>? publicKey,
  }) {
    final result = create();
    if (keyId != null) result.keyId = keyId;
    if (publicKey != null) result.publicKey = publicKey;
    return result;
  }

  OneTimePreKey._();

  factory OneTimePreKey.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory OneTimePreKey.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OneTimePreKey',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'keyId', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'publicKey', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OneTimePreKey clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OneTimePreKey copyWith(void Function(OneTimePreKey) updates) =>
      super.copyWith((message) => updates(message as OneTimePreKey))
          as OneTimePreKey;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static OneTimePreKey create() => OneTimePreKey._();
  @$core.override
  OneTimePreKey createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static OneTimePreKey getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OneTimePreKey>(create);
  static OneTimePreKey? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get keyId => $_getIZ(0);
  @$pb.TagNumber(1)
  set keyId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKeyId() => $_has(0);
  @$pb.TagNumber(1)
  void clearKeyId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get publicKey => $_getN(1);
  @$pb.TagNumber(2)
  set publicKey($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPublicKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearPublicKey() => $_clearField(2);
}

class PreKeyBundle extends $pb.GeneratedMessage {
  factory PreKeyBundle({
    $core.int? registrationId,
    $core.int? deviceId,
    $core.List<$core.int>? identityKey,
    SignedPreKey? signedPrekey,
    KyberPreKey? kyberPrekey,
    OneTimePreKey? oneTimePrekey,
  }) {
    final result = create();
    if (registrationId != null) result.registrationId = registrationId;
    if (deviceId != null) result.deviceId = deviceId;
    if (identityKey != null) result.identityKey = identityKey;
    if (signedPrekey != null) result.signedPrekey = signedPrekey;
    if (kyberPrekey != null) result.kyberPrekey = kyberPrekey;
    if (oneTimePrekey != null) result.oneTimePrekey = oneTimePrekey;
    return result;
  }

  PreKeyBundle._();

  factory PreKeyBundle.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PreKeyBundle.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreKeyBundle',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'registrationId',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'deviceId', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'identityKey', $pb.PbFieldType.OY)
    ..aOM<SignedPreKey>(4, _omitFieldNames ? '' : 'signedPrekey',
        subBuilder: SignedPreKey.create)
    ..aOM<KyberPreKey>(5, _omitFieldNames ? '' : 'kyberPrekey',
        subBuilder: KyberPreKey.create)
    ..aOM<OneTimePreKey>(6, _omitFieldNames ? '' : 'oneTimePrekey',
        subBuilder: OneTimePreKey.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreKeyBundle clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreKeyBundle copyWith(void Function(PreKeyBundle) updates) =>
      super.copyWith((message) => updates(message as PreKeyBundle))
          as PreKeyBundle;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PreKeyBundle create() => PreKeyBundle._();
  @$core.override
  PreKeyBundle createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PreKeyBundle getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PreKeyBundle>(create);
  static PreKeyBundle? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get registrationId => $_getIZ(0);
  @$pb.TagNumber(1)
  set registrationId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRegistrationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRegistrationId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get deviceId => $_getIZ(1);
  @$pb.TagNumber(2)
  set deviceId($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDeviceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get identityKey => $_getN(2);
  @$pb.TagNumber(3)
  set identityKey($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIdentityKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearIdentityKey() => $_clearField(3);

  @$pb.TagNumber(4)
  SignedPreKey get signedPrekey => $_getN(3);
  @$pb.TagNumber(4)
  set signedPrekey(SignedPreKey value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasSignedPrekey() => $_has(3);
  @$pb.TagNumber(4)
  void clearSignedPrekey() => $_clearField(4);
  @$pb.TagNumber(4)
  SignedPreKey ensureSignedPrekey() => $_ensure(3);

  @$pb.TagNumber(5)
  KyberPreKey get kyberPrekey => $_getN(4);
  @$pb.TagNumber(5)
  set kyberPrekey(KyberPreKey value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasKyberPrekey() => $_has(4);
  @$pb.TagNumber(5)
  void clearKyberPrekey() => $_clearField(5);
  @$pb.TagNumber(5)
  KyberPreKey ensureKyberPrekey() => $_ensure(4);

  @$pb.TagNumber(6)
  OneTimePreKey get oneTimePrekey => $_getN(5);
  @$pb.TagNumber(6)
  set oneTimePrekey(OneTimePreKey value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasOneTimePrekey() => $_has(5);
  @$pb.TagNumber(6)
  void clearOneTimePrekey() => $_clearField(6);
  @$pb.TagNumber(6)
  OneTimePreKey ensureOneTimePrekey() => $_ensure(5);
}

/// Bundle pro všechna zařízení identity (multi-device fanout, §4.4).
class PreKeyBundles extends $pb.GeneratedMessage {
  factory PreKeyBundles({
    $core.Iterable<PreKeyBundle>? devices,
  }) {
    final result = create();
    if (devices != null) result.devices.addAll(devices);
    return result;
  }

  PreKeyBundles._();

  factory PreKeyBundles.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PreKeyBundles.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreKeyBundles',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..pPM<PreKeyBundle>(1, _omitFieldNames ? '' : 'devices',
        subBuilder: PreKeyBundle.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreKeyBundles clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreKeyBundles copyWith(void Function(PreKeyBundles) updates) =>
      super.copyWith((message) => updates(message as PreKeyBundles))
          as PreKeyBundles;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PreKeyBundles create() => PreKeyBundles._();
  @$core.override
  PreKeyBundles createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PreKeyBundles getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PreKeyBundles>(create);
  static PreKeyBundles? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<PreKeyBundle> get devices => $_getList(0);
}

enum ClientFrame_Frame {
  auth,
  authProof,
  envelope,
  ack,
  pong,
  registerPush,
  turnRequest,
  notSet
}

class ClientFrame extends $pb.GeneratedMessage {
  factory ClientFrame({
    Auth? auth,
    AuthProof? authProof,
    Envelope? envelope,
    Ack? ack,
    Pong? pong,
    RegisterPush? registerPush,
    TurnRequest? turnRequest,
  }) {
    final result = create();
    if (auth != null) result.auth = auth;
    if (authProof != null) result.authProof = authProof;
    if (envelope != null) result.envelope = envelope;
    if (ack != null) result.ack = ack;
    if (pong != null) result.pong = pong;
    if (registerPush != null) result.registerPush = registerPush;
    if (turnRequest != null) result.turnRequest = turnRequest;
    return result;
  }

  ClientFrame._();

  factory ClientFrame.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ClientFrame.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ClientFrame_Frame> _ClientFrame_FrameByTag =
      {
    1: ClientFrame_Frame.auth,
    2: ClientFrame_Frame.authProof,
    3: ClientFrame_Frame.envelope,
    4: ClientFrame_Frame.ack,
    5: ClientFrame_Frame.pong,
    6: ClientFrame_Frame.registerPush,
    7: ClientFrame_Frame.turnRequest,
    0: ClientFrame_Frame.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ClientFrame',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4, 5, 6, 7])
    ..aOM<Auth>(1, _omitFieldNames ? '' : 'auth', subBuilder: Auth.create)
    ..aOM<AuthProof>(2, _omitFieldNames ? '' : 'authProof',
        subBuilder: AuthProof.create)
    ..aOM<Envelope>(3, _omitFieldNames ? '' : 'envelope',
        subBuilder: Envelope.create)
    ..aOM<Ack>(4, _omitFieldNames ? '' : 'ack', subBuilder: Ack.create)
    ..aOM<Pong>(5, _omitFieldNames ? '' : 'pong', subBuilder: Pong.create)
    ..aOM<RegisterPush>(6, _omitFieldNames ? '' : 'registerPush',
        subBuilder: RegisterPush.create)
    ..aOM<TurnRequest>(7, _omitFieldNames ? '' : 'turnRequest',
        subBuilder: TurnRequest.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClientFrame clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClientFrame copyWith(void Function(ClientFrame) updates) =>
      super.copyWith((message) => updates(message as ClientFrame))
          as ClientFrame;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ClientFrame create() => ClientFrame._();
  @$core.override
  ClientFrame createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ClientFrame getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ClientFrame>(create);
  static ClientFrame? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  ClientFrame_Frame whichFrame() => _ClientFrame_FrameByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  void clearFrame() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  Auth get auth => $_getN(0);
  @$pb.TagNumber(1)
  set auth(Auth value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasAuth() => $_has(0);
  @$pb.TagNumber(1)
  void clearAuth() => $_clearField(1);
  @$pb.TagNumber(1)
  Auth ensureAuth() => $_ensure(0);

  @$pb.TagNumber(2)
  AuthProof get authProof => $_getN(1);
  @$pb.TagNumber(2)
  set authProof(AuthProof value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasAuthProof() => $_has(1);
  @$pb.TagNumber(2)
  void clearAuthProof() => $_clearField(2);
  @$pb.TagNumber(2)
  AuthProof ensureAuthProof() => $_ensure(1);

  @$pb.TagNumber(3)
  Envelope get envelope => $_getN(2);
  @$pb.TagNumber(3)
  set envelope(Envelope value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasEnvelope() => $_has(2);
  @$pb.TagNumber(3)
  void clearEnvelope() => $_clearField(3);
  @$pb.TagNumber(3)
  Envelope ensureEnvelope() => $_ensure(2);

  @$pb.TagNumber(4)
  Ack get ack => $_getN(3);
  @$pb.TagNumber(4)
  set ack(Ack value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasAck() => $_has(3);
  @$pb.TagNumber(4)
  void clearAck() => $_clearField(4);
  @$pb.TagNumber(4)
  Ack ensureAck() => $_ensure(3);

  @$pb.TagNumber(5)
  Pong get pong => $_getN(4);
  @$pb.TagNumber(5)
  set pong(Pong value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasPong() => $_has(4);
  @$pb.TagNumber(5)
  void clearPong() => $_clearField(5);
  @$pb.TagNumber(5)
  Pong ensurePong() => $_ensure(4);

  @$pb.TagNumber(6)
  RegisterPush get registerPush => $_getN(5);
  @$pb.TagNumber(6)
  set registerPush(RegisterPush value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasRegisterPush() => $_has(5);
  @$pb.TagNumber(6)
  void clearRegisterPush() => $_clearField(6);
  @$pb.TagNumber(6)
  RegisterPush ensureRegisterPush() => $_ensure(5);

  @$pb.TagNumber(7)
  TurnRequest get turnRequest => $_getN(6);
  @$pb.TagNumber(7)
  set turnRequest(TurnRequest value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasTurnRequest() => $_has(6);
  @$pb.TagNumber(7)
  void clearTurnRequest() => $_clearField(7);
  @$pb.TagNumber(7)
  TurnRequest ensureTurnRequest() => $_ensure(6);
}

enum ServerFrame_Frame {
  challenge,
  receipt,
  deliver,
  prekeysLow,
  ping,
  error,
  authOk,
  turnCredentials,
  notSet
}

class ServerFrame extends $pb.GeneratedMessage {
  factory ServerFrame({
    Challenge? challenge,
    Receipt? receipt,
    Envelope? deliver,
    PrekeysLow? prekeysLow,
    Ping? ping,
    Error? error,
    AuthOk? authOk,
    TurnCredentials? turnCredentials,
  }) {
    final result = create();
    if (challenge != null) result.challenge = challenge;
    if (receipt != null) result.receipt = receipt;
    if (deliver != null) result.deliver = deliver;
    if (prekeysLow != null) result.prekeysLow = prekeysLow;
    if (ping != null) result.ping = ping;
    if (error != null) result.error = error;
    if (authOk != null) result.authOk = authOk;
    if (turnCredentials != null) result.turnCredentials = turnCredentials;
    return result;
  }

  ServerFrame._();

  factory ServerFrame.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ServerFrame.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ServerFrame_Frame> _ServerFrame_FrameByTag =
      {
    1: ServerFrame_Frame.challenge,
    2: ServerFrame_Frame.receipt,
    3: ServerFrame_Frame.deliver,
    4: ServerFrame_Frame.prekeysLow,
    5: ServerFrame_Frame.ping,
    6: ServerFrame_Frame.error,
    7: ServerFrame_Frame.authOk,
    8: ServerFrame_Frame.turnCredentials,
    0: ServerFrame_Frame.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ServerFrame',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'sepot.v1'),
      createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4, 5, 6, 7, 8])
    ..aOM<Challenge>(1, _omitFieldNames ? '' : 'challenge',
        subBuilder: Challenge.create)
    ..aOM<Receipt>(2, _omitFieldNames ? '' : 'receipt',
        subBuilder: Receipt.create)
    ..aOM<Envelope>(3, _omitFieldNames ? '' : 'deliver',
        subBuilder: Envelope.create)
    ..aOM<PrekeysLow>(4, _omitFieldNames ? '' : 'prekeysLow',
        subBuilder: PrekeysLow.create)
    ..aOM<Ping>(5, _omitFieldNames ? '' : 'ping', subBuilder: Ping.create)
    ..aOM<Error>(6, _omitFieldNames ? '' : 'error', subBuilder: Error.create)
    ..aOM<AuthOk>(7, _omitFieldNames ? '' : 'authOk', subBuilder: AuthOk.create)
    ..aOM<TurnCredentials>(8, _omitFieldNames ? '' : 'turnCredentials',
        subBuilder: TurnCredentials.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ServerFrame clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ServerFrame copyWith(void Function(ServerFrame) updates) =>
      super.copyWith((message) => updates(message as ServerFrame))
          as ServerFrame;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ServerFrame create() => ServerFrame._();
  @$core.override
  ServerFrame createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ServerFrame getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ServerFrame>(create);
  static ServerFrame? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  ServerFrame_Frame whichFrame() => _ServerFrame_FrameByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  void clearFrame() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  Challenge get challenge => $_getN(0);
  @$pb.TagNumber(1)
  set challenge(Challenge value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasChallenge() => $_has(0);
  @$pb.TagNumber(1)
  void clearChallenge() => $_clearField(1);
  @$pb.TagNumber(1)
  Challenge ensureChallenge() => $_ensure(0);

  @$pb.TagNumber(2)
  Receipt get receipt => $_getN(1);
  @$pb.TagNumber(2)
  set receipt(Receipt value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasReceipt() => $_has(1);
  @$pb.TagNumber(2)
  void clearReceipt() => $_clearField(2);
  @$pb.TagNumber(2)
  Receipt ensureReceipt() => $_ensure(1);

  @$pb.TagNumber(3)
  Envelope get deliver => $_getN(2);
  @$pb.TagNumber(3)
  set deliver(Envelope value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasDeliver() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeliver() => $_clearField(3);
  @$pb.TagNumber(3)
  Envelope ensureDeliver() => $_ensure(2);

  @$pb.TagNumber(4)
  PrekeysLow get prekeysLow => $_getN(3);
  @$pb.TagNumber(4)
  set prekeysLow(PrekeysLow value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasPrekeysLow() => $_has(3);
  @$pb.TagNumber(4)
  void clearPrekeysLow() => $_clearField(4);
  @$pb.TagNumber(4)
  PrekeysLow ensurePrekeysLow() => $_ensure(3);

  @$pb.TagNumber(5)
  Ping get ping => $_getN(4);
  @$pb.TagNumber(5)
  set ping(Ping value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasPing() => $_has(4);
  @$pb.TagNumber(5)
  void clearPing() => $_clearField(5);
  @$pb.TagNumber(5)
  Ping ensurePing() => $_ensure(4);

  @$pb.TagNumber(6)
  Error get error => $_getN(5);
  @$pb.TagNumber(6)
  set error(Error value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => $_clearField(6);
  @$pb.TagNumber(6)
  Error ensureError() => $_ensure(5);

  @$pb.TagNumber(7)
  AuthOk get authOk => $_getN(6);
  @$pb.TagNumber(7)
  set authOk(AuthOk value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasAuthOk() => $_has(6);
  @$pb.TagNumber(7)
  void clearAuthOk() => $_clearField(7);
  @$pb.TagNumber(7)
  AuthOk ensureAuthOk() => $_ensure(6);

  @$pb.TagNumber(8)
  TurnCredentials get turnCredentials => $_getN(7);
  @$pb.TagNumber(8)
  set turnCredentials(TurnCredentials value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasTurnCredentials() => $_has(7);
  @$pb.TagNumber(8)
  void clearTurnCredentials() => $_clearField(8);
  @$pb.TagNumber(8)
  TurnCredentials ensureTurnCredentials() => $_ensure(7);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
