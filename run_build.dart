// ignore_for_file: avoid_print

import 'dart:io';

const _appName = 'Netturbine';

String get _issScriptPath =>
    r'build\windows\x64\installer\Release\inno-script.iss';

String get _releaseBundleDir => r'build\windows\x64\runner\Release';

const _toolsDir = r'windows\tools';

/// Files shipped next to netturbine.exe: the elevated fan helper and the
/// PawnIO modules it loads from its own directory (see
/// windows/tools/fan_helper.cpp). Without these the installed app can never
/// register the NetturbineFanHelper service.
const _helperFiles = ['fan_helper.exe', 'LpcACPIEC.bin', 'IntelMSR.bin'];

String? findInnoBundleIscc() {
  final userProfile = Platform.environment['USERPROFILE'];
  if (userProfile == null || userProfile.isEmpty) return null;

  final versionsDir = Directory(
    '$userProfile${Platform.pathSeparator}.inno_bundle'
    '${Platform.pathSeparator}versions',
  );
  if (!versionsDir.existsSync()) return null;

  for (final versionDir in versionsDir.listSync().whereType<Directory>()) {
    final compiler = File(
      '${versionDir.path}${Platform.pathSeparator}ISCC.exe',
    );
    if (compiler.existsSync()) return compiler.path;
  }
  return null;
}

/// Locates the Inno Setup compiler: the ISCC env override first, then a
/// machine or per-user install, then the inno_bundle-managed copy under
/// ~/.inno_bundle.
String? findIscc() {
  final override = Platform.environment['ISCC'];
  final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
  final candidates = <String>[
    if (override != null && override.isNotEmpty) override,
    r'C:\Program Files (x86)\Inno Setup 6\iscc.exe',
    r'C:\Program Files\Inno Setup 6\iscc.exe',
    '$localAppData\\Programs\\Inno Setup 6\\iscc.exe',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return findInnoBundleIscc();
}

/// Returns a usable iscc.exe, downloading the inno_bundle-managed copy via
/// `dart run inno_bundle:setup_versions` when nothing is installed yet.
Future<String> ensureIscc() async {
  final found = findIscc();
  if (found != null) return found;

  print('  iscc.exe not found — installing Inno Setup via inno_bundle...');
  await runCommand('dart', ['run', 'inno_bundle:setup_versions']);

  final managed = findInnoBundleIscc();
  if (managed != null) return managed;

  print('✗ iscc.exe not found — install Inno Setup 6 or set ISCC to its path');
  exit(1);
}

void printHeader() {
  print('');
  print('╔════════════════════════════════════════════╗');
  print('║           Netturbine App Builder           ║');
  print('╚════════════════════════════════════════════╝');
  print('');
}

void printStep(String message) {
  print('');
  print('▸ $message');
  print('');
}

Future<void> runCommand(
  String executable,
  List<String> args, {
  bool shell = true,
}) async {
  final process = await Process.start(
    executable,
    args,
    mode: ProcessStartMode.inheritStdio,
    runInShell: shell,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    print('');
    print('✗ Command failed with exit code $exitCode');
    exit(exitCode);
  }
}

void ensureDistDir() {
  final distDir = Directory('dist');
  if (!distDir.existsSync()) {
    distDir.createSync();
  }
}

Future<String> copyToDist(String sourcePath, {String? destName}) async {
  ensureDistDir();
  final source =
      FileSystemEntity.typeSync(sourcePath) == FileSystemEntityType.directory
      ? Directory(sourcePath)
      : File(sourcePath);

  final fileName = destName ?? source.path.split(Platform.pathSeparator).last;
  final destPath = 'dist${Platform.pathSeparator}$fileName';

  if (FileSystemEntity.typeSync(destPath) != FileSystemEntityType.notFound) {
    if (FileSystemEntity.typeSync(destPath) == FileSystemEntityType.directory) {
      await Directory(destPath).delete(recursive: true);
    } else {
      await File(destPath).delete();
    }
  }

  if (source is Directory) {
    await _copyDirectory(source, Directory(destPath));
    await source.delete(recursive: true);
  } else if (source is File) {
    await source.rename(destPath);
  }
  print('  Moved to: $destPath');
  return destPath;
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create();
  await for (final entity in source.list(recursive: true)) {
    final relativePath = entity.path.substring(source.path.length);
    final newPath = '${destination.path}$relativePath';
    if (entity is File) {
      await entity.copy(newPath);
    } else if (entity is Directory) {
      await Directory(newPath).create();
    }
  }
}

String _readBinaryName() {
  final cmakeFile = File('windows/CMakeLists.txt');
  if (!cmakeFile.existsSync()) {
    print('✗ windows/CMakeLists.txt not found');
    exit(1);
  }
  final match = RegExp(
    r'set\(BINARY_NAME\s+"(.+?)"\)',
  ).firstMatch(cmakeFile.readAsStringSync());
  if (match == null) {
    print('✗ Could not find BINARY_NAME in windows/CMakeLists.txt');
    exit(1);
  }
  return match.group(1)!;
}

String _versionFromPubspec() {
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) return 'unknown';
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  // Strip the "+build" suffix for use in filenames.
  return match?.group(1)?.split('+').first ?? 'unknown';
}

