import 'dart:io';

class WindowsStartupService {
  const WindowsStartupService({
    String appName = 'Send to PC',
    String? executablePath,
  })  : _appName = appName,
        _executablePath = executablePath;

  final String _appName;
  final String? _executablePath;

  Future<void> setEnabled(bool enabled) async {
    if (!Platform.isWindows) {
      return;
    }

    final result = enabled ? await _enable() : await _disable();
    if (!enabled && _isMissingStartupValue(result)) {
      return;
    }
    if (result.exitCode != 0) {
      throw StateError(
        'Could not ${enabled ? 'enable' : 'disable'} Windows startup: '
        '${result.stderr}',
      );
    }
  }

  Future<ProcessResult> _enable() {
    final executable = _executablePath ?? Platform.resolvedExecutable;
    return Process.run(
      'reg.exe',
      <String>[
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
        '/v',
        _appName,
        '/t',
        'REG_SZ',
        '/d',
        '"$executable"',
        '/f',
      ],
    );
  }

  bool _isMissingStartupValue(ProcessResult result) {
    if (result.exitCode == 0) {
      return false;
    }
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    return output.contains('unable to find') ||
        output.contains('cannot find') ||
        output.contains('not found');
  }

  Future<ProcessResult> _disable() {
    return Process.run(
      'reg.exe',
      <String>[
        'delete',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
        '/v',
        _appName,
        '/f',
      ],
    );
  }
}