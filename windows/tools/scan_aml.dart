import 'dart:io';

// Minimal AML scanner: finds Device/Scope/Method/OperationRegion/Field names.

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

void scan(File f) {
  final b = f.readAsBytesSync();
  final out = StringBuffer();
  out.writeln('=== ${f.uri.pathSegments.last} ===');
  final regions = <String, int>{};
  final regionAddr = <String, String>{};
  final fieldNames = <String, List<String>>{};
  final methods = <String>[];
  final devices = <String>[];

  for (var i = 36; i < b.length - 6; i++) {
    // OperationRegion: 5B 80 NameSeg RegionSpace Offset TermArg Len TermArg
    if (b[i] == 0x5B && b[i + 1] == 0x80 && isNameSeg(b, i + 2)) {
      final n = nameAt(b, i + 2);
      regions[n] = b[i + 6];
      // offset termarg: typically ConstOp 0x0A byte / 0x0B word / 0x0C dword / 0x00 zero
      var offStr = '';
      var j = i + 7;
      if (b[j] == 0x0A) {
        offStr = '0x${b[j + 1].toRadixString(16)}';
      } else if (b[j] == 0x0B) {
        offStr =
            '0x${(b[j + 1] | b[j + 2] << 8).toRadixString(16)}';
      } else if (b[j] == 0x00) {
        offStr = '0';
      }
      regionAddr[n] = offStr;
    }
    // Device: 5B 82 PkgLen NameSeg
    if (b[i] == 0x5B && b[i + 1] == 0x82) {
      final ns = i + 2 + pkgLenSize(b, i + 2);
      if (isNameSeg(b, ns)) devices.add(nameAt(b, ns));
    }
    // Method: 14 PkgLen NameSeg flags
    if (b[i] == 0x14) {
      final ns = i + 1 + pkgLenSize(b, i + 1);
      if (isNameSeg(b, ns)) methods.add('${nameAt(b, ns)}@0x${i.toRadixString(16)}');
    }
    // Field: 5B 81 PkgLen RegionName FieldFlags FieldList
    if (b[i] == 0x5B && b[i + 1] == 0x81) {
      final off = i + 2;
      final len = pkgLen(b, off);
      final hdr = pkgLenSize(b, off);
      if (!isNameSeg(b, off + hdr)) continue;
      final region = nameAt(b, off + hdr);
      final end = off + len;
      var j = off + hdr + 4 + 1;
      var bit = 0;
      while (j < end && j < b.length - 4) {
        if (b[j] == 0x00) {
          bit += pkgLen(b, j + 1);
          j += 1 + pkgLenSize(b, j + 1);
        } else if (b[j] == 0x01) {
          j += 3;
        } else if (b[j] == 0x02) {
          j += 2;
        } else if (b[j] == 0x03) {
          j += 4;
        } else if (isNameSeg(b, j)) {
          final n = nameAt(b, j);
          final bl = pkgLen(b, j + 4);
          fieldNames.putIfAbsent(region, () => []).add('$n:b$bit+${bl}b');
          bit += bl;
          j += 4 + pkgLenSize(b, j + 4);
        } else {
          break;
        }
      }
    }
  }

  out.writeln('devices: ${devices.join(' ')}');
  out.writeln('regions:');
  regions.forEach((n, s) => out.writeln(
      '  $n space=0x${s.toRadixString(16)} addr=${regionAddr[n] ?? '?'}'));
  fieldNames.forEach((r, fields) {
    out.writeln('fields[$r]: ${fields.join(' ')}');
  });
  out.writeln('methods: ${methods.join(' ')}');
  stdout.write(out);
}

void main(List<String> args) {
  final f = File(args[0]);
  scan(f);
}
