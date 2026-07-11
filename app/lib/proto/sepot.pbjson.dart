// This is a generated file - do not edit.
//
// Generated from sepot.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use contentHintDescriptor instead')
const ContentHint$json = {
  '1': 'ContentHint',
  '2': [
    {'1': 'CONTENT_HINT_DEFAULT', '2': 0},
    {'1': 'CONTENT_HINT_RESYNC', '2': 1},
    {'1': 'CONTENT_HINT_SUPPLEMENTARY', '2': 2},
  ],
};

/// Descriptor for `ContentHint`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List contentHintDescriptor = $convert.base64Decode(
    'CgtDb250ZW50SGludBIYChRDT05URU5UX0hJTlRfREVGQVVMVBAAEhcKE0NPTlRFTlRfSElOVF'
    '9SRVNZTkMQARIeChpDT05URU5UX0hJTlRfU1VQUExFTUVOVEFSWRAC');

@$core.Deprecated('Use envelopeDescriptor instead')
const Envelope$json = {
  '1': 'Envelope',
  '2': [
    {'1': 'dst_address', '3': 1, '4': 1, '5': 12, '10': 'dstAddress'},
    {'1': 'msg_uuid', '3': 2, '4': 1, '5': 12, '10': 'msgUuid'},
    {
      '1': 'content_hint',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.sepot.v1.ContentHint',
      '10': 'contentHint'
    },
    {'1': 'payload', '3': 4, '4': 1, '5': 12, '10': 'payload'},
  ],
};

/// Descriptor for `Envelope`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List envelopeDescriptor = $convert.base64Decode(
    'CghFbnZlbG9wZRIfCgtkc3RfYWRkcmVzcxgBIAEoDFIKZHN0QWRkcmVzcxIZCghtc2dfdXVpZB'
    'gCIAEoDFIHbXNnVXVpZBI4Cgxjb250ZW50X2hpbnQYAyABKA4yFS5zZXBvdC52MS5Db250ZW50'
    'SGludFILY29udGVudEhpbnQSGAoHcGF5bG9hZBgEIAEoDFIHcGF5bG9hZA==');

@$core.Deprecated('Use ackDescriptor instead')
const Ack$json = {
  '1': 'Ack',
  '2': [
    {'1': 'msg_uuid', '3': 1, '4': 1, '5': 12, '10': 'msgUuid'},
  ],
};

/// Descriptor for `Ack`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ackDescriptor =
    $convert.base64Decode('CgNBY2sSGQoIbXNnX3V1aWQYASABKAxSB21zZ1V1aWQ=');

@$core.Deprecated('Use receiptDescriptor instead')
const Receipt$json = {
  '1': 'Receipt',
  '2': [
    {'1': 'msg_uuid', '3': 1, '4': 1, '5': 12, '10': 'msgUuid'},
    {
      '1': 'status',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.sepot.v1.Receipt.Status',
      '10': 'status'
    },
  ],
  '4': [Receipt_Status$json],
};

@$core.Deprecated('Use receiptDescriptor instead')
const Receipt_Status$json = {
  '1': 'Status',
  '2': [
    {'1': 'STATUS_QUEUED', '2': 0},
    {'1': 'STATUS_DELIVERED_ONLINE', '2': 1},
    {'1': 'STATUS_STORED_OFFLINE', '2': 2},
  ],
};

/// Descriptor for `Receipt`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List receiptDescriptor = $convert.base64Decode(
    'CgdSZWNlaXB0EhkKCG1zZ191dWlkGAEgASgMUgdtc2dVdWlkEjAKBnN0YXR1cxgCIAEoDjIYLn'
    'NlcG90LnYxLlJlY2VpcHQuU3RhdHVzUgZzdGF0dXMiUwoGU3RhdHVzEhEKDVNUQVRVU19RVUVV'
    'RUQQABIbChdTVEFUVVNfREVMSVZFUkVEX09OTElORRABEhkKFVNUQVRVU19TVE9SRURfT0ZGTE'
    'lORRAC');

@$core.Deprecated('Use authDescriptor instead')
const Auth$json = {
  '1': 'Auth',
  '2': [
    {'1': 'device_uuid', '3': 1, '4': 1, '5': 12, '10': 'deviceUuid'},
    {'1': 'nonce_client', '3': 2, '4': 1, '5': 12, '10': 'nonceClient'},
  ],
};

/// Descriptor for `Auth`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List authDescriptor = $convert.base64Decode(
    'CgRBdXRoEh8KC2RldmljZV91dWlkGAEgASgMUgpkZXZpY2VVdWlkEiEKDG5vbmNlX2NsaWVudB'
    'gCIAEoDFILbm9uY2VDbGllbnQ=');

