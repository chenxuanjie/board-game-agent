import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:remote_update/remote_update.dart';

/// Launches only a verified installer, without a command shell or forced kill.
class WindowsUpdateInstaller implements UpdateInstaller {
  WindowsUpdateInstaller({
    required this.beforeInstall,
    required this.onInstallerLaunched,
    Future<void> Function(String, List<String>)? launch,
    String? executablePath,
  }) : _launch = launch ?? _launchDetached,
       _executablePath = executablePath ?? Platform.resolvedExecutable;

  final Future<void> Function() beforeInstall;
  final Future<void> Function() onInstallerLaunched;
  final Future<void> Function(String, List<String>) _launch;
  final String _executablePath;

  static Future<void> _launchDetached(String file, List<String> args) async {
    await Process.start(
      file,
      args,
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
  }

  @override
  Future<UpdateInstallResult> install(DownloadedUpdateArtifact artifact) async {
    final file = File(artifact.filePath).absolute;
    if (artifact.artifact.platform != 'windows' ||
        artifact.artifact.architecture != 'x64' ||
        !file.path.toLowerCase().endsWith('.exe')) {
      throw StateError('更新包不是 Windows x64 安装程序');
    }
    // Reverify immediately before execution, including a reused cached file.
    if (!await file.exists() ||
        await file.length() != artifact.artifact.size ||
        (await sha256.bind(file.openRead()).first).toString() !=
            artifact.artifact.sha256) {
      throw StateError('安装包校验失败，请重新下载');
    }
    final input = await file.open();
    try {
      final header = await input.read(2);
      if (header.length != 2 || header[0] != 0x4d || header[1] != 0x5a) {
        throw StateError('安装包格式无效，请重新下载');
      }
    } finally {
      await input.close();
    }
    await beforeInstall();
    final currentDirectory = File(_executablePath).absolute.parent;
    final args = <String>[
      '/SP-',
      '/NORESTART',
      '/NOFORCECLOSEAPPLICATIONS',
      // Only an Inno-installed app may direct an upgrade into its own folder.
      // A portable/development executable instead opens the normal wizard.
      if (await File('${currentDirectory.path}/unins000.exe').exists())
        '/DIR=${currentDirectory.path}',
    ];
    await _launch(file.path, args);
    await onInstallerLaunched();
    return const UpdateInstallResult(
      status: UpdateInstallStatus.launched,
      message: '安装程序已启动',
    );
  }
}
