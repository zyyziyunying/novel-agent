import 'dart:io';

const _pubspecs = [
  'pubspec.yaml',
  'agent/pubspec.yaml',
  'viewer/pubspec.yaml',
  'packages/novel_contracts/pubspec.yaml',
];

Future<void> main(List<String> args) async {
  if (args.length == 1 && args.single == '--help') {
    stdout.writeln('用法：dart run tool/version.dart [--check|--sync]');
    stdout.writeln('--check（默认）检查 VERSION、包版本及 CHANGELOG。');
    stdout.writeln('--sync 将 VERSION 同步到所有 workspace pubspec.yaml。');
    return;
  }
  if (args.length > 1 ||
      (args.isNotEmpty && !{'--check', '--sync'}.contains(args.single))) {
    stderr.writeln('参数无效。使用 --help 查看用法。');
    exitCode = 64;
    return;
  }

  final root = Directory.fromUri(Platform.script.resolve('../'));
  final sync = args.isNotEmpty && args.single == '--sync';
  try {
    final version = (await File('${root.path}/VERSION').readAsString()).trim();
    final versionPattern = RegExp(
      r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
      r'(?:-(alpha|beta|rc)\.(0|[1-9][0-9]*))?$',
    );
    if (!versionPattern.hasMatch(version)) {
      throw const FormatException(
        'VERSION 必须为 X.Y.Z 或 X.Y.Z-alpha.N / beta.N / rc.N，数字不得有前导零。',
      );
    }

    final changelog = await File('${root.path}/CHANGELOG.md').readAsString();
    final headings = changelog.split('\n').map((line) => line.trim()).toList();
    final releaseHeading = RegExp(
      '^## \\[${RegExp.escape(version)}\\] - [0-9]{4}-[0-9]{2}-[0-9]{2}\$',
    );
    if (headings.where((line) => line == '## [Unreleased]').length != 1 ||
        headings.where(releaseHeading.hasMatch).length != 1) {
      throw FormatException(
        'CHANGELOG.md 必须有一个 [Unreleased] 和一个 [$version] - YYYY-MM-DD 条目。'
        '规划中的功能留在 SPEC.md；版本条目只登记已实现变更。',
      );
    }

    final declaration = RegExp(
      r'^version:[ \t]*([^ \t\r\n]+)[ \t]*\r?$',
      multiLine: true,
    );
    final updates = <String, String>{};
    final mismatches = <String>[];
    // Read and validate every input before --sync writes any file.
    for (final path in _pubspecs) {
      final content = await File('${root.path}/$path').readAsString();
      final matches = declaration.allMatches(content).toList();
      if (matches.length != 1) {
        throw FormatException('$path 必须有且只有一个不带引号的顶层 version 字段。');
      }
      final match = matches.single;
      if (match.group(1) != version) {
        mismatches.add('$path: ${match.group(1)}，应为 $version');
        updates[path] = content.replaceRange(
          match.start,
          match.end,
          'version: $version',
        );
      }
    }

    if (!sync && mismatches.isNotEmpty) {
      stderr.writeln(mismatches.join('\n'));
      stderr.writeln('请运行 dart run tool/version.dart --sync 后重新检查。');
      exitCode = 1;
      return;
    }
    for (final entry in updates.entries) {
      await File('${root.path}/${entry.key}').writeAsString(entry.value);
      stdout.writeln('已同步 ${entry.key} -> $version');
    }
    stdout.writeln(
      '版本检查通过：$version（${_pubspecs.length} 个 pubspec，CHANGELOG 已登记）。',
    );
  } on FormatException catch (error) {
    stderr.writeln('版本检查失败：${error.message}');
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln('无法读取或同步版本文件：${error.path}。请检查文件是否存在及读写权限。');
    exitCode = 1;
  }
}