@$core.Deprecated('Use challengeDescriptor instead')
const Challenge$json = {
  '1': 'Challenge',
  '2': [
    {'1': 'nonce_server', '3': 1, '4': 1, '5': 12, '10': 'nonceServer'},
  ],
};

/// Descriptor for `Challenge`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List challengeDescriptor = $convert.base64Decode(
    'CglDaGFsbGVuZ2USIQoMbm9uY2Vfc2VydmVyGAEgASgMUgtub25jZVNlcnZlcg==');

@$core.Deprecated('Use authProofDescriptor instead')
const AuthProof$json = {
  '1': 'AuthProof',
  '2': [
    {'1': 'signature', '3': 1, '4': 1, '5': 12, '10': 'signature'},
  ],
};

/// Descriptor for `AuthProof`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List authProofDescriptor = $convert
    .base64Decode('CglBdXRoUHJvb2YSHAoJc2lnbmF0dXJlGAEgASgMUglzaWduYXR1cmU=');

@$core.Deprecated('Use prekeysLowDescriptor instead')
const PrekeysLow$json = {
  '1': 'PrekeysLow',
  '2': [
    {'1': 'remaining', '3': 1, '4': 1, '5': 13, '10': 'remaining'},
  ],
};

/// Descriptor for `PrekeysLow`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List prekeysLowDescriptor = $convert
    .base64Decode('CgpQcmVrZXlzTG93EhwKCXJlbWFpbmluZxgBIAEoDVIJcmVtYWluaW5n');

@$core.Deprecated('Use errorDescriptor instead')
const Error$json = {
  '1': 'Error',
  '2': [
    {'1': 'code', '3': 1, '4': 1, '5': 13, '10': 'code'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `Error`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List errorDescriptor = $convert.base64Decode(
    'CgVFcnJvchISCgRjb2RlGAEgASgNUgRjb2RlEhgKB21lc3NhZ2UYAiABKAlSB21lc3NhZ2U=');

@$core.Deprecated('Use pingDescriptor instead')
const Ping$json = {
  '1': 'Ping',
};

/// Descriptor for `Ping`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pingDescriptor = $convert.base64Decode('CgRQaW5n');

@$core.Deprecated('Use pongDescriptor instead')
const Pong$json = {
  '1': 'Pong',
};

/// Descriptor for `Pong`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pongDescriptor = $convert.base64Decode('CgRQb25n');

@$core.Deprecated('Use authOkDescriptor instead')
const AuthOk$json = {
  '1': 'AuthOk',
};

/// Descriptor for `AuthOk`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List authOkDescriptor =
    $convert.base64Decode('CgZBdXRoT2s=');

@$core.Deprecated('Use registerPushDescriptor instead')
const RegisterPush$json = {
  '1': 'RegisterPush',
  '2': [
    {
      '1': 'platform',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.sepot.v1.RegisterPush.Platform',
      '10': 'platform'
    },
    {'1': 'endpoint', '3': 2, '4': 1, '5': 12, '10': 'endpoint'},
  ],
  '4': [RegisterPush_Platform$json],
};

@$core.Deprecated('Use registerPushDescriptor instead')
const RegisterPush_Platform$json = {
  '1': 'Platform',
  '2': [
    {'1': 'PLATFORM_NONE', '2': 0},
    {'1': 'PLATFORM_FCM', '2': 1},
    {'1': 'PLATFORM_APNS', '2': 2},
    {'1': 'PLATFORM_UNIFIEDPUSH', '2': 3},
    {'1': 'PLATFORM_WEBPUSH', '2': 4},
  ],
};

/// Descriptor for `RegisterPush`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List registerPushDescriptor = $convert.base64Decode(
    'CgxSZWdpc3RlclB1c2gSOwoIcGxhdGZvcm0YASABKA4yHy5zZXBvdC52MS5SZWdpc3RlclB1c2'
    'guUGxhdGZvcm1SCHBsYXRmb3JtEhoKCGVuZHBvaW50GAIgASgMUghlbmRwb2ludCJyCghQbGF0'
    'Zm9ybRIRCg1QTEFURk9STV9OT05FEAASEAoMUExBVEZPUk1fRkNNEAESEQoNUExBVEZPUk1fQV'
    'BOUxACEhgKFFBMQVRGT1JNX1VOSUZJRURQVVNIEAMSFAoQUExBVEZPUk1fV0VCUFVTSBAE');

@$core.Deprecated('Use signedPreKeyDescriptor instead')
const SignedPreKey$json = {
  '1': 'SignedPreKey',
  '2': [
    {'1': 'key_id', '3': 1, '4': 1, '5': 13, '10': 'keyId'},
    {'1': 'public_key', '3': 2, '4': 1, '5': 12, '10': 'publicKey'},
    {'1': 'signature', '3': 3, '4': 1, '5': 12, '10': 'signature'},
  ],
};

/// Descriptor for `SignedPreKey`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List signedPreKeyDescriptor = $convert.base64Decode(
    'CgxTaWduZWRQcmVLZXkSFQoGa2V5X2lkGAEgASgNUgVrZXlJZBIdCgpwdWJsaWNfa2V5GAIgAS'
    'gMUglwdWJsaWNLZXkSHAoJc2lnbmF0dXJlGAMgASgMUglzaWduYXR1cmU=');

@$core.Deprecated('Use kyberPreKeyDescriptor instead')
const KyberPreKey$json = {
  '1': 'KyberPreKey',
  '2': [
    {'1': 'key_id', '3': 1, '4': 1, '5': 13, '10': 'keyId'},
    {'1': 'public_key', '3': 2, '4': 1, '5': 12, '10': 'publicKey'},
    {'1': 'signature', '3': 3, '4': 1, '5': 12, '10': 'signature'},
    {'1': 'is_last_resort', '3': 4, '4': 1, '5': 8, '10': 'isLastResort'},
  ],
};

/// Descriptor for `KyberPreKey`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List kyberPreKeyDescriptor = $convert.base64Decode(
    'CgtLeWJlclByZUtleRIVCgZrZXlfaWQYASABKA1SBWtleUlkEh0KCnB1YmxpY19rZXkYAiABKA'
    'xSCXB1YmxpY0tleRIcCglzaWduYXR1cmUYAyABKAxSCXNpZ25hdHVyZRIkCg5pc19sYXN0X3Jl'
    'c29ydBgEIAEoCFIMaXNMYXN0UmVzb3J0');

