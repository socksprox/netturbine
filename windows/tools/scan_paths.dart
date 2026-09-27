import 'dart:io';

// Scope-tracking AML scan: resolves namespace paths for Devices, Scopes,
// Methods, and names. Also handles NameString prefixes (\ ^ Dual/MultiName).

int pkgLen(List<int> b, int i) {
  final b0 = b[i];
  final follow = b0 >> 6;
  if (follow == 0) return b0 & 0x3F;
  var len = b0 & 0x0F;
  for (var k = 0; k < follow; k++) {
    len |= b[i + 1 + k] << (4 + 8 * k);
  }
  return len;
}

int pkgLenSize(List<int> b, int i) => 1 + (b[i] >> 6);

bool isNameSeg(List<int> b, int i) {
  if (i + 4 > b.length) return false;
  for (var k = 0; k < 4; k++) {
    final c = b[i + k];
    final ok =
        (c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39) || c == 0x5F;
    if (!ok) return false;
  }
  return true;
}

String nameAt(List<int> b, int i) => String.fromCharCodes(b.sublist(i, i + 4));

/// Parses a NameString at [i]; returns (name, consumedBytes).
(String, int) nameString(List<int> b, int i) {
  var parts = <String>[];
  var j = i;
  // root + prefixes
  while (b[j] == 0x5C || b[j] == 0x5E) {
    j++;
  }
  if (b[j] == 0x2E) {
    // DualNamePrefix
    parts.add(nameAt(b, j + 1));
    parts.add(nameAt(b, j + 5));
    return (parts.join('.'), j - i + 9);
  } else if (b[j] == 0x2F) {
    // MultiNamePrefix + count
    final n = b[j + 1];
    j += 2;
    for (var k = 0; k < n; k++) {
      parts.add(nameAt(b, j + 4 * k));
    }
    return (parts.join('.'), j - i + 4 * n);
  } else if (b[j] == 0x00) {
    return ('<null>', j - i + 1);
  } else {
    return (nameAt(b, j), j - i + 4);
  }
}

void main() {
  final f = File('C:\\Users\\user\\Code\\netturbine\\acpi\\DSDT-00000002-0.bin');
  final b = f.readAsBytesSync();
  final stack = <(int end, String name)>[]; // scope stack
  final watch = RegExp(r'FAN|FST|FSL|FIF|FPS|EC|_TMP|GFRM|SFRM|RFRM|RPM');

  String curPath() =>
      '\\' + stack.map((e) => e.$2.replaceAll('\\\\', '')).where((e) => e.isNotEmpty && e != '\\').join('.');

  for (var i = 36; i < b.length - 8; i++) {
    while (stack.isNotEmpty && i >= stack.last.$1) {
      stack.removeLast();
    }
    // Scope: 10 PkgLen NameString
    if (b[i] == 0x10) {
      final len = pkgLen(b, i + 1);
      final hdr = pkgLenSize(b, i + 1);
      final (n, _) = nameString(b, i + 1 + hdr);
      if (n != '<null>' && n.isNotEmpty) {
        stack.add((i + 1 + len, n));
      }
      i += hdr; // continue inside
      continue;
    }
    // Device: 5B 82 PkgLen NameSeg
    if (b[i] == 0x5B && b[i + 1] == 0x82) {
      final len = pkgLen(b, i + 2);
      final hdr = pkgLenSize(b, i + 2);
      final ns = i + 2 + hdr;
      if (isNameSeg(b, ns)) {
        final n = nameAt(b, ns);
        final path = curPath() + '.' + n;
        if (watch.hasMatch(n) || watch.hasMatch(path)) {
          print('device $path @0x${i.toRadixString(16)}');
        }
        stack.add((i + 2 + len, n));
      }
      i += hdr;
      continue;
    }
    // Method: 14 PkgLen NameSeg Flags — record, don't descend meaningfully
    if (b[i] == 0x14) {
      final len = pkgLen(b, i + 1);
      final hdr = pkgLenSize(b, i + 1);
      final ns = i + 1 + hdr;
      if (isNameSeg(b, ns)) {
        final n = nameAt(b, ns);
        final path = curPath() + '.' + n;
        if (watch.hasMatch(path) ||
            n.startsWith('_Q') ||
            n == 'RBEC' ||
            n == 'WBEC' ||
            n == 'MBEC' ||
            n == 'RDEC' ||
            n == 'WREC' ||
            n == 'MDEC') {
          print('method $path len=$len @0x${i.toRadixString(16)}');
        }
        // Skip method body — no sub-terms we care about at top level
        i = i + 1 + len - 1;
      }
      continue;
    }
    // Name: 08 NameString DataRef — record only
    if (b[i] == 0x08) {
      final (n, consumed) = nameString(b, i + 1);
      if (n != '<null>') {
        final path = curPath() + '.' + n;
        if (watch.hasMatch(path) && n.startsWith('_')) {
          print('name   $path @0x${i.toRadixString(16)}');
        }
      }
      // Name's DataRef can be a package of length N — hard to bound; continue scanning inside
      i += consumed;
      continue;
    }
  }
}
