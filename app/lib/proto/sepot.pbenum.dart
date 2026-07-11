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

class ContentHint extends $pb.ProtobufEnum {
  static const ContentHint CONTENT_HINT_DEFAULT =
      ContentHint._(0, _omitEnumNames ? '' : 'CONTENT_HINT_DEFAULT');
  static const ContentHint CONTENT_HINT_RESYNC =
      ContentHint._(1, _omitEnumNames ? '' : 'CONTENT_HINT_RESYNC');
  static const ContentHint CONTENT_HINT_SUPPLEMENTARY =
      ContentHint._(2, _omitEnumNames ? '' : 'CONTENT_HINT_SUPPLEMENTARY');

  static const $core.List<ContentHint> values = <ContentHint>[
    CONTENT_HINT_DEFAULT,
    CONTENT_HINT_RESYNC,
    CONTENT_HINT_SUPPLEMENTARY,
  ];

  static final $core.List<ContentHint?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static ContentHint? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ContentHint._(super.value, super.name);
}

class Receipt_Status extends $pb.ProtobufEnum {
  static const Receipt_Status STATUS_QUEUED =
      Receipt_Status._(0, _omitEnumNames ? '' : 'STATUS_QUEUED');
  static const Receipt_Status STATUS_DELIVERED_ONLINE =
      Receipt_Status._(1, _omitEnumNames ? '' : 'STATUS_DELIVERED_ONLINE');
  static const Receipt_Status STATUS_STORED_OFFLINE =
      Receipt_Status._(2, _omitEnumNames ? '' : 'STATUS_STORED_OFFLINE');

  static const $core.List<Receipt_Status> values = <Receipt_Status>[
    STATUS_QUEUED,
    STATUS_DELIVERED_ONLINE,
    STATUS_STORED_OFFLINE,
  ];

  static final $core.List<Receipt_Status?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static Receipt_Status? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Receipt_Status._(super.value, super.name);
}

class RegisterPush_Platform extends $pb.ProtobufEnum {
  static const RegisterPush_Platform PLATFORM_NONE =
      RegisterPush_Platform._(0, _omitEnumNames ? '' : 'PLATFORM_NONE');
  static const RegisterPush_Platform PLATFORM_FCM =
      RegisterPush_Platform._(1, _omitEnumNames ? '' : 'PLATFORM_FCM');
  static const RegisterPush_Platform PLATFORM_APNS =
      RegisterPush_Platform._(2, _omitEnumNames ? '' : 'PLATFORM_APNS');
  static const RegisterPush_Platform PLATFORM_UNIFIEDPUSH =
      RegisterPush_Platform._(3, _omitEnumNames ? '' : 'PLATFORM_UNIFIEDPUSH');
  static const RegisterPush_Platform PLATFORM_WEBPUSH =
      RegisterPush_Platform._(4, _omitEnumNames ? '' : 'PLATFORM_WEBPUSH');

  static const $core.List<RegisterPush_Platform> values =
      <RegisterPush_Platform>[
    PLATFORM_NONE,
    PLATFORM_FCM,
    PLATFORM_APNS,
    PLATFORM_UNIFIEDPUSH,
    PLATFORM_WEBPUSH,
  ];

  static final $core.List<RegisterPush_Platform?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static RegisterPush_Platform? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RegisterPush_Platform._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
