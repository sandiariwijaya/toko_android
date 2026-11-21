import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ======================= PENULIS XLSX SEDERHANA =======================
/// Sel Excel. style: 0 normal, 1 header, 2 angka, 3 angka tebal, 4 judul, 5 teks tebal
class XC {
  final Object? value;
  final int style;
  const XC(this.value, this.style);

  static const XC empty = XC(null, 0);
  static XC text(String v) => XC(v, 0);
  static XC header(String v) => XC(v, 1);
  static XC number(num v) => XC(v, 2);
  static XC numberBold(num v) => XC(v, 3);
  static XC title(String v) => XC(v, 4);
  static XC bold(String v) => XC(v, 5);
}

class XlsxSheet {
  final String name;
  final List<double> widths;
  final List<List<XC>> rows = [];
  XlsxSheet(this.name, this.widths);

  void row(List<XC> cells) => rows.add(cells);
}

class XlsxBuilder {
  static const String _head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
  static const String _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  static const String _rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  static const String _pkgRel = 'http://schemas.openxmlformats.org/package/2006/relationships';
  static const String _styles = '$_head<styleSheet xmlns="$_ns">'
      '<fonts count="3"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="14"/><name val="Calibri"/></font></fonts>'
      '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFD9EAD3"/><bgColor indexed="64"/></patternFill></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="6">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
      '<xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '<xf numFmtId="3" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>'
      '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';

  final List<XlsxSheet> _sheets = [];

  XlsxSheet sheet(String name, List<double> widths) {
    var n = name.replaceAll(RegExp(r'[\[\]\*\?/\\:]'), ' ');
    if (n.length > 31) n = n.substring(0, 31);
    final s = XlsxSheet(n, widths);
    _sheets.add(s);
    return s;
  }

