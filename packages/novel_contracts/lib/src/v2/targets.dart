import '../workspace.dart';
import 'validation.dart';

class CommandTarget {
  CommandTarget.catalog()
    : kind = 'catalog',
      workId = null,
      libraryId = null,
      discussionId = null;
  CommandTarget.work(String workId)
    : kind = 'work',
      workId = identifier(workId),
      libraryId = null,
      discussionId = null;
  CommandTarget.library(String libraryId, {String? workId})
    : kind = 'library',
      libraryId = identifier(libraryId),
      workId = optionalIdentifier(workId),
      discussionId = null;
  CommandTarget.discussion({
    required String workId,
    required String discussionId,
  }) : kind = 'discussion',
       workId = identifier(workId),
       discussionId = identifier(discussionId),
       libraryId = null;
  final String kind;
  final String? workId;
  final String? libraryId;
  final String? discussionId;
  Json toJson() => switch (kind) {
    'catalog' => {'kind': kind},
    'work' => {'kind': kind, 'workId': workId},
    'library' => {'kind': kind, 'libraryId': libraryId, 'workId': workId},
    _ => {'kind': kind, 'workId': workId, 'discussionId': discussionId},
  };
  factory CommandTarget.fromJson(Object? value) {
    if (value is! Json) throw const FormatException('请求目标无效');
    switch (value['kind']) {
      case 'catalog':
        object(value, {'kind'});
        return CommandTarget.catalog();
      case 'work':
        final j = object(value, {'kind', 'workId'});
        return CommandTarget.work(identifier(j['workId']));
      case 'library':
        final j = object(value, {'kind', 'libraryId', 'workId'});
        return CommandTarget.library(
          identifier(j['libraryId']),
          workId: optionalIdentifier(j['workId']),
        );
      case 'discussion':
        final j = object(value, {'kind', 'workId', 'discussionId'});
        return CommandTarget.discussion(
          workId: identifier(j['workId']),
          discussionId: identifier(j['discussionId']),
        );
      default:
        throw const FormatException('未知请求目标');
    }
  }
}