@$core.Deprecated('Use oneTimePreKeyDescriptor instead')
const OneTimePreKey$json = {
  '1': 'OneTimePreKey',
  '2': [
    {'1': 'key_id', '3': 1, '4': 1, '5': 13, '10': 'keyId'},
    {'1': 'public_key', '3': 2, '4': 1, '5': 12, '10': 'publicKey'},
  ],
};

/// Descriptor for `OneTimePreKey`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List oneTimePreKeyDescriptor = $convert.base64Decode(
    'Cg1PbmVUaW1lUHJlS2V5EhUKBmtleV9pZBgBIAEoDVIFa2V5SWQSHQoKcHVibGljX2tleRgCIA'
    'EoDFIJcHVibGljS2V5');

@$core.Deprecated('Use preKeyBundleDescriptor instead')
const PreKeyBundle$json = {
  '1': 'PreKeyBundle',
  '2': [
    {'1': 'registration_id', '3': 1, '4': 1, '5': 13, '10': 'registrationId'},
    {'1': 'device_id', '3': 2, '4': 1, '5': 13, '10': 'deviceId'},
    {'1': 'identity_key', '3': 3, '4': 1, '5': 12, '10': 'identityKey'},
    {
      '1': 'signed_prekey',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.sepot.v1.SignedPreKey',
      '10': 'signedPrekey'
    },
    {
      '1': 'kyber_prekey',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.sepot.v1.KyberPreKey',
      '10': 'kyberPrekey'
    },
    {
      '1': 'one_time_prekey',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.sepot.v1.OneTimePreKey',
      '10': 'oneTimePrekey'
    },
  ],
};

/// Descriptor for `PreKeyBundle`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List preKeyBundleDescriptor = $convert.base64Decode(
    'CgxQcmVLZXlCdW5kbGUSJwoPcmVnaXN0cmF0aW9uX2lkGAEgASgNUg5yZWdpc3RyYXRpb25JZB'
    'IbCglkZXZpY2VfaWQYAiABKA1SCGRldmljZUlkEiEKDGlkZW50aXR5X2tleRgDIAEoDFILaWRl'
    'bnRpdHlLZXkSOwoNc2lnbmVkX3ByZWtleRgEIAEoCzIWLnNlcG90LnYxLlNpZ25lZFByZUtleV'
    'IMc2lnbmVkUHJla2V5EjgKDGt5YmVyX3ByZWtleRgFIAEoCzIVLnNlcG90LnYxLkt5YmVyUHJl'
    'S2V5UgtreWJlclByZWtleRI/Cg9vbmVfdGltZV9wcmVrZXkYBiABKAsyFy5zZXBvdC52MS5Pbm'
    'VUaW1lUHJlS2V5Ug1vbmVUaW1lUHJla2V5');

@$core.Deprecated('Use preKeyBundlesDescriptor instead')
const PreKeyBundles$json = {
  '1': 'PreKeyBundles',
  '2': [
    {
      '1': 'devices',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.sepot.v1.PreKeyBundle',
      '10': 'devices'
    },
  ],
};