/// dist filename: `<app>-<version>-<arch>.<ext>`
String _distFileName(String arch, String ext) =>
    '$_appName-${_versionFromPubspec()}-$arch.$ext';

/// Copies fan_helper.exe and its PawnIO modules into the Flutter Release
/// bundle. Must run before `dart run inno_bundle` generates the ISS script —
/// its [Files] section is built from a directory listing of the bundle.
void _bundleFanHelpers() {
  final bundleDir = Directory(_releaseBundleDir);
  if (!bundleDir.existsSync()) bundleDir.createSync(recursive: true);
  for (final name in _helperFiles) {
    final source = File('$_toolsDir${Platform.pathSeparator}$name');
    if (!source.existsSync()) {
      print('✗ Missing $name in $_toolsDir — the installer would ship an app');
      print('  that cannot register the fan control service');
      exit(1);
    }
    source.copySync('${bundleDir.path}${Platform.pathSeparator}$name');
  }
  print('  Bundled: ${_helperFiles.join(', ')}');
}

String _findWindowsInstaller() {
  final releaseDir = Directory(
    'build${Platform.pathSeparator}windows${Platform.pathSeparator}x64'
    '${Platform.pathSeparator}installer${Platform.pathSeparator}Release',
  );
  if (!releaseDir.existsSync()) {
    print('✗ Installer output directory not found');
    exit(1);
  }

  final installers = releaseDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('-installer.exe'))
      .toList();

  if (installers.isEmpty) {
    final binaryName = _readBinaryName();
    final legacy = File(
      '${releaseDir.path}${Platform.pathSeparator}$binaryName-setup.exe',
    );
    if (legacy.existsSync()) return legacy.path;

    print('✗ No installer .exe found in ${releaseDir.path}');
    exit(1);
  }

  if (installers.length > 1) {
    print('✗ Multiple installer exes found, expected only one');
    for (final installer in installers) {
      print('    - ${installer.path.split(Platform.pathSeparator).last}');
    }
    exit(1);
  }

  return installers.first.path;
}

void _patchIssScript(String binaryName) {
  final issFile = File(_issScriptPath);
  if (!issFile.existsSync()) {
    print('✗ ISS script not found at $_issScriptPath');
    exit(1);
  }

  var content = issFile.readAsStringSync();
  final wrongExe = RegExp(r'\\([a-z_]+)\.exe').firstMatch(content);
  if (wrongExe != null) {
    final wrongName = wrongExe.group(1)!;
    if (wrongName != binaryName) {
      content = content.replaceAll('$wrongName.exe', '$binaryName.exe');
      print('  Patched: $wrongName.exe -> $binaryName.exe');
    }
  }

  // Bake the app icon into the installer/uninstaller exe. Inno 6 merges
  // Setup and Uninstall into one exe, so SetupIconFile covers both. It
  // resolves relative paths against the script's directory, so use the
  // absolute path. Shortcuts and Add/Remove Programs already inherit
  // netturbine.exe's icon via UninstallDisplayIcon and the [Icons] entries.
  final iconPath = File(r'windows\runner\resources\app_icon.ico').absolute.path;
  if (!File(iconPath).existsSync()) {
    print('✗ App icon not found at $iconPath');
    exit(1);
  }
  content = content.replaceAllMapped(
    RegExp(r'^SetupIconFile=.*$', multiLine: true),
    (_) => 'SetupIconFile=$iconPath',
  );

  issFile.writeAsStringSync(content);
  print('  Icon: $iconPath');
}

