@TestOn('windows')
library;

import 'dart:io';

import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  // Also covers NoDefaultCurrentDirectoryInExePath being set, in which case cmd
  // doesn't look for commands in the working directory.
  test('environmentFromBatchFile', () async {
    final tempUri = await tempDirForTest();
    final batchFile = File.fromUri(tempUri.resolve('set_env.bat'));
    await batchFile.writeAsString('@set NTC_ENV_FROM_BAT_TEST=%1\r\n');

    final env = await environmentFromBatchFile(batchFile.uri, arguments: ['hello']);

    expect(env, {'NTC_ENV_FROM_BAT_TEST': 'hello'});
  });
}