  static String _esc(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r < 0x20 && r != 9 && r != 10 && r != 13) continue;
      switch (r) {
        case 38:
          b.write('&amp;');
          break;
        case 60:
          b.write('&lt;');
          break;
        case 62:
          b.write('&gt;');
          break;
        case 34:
          b.write('&quot;');
          break;
        default:
          b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  static String _col(int i) {
    var n = i + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  String _sheetXml(XlsxSheet sh) {
    final b = StringBuffer('$_head<worksheet xmlns="$_ns">');
    if (sh.widths.isNotEmpty) {
      b.write('<cols>');
      for (var i = 0; i < sh.widths.length; i++) {
        b.write('<col min="${i + 1}" max="${i + 1}" width="${sh.widths[i]}" customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (var r = 0; r < sh.rows.length; r++) {
      b.write('<row r="${r + 1}">');
      final row = sh.rows[r];
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        final v = cell.value;
        if (v == null) continue;
        final ref = '${_col(c)}${r + 1}';
        if (v is num) {
          b.write('<c r="$ref" s="${cell.style}"><v>$v</v></c>');
        } else {
          b.write('<c r="$ref" s="${cell.style}" t="inlineStr"><is><t xml:space="preserve">${_esc(v.toString())}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }

  Uint8List build() {
    final n = _sheets.length;
    final ct = StringBuffer('$_head<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
    for (var i = 0; i < n; i++) {
      ct.write('<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
    }
    ct.write('</Types>');

    final wbx = StringBuffer('$_head<workbook xmlns="$_ns" xmlns:r="$_rel"><sheets>');
    for (var i = 0; i < n; i++) {
      wbx.write('<sheet name="${_esc(_sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
    }
    wbx.write('</sheets></workbook>');

    final rels = StringBuffer('$_head<Relationships xmlns="$_pkgRel">');
    for (var i = 0; i < n; i++) {
      rels.write('<Relationship Id="rId${i + 1}" Type="$_rel/worksheet" Target="worksheets/sheet${i + 1}.xml"/>');
    }
    rels.write('<Relationship Id="rId${n + 1}" Type="$_rel/styles" Target="styles.xml"/></Relationships>');

    final zip = _StoredZip();
    zip.add('[Content_Types].xml', ct.toString());
    zip.add('_rels/.rels',
        '$_head<Relationships xmlns="$_pkgRel"><Relationship Id="rId1" Type="$_rel/officeDocument" Target="xl/workbook.xml"/></Relationships>');
    zip.add('xl/workbook.xml', wbx.toString());
    zip.add('xl/_rels/workbook.xml.rels', rels.toString());
    zip.add('xl/styles.xml', _styles);
    for (var i = 0; i < n; i++) {
      zip.add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(_sheets[i]));
    }
    return zip.build();
  }
}

/// Zip tanpa kompresi (stored) - cukup untuk file XLSX
class _StoredZip {
  final List<MapEntry<String, Uint8List>> _files = [];

  void add(String name, String content) => _files.add(MapEntry(name, Uint8List.fromList(utf8.encode(content))));

  static final List<int> _table = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    return c;
  });

  static int _crc32(Uint8List data) {
    var c = 0xFFFFFFFF;
    for (final b in data) {
      c = _table[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  Uint8List build() {
    final out = BytesBuilder();
    final central = BytesBuilder();
    var offset = 0;
    for (final f in _files) {
      final name = utf8.encode(f.key);
      final data = f.value;
      final crc = _crc32(data);

      final local = ByteData(30)
        ..setUint32(0, 0x04034b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, 0x0800, Endian.little)
        ..setUint16(8, 0, Endian.little)
        ..setUint16(10, 0, Endian.little)
        ..setUint16(12, 33, Endian.little)
        ..setUint32(14, crc, Endian.little)
        ..setUint32(18, data.length, Endian.little)
        ..setUint32(22, data.length, Endian.little)
        ..setUint16(26, name.length, Endian.little)
        ..setUint16(28, 0, Endian.little);
      out.add(local.buffer.asUint8List());
      out.add(name);
      out.add(data);

      final cd = ByteData(46)
        ..setUint32(0, 0x02014b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, 20, Endian.little)
        ..setUint16(8, 0x0800, Endian.little)
        ..setUint16(10, 0, Endian.little)
        ..setUint16(12, 0, Endian.little)
        ..setUint16(14, 33, Endian.little)
        ..setUint32(16, crc, Endian.little)
        ..setUint32(20, data.length, Endian.little)
        ..setUint32(24, data.length, Endian.little)
        ..setUint16(28, name.length, Endian.little)
        ..setUint16(30, 0, Endian.little)
        ..setUint16(32, 0, Endian.little)
        ..setUint16(34, 0, Endian.little)
        ..setUint16(36, 0, Endian.little)
        ..setUint32(38, 0, Endian.little)
        ..setUint32(42, offset, Endian.little);
      central.add(cd.buffer.asUint8List());
      central.add(name);
      offset += 30 + name.length + data.length;
    }
    final cdBytes = central.toBytes();
    final end = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(4, 0, Endian.little)
      ..setUint16(6, 0, Endian.little)
      ..setUint16(8, _files.length, Endian.little)
      ..setUint16(10, _files.length, Endian.little)
      ..setUint32(12, cdBytes.length, Endian.little)
      ..setUint32(16, offset, Endian.little)
      ..setUint16(20, 0, Endian.little);
    out.add(cdBytes);
    out.add(end.buffer.asUint8List());
    return out.toBytes();
  }
}

// ======================= PEMBACA XLSX SEDERHANA =======================
/// Membaca isi sheet .xlsx menjadi daftar baris (List<String>).
/// Mendukung file dari Microsoft Excel, WPS, Google Sheets & LibreOffice.
class XlsxReader {
  final Map<String, Uint8List> _files = {};

  XlsxReader(Uint8List bytes) {
    _unzip(bytes);
  }

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  static int _u32(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  void _unzip(Uint8List b) {
    // cari End Of Central Directory
    var eocd = -1;
    for (var i = b.length - 22; i >= 0 && i >= b.length - 70000; i--) {
      if (b[i] == 0x50 && b[i + 1] == 0x4b && b[i + 2] == 0x05 && b[i + 3] == 0x06) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw const FormatException('Bukan file Excel (.xlsx) yang valid');
    final count = _u16(b, eocd + 10);
    var off = _u32(b, eocd + 16);
    for (var n = 0; n < count; n++) {
      if (_u32(b, off) != 0x02014b50) break;
      final method = _u16(b, off + 10);
      final compSize = _u32(b, off + 20);
      final nameLen = _u16(b, off + 28);
      final extraLen = _u16(b, off + 30);
      final commentLen = _u16(b, off + 32);
      final localOff = _u32(b, off + 42);
      final name = utf8.decode(b.sublist(off + 46, off + 46 + nameLen), allowMalformed: true);
      off += 46 + nameLen + extraLen + commentLen;
      if (!name.endsWith('.xml') && !name.endsWith('.rels')) continue;
      final lNameLen = _u16(b, localOff + 26);
      final lExtraLen = _u16(b, localOff + 28);
      final start = localOff + 30 + lNameLen + lExtraLen;
      final data = b.sublist(start, start + compSize);
      Uint8List out;
      if (method == 0) {
        out = data;
      } else if (method == 8) {
        out = Uint8List.fromList(ZLibDecoder(raw: true).convert(data));
      } else {
        continue;
      }
      _files[name] = out;
    }
  }

  String? _text(String name) {
    final d = _files[name];
    if (d == null) return null;
    return utf8.decode(d, allowMalformed: true);
  }

  static String unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAllMapped(RegExp(r'&#(x?[0-9a-fA-F]+);'), (m) {
        final v = m.group(1)!;
        final code = v.startsWith('x') ? int.tryParse(v.substring(1), radix: 16) : int.tryParse(v);
        return code == null ? '' : String.fromCharCode(code);
      })
      .replaceAll('&amp;', '&');

  static final RegExp _tRe = RegExp(r'<(?:\w+:)?t(?:\s[^>]*)?>(.*?)</(?:\w+:)?t>', dotAll: true);

  static String _joinT(String xml) {
    final b = StringBuffer();
    for (final m in _tRe.allMatches(xml)) {
      b.write(m.group(1));
    }
    return unescape(b.toString());
  }

  List<String> _sharedStrings() {
    final x = _text('xl/sharedStrings.xml');
    if (x == null) return const [];
    final re = RegExp(r'<(?:\w+:)?si\b[^>]*?(?:/>|>(.*?)</(?:\w+:)?si>)', dotAll: true);
    return re.allMatches(x).map((m) => _joinT(m.group(1) ?? '')).toList();
  }

  /// Daftar nama sheet beserta path file xml-nya
  Map<String, String> sheets() {
    final res = <String, String>{};
    final wb = _text('xl/workbook.xml') ?? '';
    final rels = _text('xl/_rels/workbook.xml.rels') ?? '';
    final relMap = <String, String>{};
    for (final m in RegExp(r'<Relationship\b([^>]*)/?>').allMatches(rels)) {
      final a = m.group(1)!;
      final id = RegExp(r'\bId="([^"]*)"').firstMatch(a)?.group(1);
      var target = RegExp(r'\bTarget="([^"]*)"').firstMatch(a)?.group(1);
      if (id == null || target == null) continue;
      if (target.startsWith('/')) {
        target = target.substring(1);
      } else {
        target = 'xl/$target';
      }
      relMap[id] = target;
    }
    for (final m in RegExp(r'<(?:\w+:)?sheet\b([^>]*)/?>').allMatches(wb)) {
      final a = m.group(1)!;
      final name = RegExp(r'\bname="([^"]*)"').firstMatch(a)?.group(1);
      final rid = RegExp(r'\br:id="([^"]*)"').firstMatch(a)?.group(1) ?? RegExp(r'\b\w+:id="([^"]*)"').firstMatch(a)?.group(1);
      if (name == null || rid == null) continue;
      final path = relMap[rid];
      if (path != null && _files.containsKey(path)) res[unescape(name)] = path;
    }
    if (res.isEmpty) {
      final keys = _files.keys.where((k) => k.startsWith('xl/worksheets/sheet') && k.endsWith('.xml')).toList()..sort();
      for (var i = 0; i < keys.length; i++) {
        res['Sheet${i + 1}'] = keys[i];
      }
    }
    return res;
  }

  static int _colIndex(String ref) {
    var n = 0;
    for (final c in ref.codeUnits) {
      if (c >= 65 && c <= 90) {
        n = n * 26 + (c - 64);
      } else if (c >= 97 && c <= 122) {
        n = n * 26 + (c - 96);
      } else {
        break;
      }
    }
    return n - 1;
  }

  /// Ambil semua baris dari sheet (nama sheet atau sheet pertama)
  List<List<String>> rows([String? sheetName]) {
    final sh = sheets();
    if (sh.isEmpty) return [];
    String? path;
    if (sheetName != null) {
      for (final e in sh.entries) {
        if (e.key.toLowerCase().trim() == sheetName.toLowerCase().trim()) path = e.value;
      }
    }
    path ??= sh.values.first;
    final x = _text(path) ?? '';
    final ss = _sharedStrings();
    final out = <List<String>>[];
    final rowRe = RegExp(r'<(?:\w+:)?row\b([^>]*?)(?:/>|>(.*?)</(?:\w+:)?row>)', dotAll: true);
    final cellRe = RegExp(r'<(?:\w+:)?c\b([^>]*?)(?:/>|>(.*?)</(?:\w+:)?c>)', dotAll: true);
    final vRe = RegExp(r'<(?:\w+:)?v(?:\s[^>]*)?>(.*?)</(?:\w+:)?v>', dotAll: true);
    var expectRow = 1;
    for (final rm in rowRe.allMatches(x)) {
      final attrs = rm.group(1) ?? '';
      final rNum = int.tryParse(RegExp(r'\br="(\d+)"').firstMatch(attrs)?.group(1) ?? '') ?? expectRow;
      while (expectRow < rNum) {
        out.add(<String>[]);
        expectRow++;
      }
      final row = <String>[];
      final body = rm.group(2) ?? '';
      var nextCol = 0;
      for (final cm in cellRe.allMatches(body)) {
        final ca = cm.group(1) ?? '';
        final ref = RegExp(r'\br="([A-Za-z]+)\d*"').firstMatch(ca)?.group(1);
        final col = ref == null ? nextCol : _colIndex(ref);
        final type = RegExp(r'\bt="([^"]*)"').firstMatch(ca)?.group(1) ?? '';
        final inner = cm.group(2) ?? '';
        String val;
        if (type == 'inlineStr') {
          val = _joinT(inner);
        } else {
          final v = vRe.firstMatch(inner)?.group(1);
          if (v == null) {
            val = '';
          } else if (type == 's') {
            final idx = int.tryParse(v.trim()) ?? -1;
            val = idx >= 0 && idx < ss.length ? ss[idx] : '';
          } else {
            val = unescape(v);
          }
        }
        while (row.length < col) {
          row.add('');
        }
        if (row.length == col) {
          row.add(val);
        } else if (col < row.length) {
          row[col] = val;
        }
        nextCol = col + 1;
      }
      out.add(row);
      expectRow = rNum + 1;
    }
    return out;
  }
}

/// Ubah angka dari Excel (bisa "8.99E+12" atau "15000.0") menjadi teks utuh
String excelWholeText(String s) {
  final t = s.trim();
  if (t.isEmpty) return '';
  if (RegExp(r'^-?\d+(\.\d+)?([eE][+-]?\d+)?$').hasMatch(t) && (t.contains('.') || t.contains('e') || t.contains('E'))) {
    final d = double.tryParse(t);
    if (d != null && d == d.roundToDouble() && d.abs() < 1e18) return d.toStringAsFixed(0);
  }
  return t;
}

/// Angka dari sel Excel: "15000", "15.000", "Rp 15.000", "15000.0", "2,5"
double excelNum(String s) {
  var t = s.trim().replaceAll(RegExp(r'[Rr][Pp]\.?'), '').replaceAll(' ', '');
  if (t.isEmpty) return 0;
  final plain = double.tryParse(t);
  if (plain != null && !t.contains(',')) {
    // "15.000" ditulis sebagai teks gaya Indonesia
    if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t)) return double.parse(t.replaceAll('.', ''));
    return plain;
  }
  t = t.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(t) ?? 0;
}
