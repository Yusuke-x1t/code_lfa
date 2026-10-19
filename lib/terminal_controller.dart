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
  double step = 17;
  String currentProgress = '';

  void bumpProgress() {
    try {
      int current = 0;
      if (progressFile.existsSync()) {
        final content = progressFile.readAsStringSync().trim();
        if (content.isNotEmpty) {
          current = int.tryParse(content) ?? 0;
        }
      } else {
        progressFile.createSync(recursive: true);
      }
      progressFile.writeAsStringSync('${current + 1}');
    } catch (e) {
      progressFile.writeAsStringSync('1');
    }
    update();
  }

  Future<void> vsCodeStartWhenSuccessBind() async {
    terminal.writeProgress('${S.current.listen_vscode_start}...');
    final Completer completer = Completer();
    Utf8Decoder decoder = const Utf8Decoder(allowMalformed: true);
    pseudoTerminal!.output.cast<List<int>>().transform(decoder).listen((event) async {
      if (event.contains('http://0.0.0.0:${Config.port}')) {
        Log.e(event);
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
      if (event.contains('already')) {
        Log.e(event);
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
      terminal.write(event);
    });
    await completer.future;
    bumpProgress();
    await Future.delayed(const Duration(milliseconds: 100));
    webviewHasOpen = true;
    openWebView();
    Future.delayed(const Duration(milliseconds: 2000), () {
      vsCodeStaring = false;
      update();
    });
  }

  Future<void> initEnvir() async {
    List<String> androidFiles = [
      'libbash.so',
      'libbusybox.so',
      'liblibtalloc.so.2.so',
      'libloader.so',
      'libproot.so',
      'libsudo.so'
    ];
    String libPath = await getLibPath();
    Log.i('libPath -> $libPath');

    for (int i = 0; i < androidFiles.length; i++) {
      final sourcePath = '$libPath/${androidFiles[i]}';
      String fileName = androidFiles[i].replaceAll(RegExp('^lib|\\.so\$'), '');
      String filePath = '${RuntimeEnvir.binPath}/$fileName';
      File file = File(filePath);
      FileSystemEntityType type = await FileSystemEntity.type(filePath);
      Log.i('$fileName type -> $type');
      if (type != FileSystemEntityType.notFound && type != FileSystemEntityType.link) {
        Log.i('find plain file -> $fileName, delete it');
        await file.delete();
      }
      Link link = Link(filePath);
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
    progressFile.createSync(recursive: true);
    progressFile.writeAsStringSync('0');
    progressFile.watch(events: FileSystemEvent.all).listen((event) async {
      if (event.type == FileSystemEvent.modify) {
        String content = await progressFile.readAsString();
        Log.e('content -> $content');
        if (content.isEmpty) {
          return;
        }
        progress = int.parse(content) / step;
        Log.e('progress -> $progress');
        update();
      }
    });
    progressDesFile.createSync(recursive: true);
    progressDesFile.writeAsStringSync('');
    progressDesFile.watch(events: FileSystemEvent.all).listen((event) async {
      if (event.type == FileSystemEvent.modify) {
        String content = await progressDesFile.readAsString();
        currentProgress = content;
        update();
      }
    });
  }

  void createBusyboxLink() {
    try {
      List<String> links = [
        ...['awk', 'ash', 'basename', 'bzip2', 'curl', 'cp', 'chmod', 'cut', 'cat', 'du', 'dd', 'find', 'grep', 'gzip'],
        ...['hexdump', 'head', 'id', 'lscpu', 'mkdir', 'realpath', 'rm', 'sed', 'stat', 'sh', 'tr', 'tar', 'uname', 'xargs', 'xz', 'xxd']
      ];

      for (String linkName in links) {
        Link link = Link('${RuntimeEnvir.binPath}/$linkName');
        if (!link.existsSync()) {
          link.createSync('${RuntimeEnvir.binPath}/busybox');
        }
      }
      Link link = Link('${RuntimeEnvir.binPath}/file');
      link.createSync('/system/bin/file');
    } catch (e) {
      Log.e('Create link failed -> $e');
    }
  }

  Future<void> loadCodeVersion() async {
    if (GetPlatform.isAndroid) {
      PermissionStatus status = await Permission.manageExternalStorage.request();
      Log.i('status -> $status');
      if (!status.isGranted) {
        return;
      }
    }

    final File file = File('/sdcard/code_version');
    try {
      if (!file.existsSync()) {
        file.createSync(recursive: true);
        file.writeAsStringSync(Config.defaultCodeServerVersion);
      }
    } catch (e) {
      Log.e('Create code_version file failed -> $e');
    }

    try {
      if (file.existsSync()) {
        Config.codeServerVersion = file.readAsStringSync().trim();
      }
    } catch (e) {
      Log.e('Read code_version file failed -> $e');
    }

    if (Config.codeServerVersion.trim().isEmpty) {
      Config.codeServerVersion = Config.defaultCodeServerVersion;
    }
  }

  bool get useCustomCodeServer => Config.codeServerVersion != Config.defaultCodeServerVersion;

  void setProgress(String description) {
    currentProgress = description;
    terminal.writeProgress(currentProgress);
  }

  Future<void> loadCodeServer() async {
    await loadCodeVersion();
    bumpProgress();
    Directory(RuntimeEnvir.tmpPath).createSync(recursive: true);
    Directory(RuntimeEnvir.homePath).createSync(recursive: true);
    Directory(RuntimeEnvir.binPath).createSync(recursive: true);
    bumpProgress();
    await initEnvir();
    bumpProgress();

    setProgress('${S.current.create_terminal_obj}...');
    pseudoTerminal = createPTY(rows: terminal.viewHeight, columns: terminal.viewWidth);
    bumpProgress();

    terminal.writeProgress('${S.current.current_code_version}:${Config.codeServerVersion} [${useCustomCodeServer ? 'custom' : ''}]');
    setProgress('${S.current.copy_proot_distro}...');
    await AssetsUtils.copyAssetToPath('assets/proot-distro.zip', '${RuntimeEnvir.homePath}/proot-distro.zip');
    bumpProgress();

    setProgress('${S.current.copy_ubuntu}...');
    await AssetsUtils.copyAssetToPath('assets/${Config.ubuntuFileName}', '${RuntimeEnvir.homePath}/${Config.ubuntuFileName}');
    bumpProgress();

    setProgress('${S.current.create_busybox_symlink}...');
    createBusyboxLink();
    bumpProgress();

    final String codeServerName = 'code-server-${Config.codeServerVersion}-linux-arm64.tar.gz';
    final String sourcePath = useCustomCodeServer ? '/sdcard/$codeServerName' : 'assets/$codeServerName';
    setProgress('${S.current.copy_code_server('[$sourcePath]')} ${RuntimeEnvir.tmpPath}...');

    try {
      if (useCustomCodeServer) {
        final File sourceFile = File(sourcePath);
        final File targetFile = File('${RuntimeEnvir.tmpPath}/$codeServerName');
        final File temporaryFile = File('${targetFile.path}.part');

        if (!await sourceFile.exists()) {
          throw FileSystemException(
            'No se encontró el paquete personalizado. Comprueba que esté en /sdcard y que el nombre sea exacto.',
            sourcePath,
          );
        }

        final int sourceLength = await sourceFile.length();
        bool targetIsValid = false;

        try {
          if (await targetFile.exists()) {
            targetIsValid = await targetFile.length() == sourceLength;
          }
        } on FileSystemException catch (e) {
          Log.e('Archivo temporal inválido; se volverá a copiar -> $e');
          targetIsValid = false;
        }

        if (targetIsValid) {
          Log.i('code server already copied to tmp, skip');
        } else {
          if (await temporaryFile.exists()) {
            await temporaryFile.delete();
          }

          await sourceFile.copy(temporaryFile.path);
          final int copiedLength = await temporaryFile.length();
          if (copiedLength != sourceLength) {
            await temporaryFile.delete();
            throw FileSystemException(
              'La copia temporal de code-server no coincide en tamaño.',
              temporaryFile.path,
            );
          }

          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          await temporaryFile.rename(targetFile.path);

          if (!await targetFile.exists() || await targetFile.length() != sourceLength) {
            throw FileSystemException(
              'La copia de code-server no superó la comprobación final.',
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
      terminal.write('Copy code server failed -> $e\r\n');
      return;
    }

    final String codeServerPath = '${RuntimeEnvir.tmpPath}/$codeServerName';
    setProgress('${S.current.gen_script}...');
    String fixHardLinkShell = '';
    try {
      Map<String, String> hardLinks = await getHardLinkMap(codeServerPath);
      fixHardLinkShell = genFixCodeServerHardLinkShell(hardLinks);
      Log.i('fixHardLinkShell -> $fixHardLinkShell');
    } catch (e) {
      terminal.write('Get hard link failed, will cause code-server start failed -> $e\r\n');
      return;
    }
    bumpProgress();
    bumpProgress();

    vsCodeStartWhenSuccessBind();
    bumpProgress();
    File('${RuntimeEnvir.homePath}/common.sh').writeAsStringSync('$commonScript\n$fixHardLinkShell');
    bumpProgress();
    startVsCode(pseudoTerminal!);
  }

  Future<void> startVsCode(Pty pseudoTerminal) async {
    vsCodeStaring = true;
    update();
    pseudoTerminal.writeString('source ${RuntimeEnvir.homePath}/common.sh\nstart_vs_code\n');
  }

  @override
  void onInit() {
    super.onInit();
    Future.delayed(Duration.zero, () async {
      if (privacySetting.get() == null) {
        await Get.to(PrivacyAgreePage(
          onAgreeTap: () {
            privacySetting.set(true);
            Get.back();
          },
        ));
      }
      syncProgress();
      loadCodeServer();
    });
  }
}
