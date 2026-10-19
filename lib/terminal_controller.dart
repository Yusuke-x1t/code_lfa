
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
  bool webviewHasOpen = false;

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

  final File progressFile =
      File('${RuntimeEnvir.tmpPath}/progress');

  final File progressDesFile =
      File('${RuntimeEnvir.tmpPath}/progress_des');

  double progress = 0.0;
  double step = 16;
  String currentProgress = '';

  Timer? _progressTimer;
  bool _readingProgress = false;
  StreamSubscription<String>? _terminalOutputSubscription;

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

  void syncProgress() {
    progressFile.parent.createSync(recursive: true);
    progressDesFile.parent.createSync(recursive: true);

    progressFile.writeAsStringSync('0', flush: true);
    progressDesFile.writeAsStringSync('', flush: true);

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
            final int? current = int.tryParse(
              progressFile.readAsStringSync().trim(),
            );

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
          Log.e('Read progress failed -> $e');
        } finally {
          _readingProgress = false;
        }
      },
    );

    update();
  }

  void setProgress(String description) {
    currentProgress = description;

    try {
      progressDesFile.parent.createSync(recursive: true);
      progressDesFile.writeAsStringSync(
        description,
        flush: true,
      );
    } catch (e) {
      Log.e('Write progress description failed -> $e');
    }

    terminal.writeProgress(description);
    update();
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

    for (final String androidFile in androidFiles) {
      final String sourcePath = '$libPath/$androidFile';

      final String fileName = androidFile.replaceAll(
        RegExp(r'^lib|\.so$'),
        '',
      );

      final String filePath = '${RuntimeEnvir.binPath}/$fileName';
      final File file = File(filePath);

      final FileSystemEntityType type =
          await FileSystemEntity.type(filePath);

      Log.i('$fileName type -> $type');

      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.link) {
        await file.delete();
      }

      final Link link = Link(filePath);

      if (link.existsSync()) {
        link.deleteSync();
      }

      try {
        link.createSync(sourcePath);
      } catch (e) {
        Log.e('Create environment link failed -> $e');
      }
    }
  }

  void createBusyboxLink() {
    try {
      final List<String> links = [
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
      ];

      for (final String linkName in links) {
        final Link link =
            Link('${RuntimeEnvir.binPath}/$linkName');

        if (!link.existsSync()) {
          link.createSync('${RuntimeEnvir.binPath}/busybox');
        }
      }

      final Link fileLink =
          Link('${RuntimeEnvir.binPath}/file');

      if (!fileLink.existsSync()) {
        fileLink.createSync('/system/bin/file');
      }
    } catch (e) {
      Log.e('Create BusyBox links failed -> $e');
    }
  }

  Future<void> loadCodeVersion() async {
    if (GetPlatform.isAndroid) {
      final PermissionStatus status =
          await Permission.manageExternalStorage.request();

      Log.i('Storage permission -> $status');

      if (!status.isGranted) {
        Log.i(
          'Storage permission not granted; '
          'using the default code-server version.',
        );
        Config.codeServerVersion =
            Config.defaultCodeServerVersion;
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

      if (file.existsSync()) {
        Config.codeServerVersion =
            file.readAsStringSync().trim();
      }
    } catch (e) {
      Log.e('Read code-server version failed -> $e');
    }

    if (Config.codeServerVersion.trim().isEmpty) {
      Config.codeServerVersion =
          Config.defaultCodeServerVersion;
    }
  }

  bool get useCustomCodeServer =>
      Config.codeServerVersion !=
      Config.defaultCodeServerVersion;

  Future<void> vsCodeStartWhenSuccessBind() async {
    final Pty? pty = pseudoTerminal;

    if (pty == null) {
      setProgress('Error: la terminal PTY no se creó.');
      return;
    }

    setProgress(
      'Esperando a Code Server en el puerto ${Config.port}...',
    );

    await _terminalOutputSubscription?.cancel();

    _terminalOutputSubscription = pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
      (event) {
        terminal.write(event);
      },
      onError: (Object error) {
        Log.e('Terminal output error -> $error');
        terminal.write('\r\nTerminal output error: $error\r\n');
        setProgress('Error leyendo la salida de la terminal: $error');
      },
    );

    bool serverReady = false;

    for (int attempt = 0; attempt < 180; attempt++) {
      await Future.delayed(const Duration(seconds: 1));

      try {
        final Socket socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          Config.port,
          timeout: const Duration(milliseconds: 900),
        );

        socket.destroy();
        serverReady = true;
        break;
      } catch (_) {
        if (attempt % 5 == 0) {
          setProgress(
            'Iniciando Code Server... '
            'esperando el puerto ${Config.port} '
            '(${attempt + 1}/180)',
          );
        }
      }
    }

    if (!serverReady) {
      setProgress(
        'Code Server no respondió en el puerto '
        '${Config.port}. Revisa los errores mostrados '
        'en la terminal.',
      );

      terminal.write(
        '\r\nERROR: Code Server no abrió el puerto '
        '${Config.port} tras 180 segundos.\r\n',
      );

      return;
    }

    await Future.delayed(const Duration(milliseconds: 350));

    bumpProgress();

    webviewHasOpen = true;
    update();

    try {
      openWebView();
    } catch (e) {
      webviewHasOpen = false;
      setProgress('No se pudo abrir la WebView: $e');
      Log.e('Open WebView failed -> $e');
      return;
    }

    Future.delayed(const Duration(seconds: 2), () {
      vsCodeStaring = false;
      update();
    });
  }

  Future<void> loadCodeServer() async {
    try {
      await _loadCodeServer();
    } catch (e) {
      Log.e('Code Server startup failed -> $e');

      terminal.write(
        '\r\nSTARTUP ERROR:\r\n$e\r\n',
      );

      setProgress('Error al iniciar Code Server: $e');
    }
  }

  Future<void> _loadCodeServer() async {
    setProgress('Preparando el entorno...');

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

    setProgress('Preparando los enlaces de Android...');
    await initEnvir();
    bumpProgress();

    setProgress('${S.current.create_terminal_obj}...');

    pseudoTerminal = createPTY(
      rows: terminal.viewHeight,
      columns: terminal.viewWidth,
    );

    bumpProgress();

    terminal.writeProgress(
      '${S.current.current_code_version}:'
      '${Config.codeServerVersion}',
    );

    setProgress('${S.current.copy_proot_distro}...');

    await AssetsUtils.copyAssetToPath(
      'assets/proot-distro.zip',
      '${RuntimeEnvir.homePath}/proot-distro.zip',
    );

    bumpProgress();

    setProgress('${S.current.copy_ubuntu}...');

    await AssetsUtils.copyAssetToPath(
      'assets/${Config.ubuntuFileName}',
      '${RuntimeEnvir.homePath}/${Config.ubuntuFileName}',
    );

    bumpProgress();

    setProgress('${S.current.create_busybox_symlink}...');
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

        if (!await sourceFile.exists()) {
          throw FileSystemException(
            'No se encontró el paquete personalizado.',
            sourcePath,
          );
        }

        final File targetFile = File(
          '${RuntimeEnvir.tmpPath}/$codeServerName',
        );

        final File temporaryFile = File(
          '${targetFile.path}.part',
        );

        final int sourceLength = await sourceFile.length();

        bool targetIsValid = false;

        if (await targetFile.exists()) {
          targetIsValid =
              await targetFile.length() == sourceLength;
        }

        if (!targetIsValid) {
          if (await temporaryFile.exists()) {
            await temporaryFile.delete();
          }

          await sourceFile.copy(temporaryFile.path);

          if (await temporaryFile.length() != sourceLength) {
            await temporaryFile.delete();

            throw FileSystemException(
              'La copia de code-server tiene un tamaño incorrecto.',
              temporaryFile.path,
            );
          }

          if (await targetFile.exists()) {
            await targetFile.delete();
          }

          await temporaryFile.rename(targetFile.path);
        }
      } else {
        await AssetsUtils.copyAssetToPath(
          sourcePath,
          '${RuntimeEnvir.tmpPath}/$codeServerName',
        );
      }
    } catch (e) {
      terminal.write(
        '\r\nCopy code server failed: $e\r\n',
      );
      setProgress('Error al copiar code-server: $e');
      return;
    }

    final String codeServerPath =
        '${RuntimeEnvir.tmpPath}/$codeServerName';

    setProgress('${S.current.gen_script}...');

    String fixHardLinkShell;

    try {
      final Map<String, String> hardLinks =
          await getHardLinkMap(codeServerPath);

      fixHardLinkShell =
          genFixCodeServerHardLinkShell(hardLinks);
    } catch (e) {
      terminal.write(
        '\r\nGet hard link failed: $e\r\n',
      );

      setProgress('Error preparando los enlaces: $e');
      return;
    }

    bumpProgress();
    bumpProgress();

    File('${RuntimeEnvir.homePath}/common.sh')
        .writeAsStringSync(
      '$commonScript\n$fixHardLinkShell',
    );

    bumpProgress();

    startVsCode(pseudoTerminal!);

    vsCodeStartWhenSuccessBind();
  }

  Future<void> startVsCode(Pty pty) async {
    vsCodeStaring = true;
    update();

    pty.writeString(
      'source ${RuntimeEnvir.homePath}/common.sh\n'
      'start_vs_code\n',
    );
  }

  @override
  void onInit() {
    super.onInit();

    Future<void>.delayed(Duration.zero, () async {
      try {
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
        await loadCodeServer();
      } catch (e) {
        Log.e('Initialization failed -> $e');
        setProgress('Error de inicialización: $e');
      }
    });
  }

  @override
  void onClose() {
    _progressTimer?.cancel();
    _terminalOutputSubscription?.cancel();
    super.onClose();
  }
}
