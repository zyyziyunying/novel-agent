import '../workspace.dart';

/// Additive fields keep older format 2 snapshots and requests readable.
/// Explicit null and unknown fields still fail at the individual field parser.
Json objectWithOptional(
  Object? value,
  Set<String> required,
  Set<String> optional,
) {
  if (value is! Json ||
      required.any((key) => !value.containsKey(key)) ||
      value.keys.any(
        (key) => !required.contains(key) && !optional.contains(key),
      )) {
    throw const FormatException('JSON 字段不符合契约');
  }
  return value;
}

String identifier(Object? value) {
  final text = readText(value);
  if (text != text.trim()) throw const FormatException('标识不得带首尾空白');
  return text;
}

String choice(Object? value, Set<String> allowed) {
  final text = readText(value);
  if (!allowed.contains(text)) throw const FormatException('未知枚举值');
  return text;
}

String? optionalIdentifier(Object? value) =>
    value == null ? null : identifier(value);

void uniqueIds(Iterable<String> values) {
  final seen = <String>{};
  for (final value in values) {
    identifier(value);
    if (!seen.add(value)) throw const FormatException('重复标识');
  }
}

Map<String, String> versionMap(Object? value) {
  final result = heads(value);
  for (final entry in result.entries) {
    identifier(entry.key);
    identifier(entry.value);
  }
  return result;
}

// Freeze nested JSON too: a queued request must keep its original fingerprint.
Object? immutableJson(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double && value.isFinite) return value;
  if (value is List) return List.unmodifiable(value.map(immutableJson));
  if (value is Json) {
    return Map<String, dynamic>.unmodifiable(
      value.map((key, item) => MapEntry(key, immutableJson(item))),
    );
  }
  throw const FormatException('需要有限的 JSON 值');
}

Object? sortedJson(Object? value) {
  if (value is Json) {
    return {
      for (final key in value.keys.toList()..sort())
        key: sortedJson(value[key]),
    };
  }
  if (value is List) return value.map(sortedJson).toList();
  return value;
}
