import 'dart:io';

void main() {
  final b = File('C:\\Users\\user\\Code\\netturbine\\acpi\\DSDT-00000002-0.bin').readAsBytesSync();
  for (final o in [0x18df4, 0x18e03, 0x18e34, 0x197ec, 0x1981c, 0x1984d, 0x1abab, 0x1ac12, 0x1b303]) {
    final s = b.sublist(o, o + 70).map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
    print('@0x${o.toRadixString(16)}: $s');
    print('');
  }
}
