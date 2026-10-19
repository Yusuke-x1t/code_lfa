import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:settings/settings.dart';
import 'package:xterm/xterm.dart';

import 'config.dart';
import 'generated/l10n.dart';
import 'script.dart';
import 'utils.dart';

class HomeController extends GetxController {
  bool vsCodeStaring = false;

  SettingNode privacySetting = 'privacy'.setting;

  Pty? pseudoTerminal;

  late Terminal terminal = Terminal(
    maxLines: 10000,
    onResize: (width, height, pixelWidth, pixelHeight) {
      pseudoTerminal?.resize(height, width);
    },
    onOutput: (data) {
      pseudoTerminal?.writeString(data);
    },
  );

  bool webviewHasOpen = false;

  File progressFile = File('${RuntimeEnvir.tmpPath}/progress');
  File progressDesFile = File('${RuntimeEnvir.tmpPath}/progress_des');

  double progress = 0.0;
  double step = 16;
  String currentProgress = '';

  Timer? _progressTimer;
  bool _readingProgress = false;

  void bumpProgress() {
    try {
      progressFile.parent.createSync(recursive: true);

      int current = 0;

      if (progressFile.existsSync()) {
        current = int.tryParse(
              progressFile.readAsStringSync().trim(),
            ) ??
            0;
      }

      final int next = current + 1;

      progressFile.writeAsStringSync(
        '$next',
        flush: true,
      );

      progress = (next / step).clamp(0.0, 1.0).toDouble();

      update();
    } catch (e) {
      Log.e('Update progress failed -> $e');
    }
  }

  Future<void> vsCodeStartWhenSuccessBind() async {
    terminal.writeProgress(
      '${S.current.listen_vscode_start}...',
    );

    final Completer<void> completer = Completer<void>();

    const Utf8Decoder decoder = Utf8Decoder(
      allowMalformed: true,
    );

    String recentOutput = '';

    pseudoTerminal!.output
        .cast<List<int>>()
        .transform(decoder)
        .listen(
      (event) {
        recentOutput += event;

        if (recentOutput.length > 8192) {
          recentOutput = recentOutput.substring(
            recentOutput.length - 4096,
          );
        }

        final String address =
            'http://0.0.0.0:${Config.port}';

        if (!completer.isCompleted &&
            recentOutput.contains(address)) {
          completer.complete();
        }

        terminal.write(event);
      },
      onError: (Object error) {
        Log.e('Terminal output failed -> $error');

        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
    );

    try {
      await completer.future;
    } catch (e) {
      Log.e('Waiting for Code Server failed -> $e');
      return;
    }

    bumpProgress();

    await Future.delayed(
      const Duration(milliseconds: 100),
    );

    webviewHasOpen = true;
    update();

    openWebView();

    Future.delayed(
      const Duration(milliseconds: 2000),
      () {
        vsCodeStaring = false;
        update();
      },
    );
  }

  Future<void> initEnvir() async {
    final List<String> androidFiles = [
      'libbash.so',
      'libbusybox.so',
      'liblibtalloc.so.2.so',
      'libloader.so',
      'libproot.so',
      'libsudo.so',
    ];

    final String libPath = await getLibPath();

    Log.i('libPath -> $libPath');

    for (int i = 0; i < androidFiles.length; i++) {
      final String sourcePath =
          '$libPath/${androidFiles[i]}';

      final String fileName = androidFiles[i]
          .replaceAll(RegExp('^lib|\\.so\$'), '');

      final String filePath =
          '${RuntimeEnvir.binPath}/$fileName';

      final File file = File(filePath);

      final FileSystemEntityType type =
          await FileSystemEntity.type(filePath);

      Log.i('$fileName type -> $type');

      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.link) {
        Log.i('find plain file -> $fileName, delete it');
        await file.delete();
      }

      final Link link = Link(filePath);

      if (link.existsSync()) {
        link.deleteSync();
      }

      try {
        Log.i('create link -> $fileName ${link.path}');
        link.createSync(sourcePath);
      } catch (e) {
        Log.e('installAdbToEnvir error -> $e');
      }
    }
  }

