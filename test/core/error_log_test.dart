import 'dart:io';

import 'package:dio/dio.dart';
import 'package:doc_approval/core/errors/error_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // `debugPrint` is not compiled out of release builds, so anything passed to
  // it in a catch block is published to logcat on a real user's device.
  group('release builds log the exception type and nothing else', () {
    test('a filesystem error does not leak the on-device path', () {
      const error = FileSystemException(
        'Cannot open file',
        '/data/user/0/com.alraqi.app/cache/محضر-سري.pdf',
      );

      final lines = unexpectedLogLines(
        'Document upload failed',
        error,
        StackTrace.current,
        debug: false,
      );

      expect(lines, ['Document upload failed: FileSystemException']);
      final joined = lines.join('\n');
      expect(joined, isNot(contains('/data/user/0/')));
      expect(joined, isNot(contains('محضر-سري')));
      expect(joined, isNot(contains('Cannot open file')));
    });

    test('a Dio error does not leak the request it dumps', () {
      final error = DioException(
        requestOptions: RequestOptions(
          path: '/documents',
          headers: {'Authorization': 'Bearer super-secret-token'},
          data: {'title': 'عقد سري'},
        ),
        message: 'connection error to https://internal.alraqi.local',
      );

      final lines =
          unexpectedLogLines('Upload failed', error, null, debug: false);
      final joined = lines.join('\n');

      expect(lines, ['Upload failed: DioException']);
      expect(joined, isNot(contains('super-secret-token')));
      expect(joined, isNot(contains('internal.alraqi.local')));
      expect(joined, isNot(contains('عقد سري')));
    });

    test('no stack trace is written, however many frames it has', () {
      final lines = unexpectedLogLines(
        'Approver picker failed to open',
        StateError('bad state'),
        StackTrace.current,
        debug: false,
      );

      expect(lines, hasLength(1));
      expect(lines.single, isNot(contains('error_log_test')));
      expect(lines.single, isNot(contains('bad state')));
    });
  });

  group('debug builds keep the full detail', () {
    test('the message and the stack are both written', () {
      const error = FileSystemException('Cannot open file', '/tmp/x.pdf');
      final stack = StackTrace.current;

      final lines = unexpectedLogLines('Document upload failed', error, stack,
          debug: true);

      expect(lines, hasLength(2));
      expect(lines.first, contains('Cannot open file'));
      expect(lines.first, contains('/tmp/x.pdf'));
      expect(lines.last, stack.toString());
    });

    test('a missing stack trace does not produce an empty line', () {
      final lines = unexpectedLogLines('x', StateError('y'), null, debug: true);
      expect(lines, hasLength(1));
    });
  });
}