/// Inserts [entry] at the end of the named ISS section, or appends a new
/// section at the end of the file when none exists yet.
String _insertIntoIssSection(String content, String section, String entry) {
  final header = RegExp(
    '^\\[${RegExp.escape(section)}\\]\\s*\$',
    multiLine: true,
  ).firstMatch(content);
  if (header == null) {
    return '$content\n[$section]\n$entry';
  }
  final remainder = content.substring(header.end);
  final nextSection = RegExp(
    r'^\[[^\r\n]+\]\s*$',
    multiLine: true,
  ).firstMatch(remainder);
  final insertAt = nextSection == null
      ? content.length
      : header.end + nextSection.start;
  return content.replaceRange(insertAt, insertAt, '$entry\n');
}

/// Adds a post-install entry that registers the NetturbineFanHelper Windows
/// service — shellexec + runas produces one UAC prompt from the finish-page
/// checkbox — plus an uninstall hook that removes it again.
void _registerFanService() {
  final issFile = File(_issScriptPath);
  if (!issFile.existsSync()) {
    print('✗ ISS script not found at $_issScriptPath');
    exit(1);
  }

  var content = issFile.readAsStringSync();
  const marker = '; Netturbine fan helper service';
  if (content.contains(marker)) {
    return;
  }

  content = _insertIntoIssSection(
    content,
    'Run',
    '$marker\n'
        'Filename: "{app}\\fan_helper.exe"; Parameters: "install"; '
        'Description: "Install fan control service (requires administrator)"; '
        'Flags: postinstall shellexec skipifsilent; Verb: "runas"',
  );
  content = _insertIntoIssSection(
    content,
    'UninstallRun',
    'Filename: "{app}\\fan_helper.exe"; Parameters: "uninstall"; '
        'Flags: skipifdoesntexist; RunOnceId: "NetturbineFanService"',
  );

  issFile.writeAsStringSync(content);
  print('  Added: fan service install/uninstall entries');
}

Future<void> buildWindows() async {
  final binaryName = _readBinaryName();
  print('  Binary name: $binaryName');

  printStep(
    'Step 1/4 — Building Flutter app and generating installer script...',
  );
  // The helper files must be in the bundle before inno_bundle lists it for
  // the generated [Files] section; re-copy after the build in case the
  // directory was recreated.
  _bundleFanHelpers();
  await runCommand('dart', [
    'run',
    'inno_bundle',
    '--no-installer',
    '--release',
  ]);
  _bundleFanHelpers();

  printStep('Step 2/4 — Patching installer script...');
  _patchIssScript(binaryName);
  _registerFanService();

  printStep('Step 3/4 — Compiling installer...');
  // The iscc path contains spaces; spawning it through a shell would split it
  // at the first space, so this one runs without cmd.exe in between.
  await runCommand(await ensureIscc(), [_issScriptPath], shell: false);

  printStep('Step 4/4 — Copying to dist folder...');
  final installerPath = _findWindowsInstaller();
  final installerName = _distFileName('x64', 'exe');
  await copyToDist(installerPath, destName: installerName);

  print('');
  print('✓ Windows build complete!');
  print('  Installer: dist/$installerName');
  print('');
}

Future<void> main() async {
  printHeader();

  if (!Platform.isWindows) {
    print('✗ The Windows installer can only be built on Windows');
    exit(1);
  }

  await buildWindows();
}