  void syncProgress() {
    progressFile.parent.createSync(recursive: true);
    progressDesFile.parent.createSync(recursive: true);

    progressFile.writeAsStringSync(
      '0',
      flush: true,
    );

    progressDesFile.writeAsStringSync(
      '',
      flush: true,
    );

    progress = 0.0;
    currentProgress = '';

    _progressTimer?.cancel();

    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (timer) {
        if (_readingProgress) {
          return;
        }

        _readingProgress = true;

        try {
          if (progressFile.existsSync()) {
            final String content =
                progressFile.readAsStringSync().trim();

            final int? current = int.tryParse(content);

            if (current != null) {
              progress = (current / step)
                  .clamp(0.0, 1.0)
                  .toDouble();
            }
          }

          if (progressDesFile.existsSync()) {
            final String description =
                progressDesFile.readAsStringSync().trim();

            if (description.isNotEmpty) {
              currentProgress = description;
            }
          }

          update();
        } catch (e) {
          Log.e('Read startup progress failed -> $e');
        } finally {
          _readingProgress = false;
        }
      },
    );

    update();
  }

  void createBusyboxLink() {
    try {
      final List<String> links = [
        ...[
          'awk',
          'ash',
          'basename',
          'bzip2',
          'curl',
          'cp',
          'chmod',
          'cut',
          'cat',
          'du',
          'dd',
          'find',
          'grep',
          'gzip',
        ],
        ...[
          'hexdump',
          'head',
          'id',
          'lscpu',
          'mkdir',
          'realpath',
          'rm',
          'sed',
          'stat',
          'sh',
          'tr',
          'tar',
          'uname',
          'xargs',
          'xz',
          'xxd',
        ],
      ];

      for (final String linkName in links) {
        final Link link = Link(
          '${RuntimeEnvir.binPath}/$linkName',
        );

        if (!link.existsSync()) {
          link.createSync(
            '${RuntimeEnvir.binPath}/busybox',
          );
        }
      }

      final Link fileLink = Link(
        '${RuntimeEnvir.binPath}/file',
      );

      if (!fileLink.existsSync()) {
        fileLink.createSync('/system/bin/file');
      }
    } catch (e) {
      Log.e('Create link failed -> $e');
    }
  }

  Future<void> loadCodeVersion() async {
    if (GetPlatform.isAndroid) {
      final PermissionStatus status =
          await Permission.manageExternalStorage.request();

      Log.i('status -> $status');

      if (!status.isGranted) {
        return;
      }
    }

    final File file = File('/sdcard/code_version');

    try {
      if (!file.existsSync()) {
        file.createSync(recursive: true);

        file.writeAsStringSync(
          Config.defaultCodeServerVersion,
        );
      }
    } catch (e) {
      Log.e('Create code_version file failed -> $e');
    }

    try {
      if (file.existsSync()) {
        Config.codeServerVersion =
            file.readAsStringSync().trim();
      }
    } catch (e) {
      Log.e('Read code_version file failed -> $e');
    }

    if (Config.codeServerVersion.trim().isEmpty) {
      Config.codeServerVersion =
          Config.defaultCodeServerVersion;
    }
  }

  bool get useCustomCodeServer =>
      Config.codeServerVersion !=
      Config.defaultCodeServerVersion;

  void setProgress(String description) {
    currentProgress = description;

    try {
      progressDesFile.parent.createSync(recursive: true);

      progressDesFile.writeAsStringSync(
        description,
        flush: true,
      );
    } catch (e) {
      Log.e('Write startup description failed -> $e');
    }

    terminal.writeProgress(description);
    update();
  }

  Future<void> loadCodeServer() async {
    await loadCodeVersion();

    bumpProgress();

    Directory(RuntimeEnvir.tmpPath).createSync(
      recursive: true,
    );

    Directory(RuntimeEnvir.homePath).createSync(
      recursive: true,
    );

    Directory(RuntimeEnvir.binPath).createSync(
      recursive: true,
    );

    bumpProgress();

    await initEnvir();

    bumpProgress();

    setProgress(
      '${S.current.create_terminal_obj}...',
    );

    pseudoTerminal = createPTY(
      rows: terminal.viewHeight,
      columns: terminal.viewWidth,
    );

    bumpProgress();

    terminal.writeProgress(
      '${S.current.current_code_version}:'
      '${Config.codeServerVersion} '
      '[${useCustomCodeServer ? 'custom' : ''}]',
    );

    setProgress(
      '${S.current.copy_proot_distro}...',
    );

    await AssetsUtils.copyAssetToPath(
      'assets/proot-distro.zip',
      '${RuntimeEnvir.homePath}/proot-distro.zip',
    );

    bumpProgress();

    setProgress(
      '${S.current.copy_ubuntu}...',
    );

    await AssetsUtils.copyAssetToPath(
      'assets/${Config.ubuntuFileName}',
      '${RuntimeEnvir.homePath}/${Config.ubuntuFileName}',
    );

    bumpProgress();

    setProgress(
      '${S.current.create_busybox_symlink}...',
    );

    createBusyboxLink();

    bumpProgress();

    final String codeServerName =
        'code-server-${Config.codeServerVersion}-linux-arm64.tar.gz';

    final String sourcePath = useCustomCodeServer
        ? '/sdcard/$codeServerName'
        : 'assets/$codeServerName';

    setProgress(
      '${S.current.copy_code_server('[$sourcePath]')} '
      '${RuntimeEnvir.tmpPath}...',
    );

    try {
      if (useCustomCodeServer) {
        final File sourceFile = File(sourcePath);

        final File targetFile = File(
          '${RuntimeEnvir.tmpPath}/$codeServerName',
        );

        final File temporaryFile = File(
          '${targetFile.path}.part',
        );

        if (!await sourceFile.exists()) {
          throw FileSystemException(
            'No se encontró el paquete personalizado. '
            'Comprueba que esté en /sdcard y que el '
            'nombre sea exacto.',
            sourcePath,
          );
        }

        final int sourceLength =
            await sourceFile.length();

        bool targetIsValid = false;

        try {
          if (await targetFile.exists()) {
            targetIsValid =
                await targetFile.length() == sourceLength;
          }
        } on FileSystemException catch (e) {
          Log.e(
            'Archivo temporal inválido; '
            'se volverá a copiar -> $e',
          );

          targetIsValid = false;
        }

        if (targetIsValid) {
          Log.i(
            'code server already copied to tmp, skip',
          );
        } else {
          if (await temporaryFile.exists()) {
            await temporaryFile.delete();
          }

          await sourceFile.copy(
            temporaryFile.path,
          );

          final int copiedLength =
              await temporaryFile.length();

          if (copiedLength != sourceLength) {
            await temporaryFile.delete();

            throw FileSystemException(
              'La copia temporal de code-server '
              'no coincide en tamaño.',
              temporaryFile.path,
            );
          }

          if (await targetFile.exists()) {
            await targetFile.delete();
          }

          await temporaryFile.rename(
            targetFile.path,
          );

          if (!await targetFile.exists() ||
              await targetFile.length() != sourceLength) {
            throw FileSystemException(
              'La copia de code-server no superó '
              'la comprobación final.',
              targetFile.path,
            );
          }
        }
      } else {
        await AssetsUtils.copyAssetToPath(
          sourcePath,
          '${RuntimeEnvir.tmpPath}/$codeServerName',
        );
      }
    } catch (e) {
      Log.e('Copy code server failed -> $e');

      terminal.write(
        'Copy code server failed -> $e\r\n',
      );

      setProgress(
        'Error al copiar code-server: $e',
      );

      return;
    }

    final String codeServerPath =
        '${RuntimeEnvir.tmpPath}/$codeServerName';

    setProgress(
      '${S.current.gen_script}...',
    );

    String fixHardLinkShell = '';

    try {
      final Map<String, String> hardLinks =
          await getHardLinkMap(codeServerPath);

      fixHardLinkShell =
          genFixCodeServerHardLinkShell(hardLinks);

      Log.i(
        'fixHardLinkShell -> $fixHardLinkShell',
      );
    } catch (e) {
      terminal.write(
        'Get hard link failed, '
        'will cause code-server start failed -> $e\r\n',
      );

      setProgress(
        'Error al preparar enlaces de code-server: $e',
      );

      return;
    }

    bumpProgress();
    bumpProgress();

    vsCodeStartWhenSuccessBind();

    bumpProgress();

    File(
      '${RuntimeEnvir.homePath}/common.sh',
    ).writeAsStringSync(
      '$commonScript\n$fixHardLinkShell',
    );

    bumpProgress();

    startVsCode(pseudoTerminal!);
  }

  Future<void> startVsCode(Pty pseudoTerminal) async {
    vsCodeStaring = true;

    update();

    pseudoTerminal.writeString(
      'source ${RuntimeEnvir.homePath}/common.sh\n'
      'start_vs_code\n',
    );
  }

  @override
  void onInit() {
    super.onInit();

    Future.delayed(
      Duration.zero,
      () async {
        if (privacySetting.get() == null) {
          await Get.to(
            PrivacyAgreePage(
              onAgreeTap: () {
                privacySetting.set(true);
                Get.back();
              },
            ),
          );
        }

        syncProgress();

        loadCodeServer();
      },
    );
  }

  @override
  void onClose() {
    _progressTimer?.cancel();
    super.onClose();
  }
}
