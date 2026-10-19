const bool product = bool.fromEnvironment('dart.vm.product');

const String debugCSV = '4.141.0';

class Config {
  Config._();

  static const String packageName = 'com.nightmare.code';

  static const String versionName = String.fromEnvironment('VERSION');

  static const String defaultCodeServerVersion = String.fromEnvironment(
    'CSVERSION',
    defaultValue: debugCSV,
  );

  static String codeServerVersion = defaultCodeServerVersion;

  static int port = 20000;

  static String ubuntuFileName = 'ubuntu-noble-aarch64-pd-v4.18.0.tar.xz';
}