/// Descriptor for `PreKeyBundles`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List preKeyBundlesDescriptor = $convert.base64Decode(
    'Cg1QcmVLZXlCdW5kbGVzEjAKB2RldmljZXMYASADKAsyFi5zZXBvdC52MS5QcmVLZXlCdW5kbG'
    'VSB2RldmljZXM=');

@$core.Deprecated('Use clientFrameDescriptor instead')
const ClientFrame$json = {
  '1': 'ClientFrame',
  '2': [
    {
      '1': 'auth',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.sepot.v1.Auth',
      '9': 0,
      '10': 'auth'
    },
    {
      '1': 'auth_proof',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.sepot.v1.AuthProof',
      '9': 0,
      '10': 'authProof'
    },
    {
      '1': 'envelope',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.sepot.v1.Envelope',
      '9': 0,
      '10': 'envelope'
    },
    {
      '1': 'ack',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.sepot.v1.Ack',
      '9': 0,
      '10': 'ack'
    },
    {
      '1': 'pong',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.sepot.v1.Pong',
      '9': 0,
      '10': 'pong'
    },
    {
      '1': 'register_push',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.sepot.v1.RegisterPush',
      '9': 0,
      '10': 'registerPush'
    },
  ],
  '8': [
    {'1': 'frame'},
  ],
};

/// Descriptor for `ClientFrame`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clientFrameDescriptor = $convert.base64Decode(
    'CgtDbGllbnRGcmFtZRIkCgRhdXRoGAEgASgLMg4uc2Vwb3QudjEuQXV0aEgAUgRhdXRoEjQKCm'
    'F1dGhfcHJvb2YYAiABKAsyEy5zZXBvdC52MS5BdXRoUHJvb2ZIAFIJYXV0aFByb29mEjAKCGVu'
    'dmVsb3BlGAMgASgLMhIuc2Vwb3QudjEuRW52ZWxvcGVIAFIIZW52ZWxvcGUSIQoDYWNrGAQgAS'
    'gLMg0uc2Vwb3QudjEuQWNrSABSA2FjaxIkCgRwb25nGAUgASgLMg4uc2Vwb3QudjEuUG9uZ0gA'
    'UgRwb25nEj0KDXJlZ2lzdGVyX3B1c2gYBiABKAsyFi5zZXBvdC52MS5SZWdpc3RlclB1c2hIAF'
    'IMcmVnaXN0ZXJQdXNoQgcKBWZyYW1l');

@$core.Deprecated('Use serverFrameDescriptor instead')
const ServerFrame$json = {
  '1': 'ServerFrame',
  '2': [
    {
      '1': 'challenge',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.sepot.v1.Challenge',
      '9': 0,
      '10': 'challenge'
    },
    {
      '1': 'receipt',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.sepot.v1.Receipt',
      '9': 0,
      '10': 'receipt'
    },
    {
      '1': 'deliver',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.sepot.v1.Envelope',
      '9': 0,
      '10': 'deliver'
    },
    {
      '1': 'prekeys_low',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.sepot.v1.PrekeysLow',
      '9': 0,
      '10': 'prekeysLow'
    },
    {
      '1': 'ping',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.sepot.v1.Ping',
      '9': 0,
      '10': 'ping'
    },
    {
      '1': 'error',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.sepot.v1.Error',
      '9': 0,
      '10': 'error'
    },
    {
      '1': 'auth_ok',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.sepot.v1.AuthOk',
      '9': 0,
      '10': 'authOk'
    },
  ],
  '8': [
    {'1': 'frame'},
  ],
};

/// Descriptor for `ServerFrame`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List serverFrameDescriptor = $convert.base64Decode(
    'CgtTZXJ2ZXJGcmFtZRIzCgljaGFsbGVuZ2UYASABKAsyEy5zZXBvdC52MS5DaGFsbGVuZ2VIAF'
    'IJY2hhbGxlbmdlEi0KB3JlY2VpcHQYAiABKAsyES5zZXBvdC52MS5SZWNlaXB0SABSB3JlY2Vp'
    'cHQSLgoHZGVsaXZlchgDIAEoCzISLnNlcG90LnYxLkVudmVsb3BlSABSB2RlbGl2ZXISNwoLcH'
    'Jla2V5c19sb3cYBCABKAsyFC5zZXBvdC52MS5QcmVrZXlzTG93SABSCnByZWtleXNMb3cSJAoE'
    'cGluZxgFIAEoCzIOLnNlcG90LnYxLlBpbmdIAFIEcGluZxInCgVlcnJvchgGIAEoCzIPLnNlcG'
    '90LnYxLkVycm9ySABSBWVycm9yEisKB2F1dGhfb2sYByABKAsyEC5zZXBvdC52MS5BdXRoT2tI'
    'AFIGYXV0aE9rQgcKBWZyYW1l');
