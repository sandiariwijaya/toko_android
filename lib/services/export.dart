import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../config.dart';
import '../db/database.dart';
import '../models.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import 'native.dart';
import 'printer.dart' show TextFmt;
import 'xlsx.dart';

const String kPdfMime = 'application/pdf';
const String kXlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Simpan file ke Download/AplikasiToko/<sub> lalu buka / bagikan
class FileOut {
  static String safe(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');

  static Future<void> saveAndOpen(Uint8List bytes, String name, String mime, {String sub = 'Laporan', bool open = true}) async {
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes(bytes, flush: true);
    final folder = '${AppConfig.folder}/$sub';
    final sdk = await Native.sdkInt();
    if (sdk >= 29) {
      if (open) {
        final opened = await Native.openFile(f.path, name, folder: folder, mime: mime);
        if (opened) {
          Notify.success('Tersimpan di Download/$folder');
          return;
        }
        Notify.warning('Tidak ada aplikasi pembuka file ini. Pilih aplikasi untuk membuka/berbagi.');
      } else {
        try {
          final saved = await Native.saveToDownloads(f.path, name, folder: folder, mime: mime);
          if (saved != null) {
            Notify.success('Tersimpan di Download/$folder');
            return;
          }
        } catch (_) {}
      }
    } else {
      try {
        var allowed = true;
        if (sdk > 0) allowed = (await Permission.storage.request()).isGranted;
        if (allowed) {
          final saved = await Native.saveToDownloads(f.path, name, folder: folder, mime: mime);
          if (saved != null) Notify.success('Tersimpan di Download/$folder');
        }
      } catch (_) {}
    }
    await Share.shareXFiles([XFile(f.path, mimeType: mime, name: name)], subject: name);
  }
}

class _Pdf {
  final AppState app;
  final PdfColor primary;
  _Pdf(this.app) : primary = PdfColor.fromInt(app.seedColor.value);

  static String a(String s) => TextFmt.ascii(s);

  pw.Widget table(List<String> headers, List<List<String>> rows, {Set<int> right = const {}, List<double>? flex}) {
    final align = <int, pw.Alignment>{
      for (var i = 0; i < headers.length; i++) i: right.contains(i) ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
    };
    return pw.TableHelper.fromTextArray(
      headers: headers.map(a).toList(),
      data: rows.map((r) => r.map(a).toList()).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
      headerDecoration: pw.BoxDecoration(color: primary),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      cellHeight: 16,
      cellAlignments: align,
      headerAlignments: align,
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      columnWidths: flex == null ? null : {for (var i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i])},
    );
  }

  pw.Widget title(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(a(t), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: primary)),
      );

  pw.Widget box(String label, String value) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.all(3),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(a(label), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 3),
            pw.Text(a(value), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
      );

  pw.Widget header(String reportTitle, String period) {
    final name = a(app.get('store_name'));
    final addr = a(app.get('store_address'));
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(name, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            if (addr.isNotEmpty) pw.Text(addr, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(a(reportTitle), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: primary)),
          pw.Text(a(period), style: const pw.TextStyle(fontSize: 9)),
        ]),
      ]),
      pw.Divider(color: primary, thickness: 1.5),
    ]);
  }

  pw.Widget footer(pw.Context c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(a('Dicetak ${fmtDateTime(DateTime.now())} oleh ${app.userName}'), style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
        pw.Text('Hal ${c.pageNumber}/${c.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
      ]);

  Future<Uint8List> doc(String reportTitle, String period, List<pw.Widget> body, {bool landscape = false}) {
    final d = pw.Document(title: reportTitle, author: a(app.get('store_name')));
    d.addPage(pw.MultiPage(
      pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 24),
      header: (c) => c.pageNumber == 1 ? header(reportTitle, period) : pw.SizedBox(),
      footer: footer,
      build: (c) => body,
    ));
    return d.save();
  }
}

/// Export laporan ke PDF & Excel
class ReportExport {
  static String period(DateTime from, DateTime to) =>
      dbDay(from) == dbDay(to) ? fmtDayName(from) : '${fmtDate(from)} s/d ${fmtDate(to)}';

  static String _periodFile(DateTime from, DateTime to) =>
      dbDay(from) == dbDay(to) ? dbDay(from) : '${dbDay(from)}_sd_${dbDay(to)}';

  // ------------------------------------------------------------------ PENJUALAN
  static Future<void> sales(AppState app, DateTime from, DateTime to, {required bool pdf}) async {
    try {
      Notify.info('Menyiapkan file ${pdf ? 'PDF' : 'Excel'}...');
      final d = await Repo.report(from, to);
      final list = await Repo.sales(from, to, withItems: true);
      final ex = await Repo.expenses(from, to);
      final profit = app.isOwner;
      final bytes = pdf ? await _salesPdf(app, d, list, ex, profit) : _salesXlsx(app, d, list, ex, profit);
      final name = 'Laporan_Penjualan_${_periodFile(from, to)}.${pdf ? 'pdf' : 'xlsx'}';
      await Activity.log('data', 'Export laporan penjualan ${pdf ? 'PDF' : 'Excel'}', period(from, to));
      await FileOut.saveAndOpen(bytes, name, pdf ? kPdfMime : kXlsxMime);
    } catch (e) {
      Notify.error('Gagal export: $e');
    }
  }

  static Future<Uint8List> _salesPdf(AppState app, ReportData d, List<Sale> sales, List<Expense> ex, bool profit) {
    final x = _Pdf(app);
    final ok = sales.where((s) => !s.isVoid).toList();
    final body = <pw.Widget>[
      pw.Row(children: [
        x.box('Total Penjualan', rp(d.total)),
        x.box('Transaksi', nf(d.trxCount)),
        x.box('Item Terjual', fq(d.itemsSold)),
        x.box('Rata-rata', rp(d.average)),
      ]),
      if (profit)
        pw.Row(children: [
          x.box('Modal (HPP)', rp(d.hpp)),
          x.box('Laba Kotor', rp(d.grossProfit)),
          x.box('Pengeluaran', rp(d.expense)),
          x.box(d.net >= 0 ? 'Laba Bersih' : 'Rugi Bersih', rp(d.net)),
        ]),
      x.title('Ringkasan per Metode Bayar'),
      x.table(['Metode', 'Transaksi', 'Total'], [for (final m in d.byMethod) [m.name, nf(m.count), nf(m.total)]], right: {1, 2}),
      x.title('Ringkasan per Kasir'),
      x.table(['Kasir', 'Transaksi', 'Total'], [for (final m in d.byCashier) [m.name, nf(m.count), nf(m.total)]], right: {1, 2}),
      x.title('Penjualan Harian'),
      x.table(['Tanggal', 'Transaksi', 'Total'], [for (final e in d.daily) if (e.count > 0) [fmtDate(e.day), nf(e.count), nf(e.total)]], right: {1, 2}),
      x.title('Daftar Transaksi'),
      x.table(
        ['No Nota', 'Tanggal', 'Kasir', 'Metode', 'Diskon', 'Total', 'Status'],
        [
          for (final s in sales)
            [s.invoiceNo, '${fmtDateShort(s.createdAt)} ${fmtTime(s.createdAt)}', s.userName, s.method, nf(s.discount), nf(s.total), s.isVoid ? 'BATAL' : 'OK']
        ],
        right: {4, 5},
        flex: [2.2, 2, 1.6, 1.3, 1.2, 1.5, 1],
      ),
      x.title('Barang Terjual'),
      x.table(['No', 'Barang', 'Qty', 'Total'], [
        for (var i = 0; i < d.topItems.length; i++) ['${i + 1}', d.topItems[i].name, fq(d.topItems[i].qty), nf(d.topItems[i].total)]
      ], right: {2, 3}, flex: [0.6, 5, 1.2, 1.6]),
      if (ex.isNotEmpty) ...[
        x.title('Pengeluaran'),
        x.table(['Tanggal', 'Kategori', 'Keterangan', 'Nominal'], [for (final e in ex) [fmtDateShort(e.date), e.category, e.note, nf(e.amount)]],
            right: {3}, flex: [1.4, 2, 4, 1.6]),
      ],
      pw.SizedBox(height: 8),
      pw.Text(_Pdf.a('Jumlah nota: ${ok.length} sah, ${sales.length - ok.length} batal'), style: const pw.TextStyle(fontSize: 8)),
    ];
    return x.doc('LAPORAN PENJUALAN', period(d.from, d.to), body);
  }

  static Uint8List _salesXlsx(AppState app, ReportData d, List<Sale> sales, List<Expense> ex, bool profit) {
    final wb = XlsxBuilder();
    final s1 = wb.sheet('Ringkasan', [32, 20]);
    s1.row([XC.title('LAPORAN PENJUALAN - ${app.get('store_name')}')]);
    s1.row([XC.text('Periode'), XC.text(period(d.from, d.to))]);
    s1.row([]);
    s1.row([XC.header('Keterangan'), XC.header('Nilai')]);
    s1.row([XC.text('Jumlah transaksi'), XC.number(d.trxCount)]);
    s1.row([XC.text('Item terjual'), XC.number(d.itemsSold)]);
    s1.row([XC.text('Penjualan kotor'), XC.number(d.gross)]);
    s1.row([XC.text('Diskon'), XC.number(d.discount)]);
    s1.row([XC.bold('TOTAL PENJUALAN'), XC.numberBold(d.total)]);
    s1.row([XC.text('Rata-rata per transaksi'), XC.number(d.average)]);
    s1.row([XC.text('Transaksi dibatalkan'), XC.number(d.voidCount)]);
    if (profit) {
      s1.row([XC.text('Modal (HPP)'), XC.number(d.hpp)]);
      s1.row([XC.bold('Laba kotor'), XC.numberBold(d.grossProfit)]);
      s1.row([XC.text('Pengeluaran'), XC.number(d.expense)]);
      s1.row([XC.bold(d.net >= 0 ? 'LABA BERSIH' : 'RUGI BERSIH'), XC.numberBold(d.net)]);
    }
    s1.row([XC.text('Pembelian barang'), XC.number(d.purchase)]);
    s1.row([]);
    s1.row([XC.header('Metode Bayar'), XC.header('Total')]);
    for (final m in d.byMethod) {
      s1.row([XC.text('${m.name} (${m.count} trx)'), XC.number(m.total)]);
    }
    s1.row([]);
    s1.row([XC.header('Kasir'), XC.header('Total')]);
    for (final m in d.byCashier) {
      s1.row([XC.text('${m.name} (${m.count} trx)'), XC.number(m.total)]);
    }

    final s2 = wb.sheet('Transaksi', [20, 12, 8, 16, 18, 12, 13, 12, 14, 12, 10, 24]);
    s2.row([
      for (final h in ['No Nota', 'Tanggal', 'Jam', 'Kasir', 'Pelanggan', 'Metode', 'Subtotal', 'Diskon', 'Total', 'Bayar', 'Status', 'Keterangan'])
        XC.header(h)
    ]);
    for (final s in sales) {
      s2.row([
        XC.text(s.invoiceNo),
        XC.text(dbDay(s.createdAt)),
        XC.text(fmtTime(s.createdAt)),
        XC.text(s.userName),
        XC.text(s.customer),
        XC.text(s.method),
        XC.number(s.subtotal),
        XC.number(s.discount),
        XC.number(s.total),
        XC.number(s.paid),
        XC.text(s.isVoid ? 'BATAL' : 'OK'),
        XC.text(s.isVoid ? s.voidReason : s.note),
      ]);
    }

    final s3 = wb.sheet('Detail Item', profit ? [20, 12, 16, 32, 8, 8, 12, 12, 13, 13] : [20, 12, 16, 32, 8, 8, 12, 12, 13]);
    s3.row([
      for (final h in ['No Nota', 'Tanggal', 'Barcode', 'Barang', 'Qty', 'Satuan', 'Harga', 'Diskon', 'Subtotal', if (profit) 'Laba'])
        XC.header(h)
    ]);
    for (final s in sales.where((e) => !e.isVoid)) {
      for (final it in s.items) {
        s3.row([
          XC.text(s.invoiceNo),
          XC.text(dbDay(s.createdAt)),
          XC.text(it.barcode),
          XC.text(it.name),
          XC.number(it.qty),
          XC.text(it.unit),
          XC.number(it.price),
          XC.number(it.discount),
          XC.number(it.subtotal),
          if (profit) XC.number(it.subtotal - (it.buyPrice * it.qty).round()),
        ]);
      }
    }

    final s4 = wb.sheet('Barang Terjual', [6, 36, 10, 15]);
    s4.row([for (final h in ['No', 'Barang', 'Qty', 'Total']) XC.header(h)]);
    for (var i = 0; i < d.topItems.length; i++) {
      final t = d.topItems[i];
      s4.row([XC.number(i + 1), XC.text(t.name), XC.number(t.qty), XC.number(t.total)]);
    }

    final s5 = wb.sheet('Harian', [14, 12, 15]);
    s5.row([for (final h in ['Tanggal', 'Transaksi', 'Total']) XC.header(h)]);
    for (final e in d.daily) {
      s5.row([XC.text(dbDay(e.day)), XC.number(e.count), XC.number(e.total)]);
    }

    if (ex.isNotEmpty) {
      final s6 = wb.sheet('Pengeluaran', [12, 20, 36, 15, 16]);
      s6.row([for (final h in ['Tanggal', 'Kategori', 'Keterangan', 'Nominal', 'Dicatat oleh']) XC.header(h)]);
      for (final e in ex) {
        s6.row([XC.text(dbDay(e.date)), XC.text(e.category), XC.text(e.note), XC.number(e.amount), XC.text(e.userName)]);
      }
      s6.row([XC.bold('TOTAL'), XC.empty, XC.empty, XC.numberBold(ex.fold<int>(0, (a, e) => a + e.amount))]);
    }
    return wb.build();
  }

  // ------------------------------------------------------------------ PEMBELIAN
  static Future<void> purchases(AppState app, DateTime from, DateTime to, {required bool pdf}) async {
    try {
      Notify.info('Menyiapkan file ${pdf ? 'PDF' : 'Excel'}...');
      final list = await Repo.purchases(from, to, withItems: true);
      final ok = list.where((e) => !e.isVoid).toList();
      final total = ok.fold<int>(0, (a, e) => a + e.total);
      Uint8List bytes;
      if (pdf) {
        final x = _Pdf(app);
        bytes = await x.doc('LAPORAN PEMBELIAN', period(from, to), [
          pw.Row(children: [x.box('Total Pembelian', rp(total)), x.box('Jumlah Nota', nf(ok.length))]),
          x.title('Daftar Pembelian'),
          x.table(['No', 'Tanggal', 'Supplier', 'No Faktur', 'Total', 'Status'], [
            for (final pb in list)
              [pb.invoiceNo, fmtDateShort(pb.createdAt), pb.supplierName, pb.refNo, nf(pb.total), pb.isVoid ? 'BATAL' : 'OK']
          ], right: {4}, flex: [2, 1.4, 2.4, 1.6, 1.5, 1]),
          x.title('Detail Barang Masuk'),
          x.table(['No', 'Barang', 'Qty', 'Harga Beli', 'Subtotal'], [
            for (final pb in ok)
              for (final it in pb.items) [pb.invoiceNo, it.name, fq(it.qty), nf(it.buyPrice), nf(it.subtotal)]
          ], right: {2, 3, 4}, flex: [2, 4, 1, 1.5, 1.6]),
        ]);
      } else {
        final wb = XlsxBuilder();
        final s1 = wb.sheet('Pembelian', [20, 12, 24, 16, 14, 10, 16, 24]);
        s1.row([for (final h in ['No', 'Tanggal', 'Supplier', 'No Faktur', 'Total', 'Status', 'Dicatat oleh', 'Catatan']) XC.header(h)]);
        for (final pb in list) {
          s1.row([
            XC.text(pb.invoiceNo),
            XC.text(dbDay(pb.createdAt)),
            XC.text(pb.supplierName),
            XC.text(pb.refNo),
            XC.number(pb.total),
            XC.text(pb.isVoid ? 'BATAL' : 'OK'),
            XC.text(pb.userName),
            XC.text(pb.isVoid ? pb.voidReason : pb.note),
          ]);
        }
        s1.row([XC.bold('TOTAL'), XC.empty, XC.empty, XC.empty, XC.numberBold(total)]);
        final s2 = wb.sheet('Detail', [20, 12, 34, 8, 8, 14, 14]);
        s2.row([for (final h in ['No', 'Tanggal', 'Barang', 'Qty', 'Satuan', 'Harga Beli', 'Subtotal']) XC.header(h)]);
        for (final pb in ok) {
          for (final it in pb.items) {
            s2.row([XC.text(pb.invoiceNo), XC.text(dbDay(pb.createdAt)), XC.text(it.name), XC.number(it.qty), XC.text(it.unit), XC.number(it.buyPrice), XC.number(it.subtotal)]);
          }
        }
        bytes = wb.build();
      }
      await Activity.log('data', 'Export laporan pembelian ${pdf ? 'PDF' : 'Excel'}', period(from, to));
      await FileOut.saveAndOpen(bytes, 'Laporan_Pembelian_${_periodFile(from, to)}.${pdf ? 'pdf' : 'xlsx'}', pdf ? kPdfMime : kXlsxMime);
    } catch (e) {
      Notify.error('Gagal export: $e');
    }
  }

  // ------------------------------------------------------------------ STOK
  static Future<void> stock(AppState app, {required bool pdf, bool onlyLow = false}) async {
    try {
      Notify.info('Menyiapkan file ${pdf ? 'PDF' : 'Excel'}...');
      final list = await Repo.products(onlyLow: onlyLow, order: onlyLow ? 'stock' : 'name');
      final showBuy = app.can('perm_buy_price');
      final sum = await Repo.stockSummary();
      final title = onlyLow ? 'LAPORAN STOK MENIPIS' : 'LAPORAN STOK BARANG';
      final per = fmtDayName(DateTime.now());
      Uint8List bytes;
      if (pdf) {
        final x = _Pdf(app);
        bytes = await x.doc(title, per, [
          pw.Row(children: [
            x.box('Jenis Barang', nf(sum['count'] ?? 0)),
            x.box('Stok Menipis', nf(sum['low'] ?? 0)),
            x.box('Stok Habis', nf(sum['empty'] ?? 0)),
            if (showBuy) x.box('Nilai Stok (modal)', rp(sum['value_buy'] ?? 0)),
            x.box('Nilai Stok (jual)', rp(sum['value_sell'] ?? 0)),
          ]),
          x.title('Daftar Barang'),
          x.table([
            'Barcode', 'Nama Barang', 'Kategori', 'Stok', 'Min', 'Satuan', if (showBuy) 'H. Beli', 'H. Jual'
          ], [
            for (final pr in list)
              [pr.barcode, pr.name, pr.category, fq(pr.stock), fq(pr.minStock), pr.unit, if (showBuy) nf(pr.buyPrice), nf(pr.sellPrice)]
          ], right: showBuy ? {3, 4, 6, 7} : {3, 4, 6}, flex: showBuy ? [2.2, 4, 2, 1, 1, 1, 1.5, 1.5] : [2.2, 4.5, 2, 1, 1, 1, 1.5]),
        ]);
      } else {
        bytes = productsXlsx(list, showBuy: showBuy, title: title);
      }
      await Activity.log('data', 'Export ${onlyLow ? 'stok menipis' : 'stok barang'} ${pdf ? 'PDF' : 'Excel'}');
      await FileOut.saveAndOpen(bytes, '${onlyLow ? 'Stok_Menipis' : 'Stok_Barang'}_${dbDay(DateTime.now())}.${pdf ? 'pdf' : 'xlsx'}',
          pdf ? kPdfMime : kXlsxMime);
    } catch (e) {
      Notify.error('Gagal export: $e');
    }
  }

  /// Format kolom sama dengan template import, jadi file ini bisa diedit lalu di-upload lagi
  static Uint8List productsXlsx(List<Product> list, {bool showBuy = true, String title = ''}) {
    final wb = XlsxBuilder();
    final s = wb.sheet('Data Barang', [18, 36, 18, 10, 14, 14, 10, 12]);
    s.row([for (final h in importHeaders) XC.header(h)]);
    for (final p in list) {
      s.row([
        XC.text(p.barcode),
        XC.text(p.name),
        XC.text(p.category),
        XC.text(p.unit),
        showBuy ? XC.number(p.buyPrice) : XC.empty,
        XC.number(p.sellPrice),
        XC.number(p.stock),
        XC.number(p.minStock),
      ]);
    }
    return wb.build();
  }

  static const List<String> importHeaders = [
    'Barcode',
    'Nama Barang',
    'Kategori',
    'Satuan',
    'Harga Beli',
    'Harga Jual',
    'Stok',
    'Stok Minimum',
  ];

  /// Template kosong untuk diisi lalu di-upload
  static Uint8List templateXlsx() {
    final wb = XlsxBuilder();
    final s = wb.sheet('Data Barang', [18, 36, 18, 10, 14, 14, 10, 12]);
    s.row([for (final h in importHeaders) XC.header(h)]);
    final samples = [
      ['8992388101010', 'Indomie Goreng 85g', 'Makanan', 'pcs', 2800, 3500, 40, 10],
      ['8999999001234', 'Aqua Botol 600ml', 'Minuman', 'btl', 2600, 3500, 24, 6],
      ['', 'Beras Premium 5kg', 'Sembako', 'sak', 68000, 75000, 10, 2],
      ['', 'Gula Pasir', 'Sembako', 'kg', 15500, 17500, 25.5, 5],
    ];
    for (final r in samples) {
      s.row([
        XC.text(r[0] as String),
        XC.text(r[1] as String),
        XC.text(r[2] as String),
        XC.text(r[3] as String),
        XC.number(r[4] as num),
        XC.number(r[5] as num),
        XC.number(r[6] as num),
        XC.number(r[7] as num),
      ]);
    }
    final h = wb.sheet('Petunjuk', [100]);
    for (final t in [
      'PETUNJUK PENGISIAN DATA BARANG',
      '1. Isi data di sheet "Data Barang" mulai baris ke-2 (baris 1 adalah judul kolom, jangan diubah).',
      '2. Hapus contoh data sebelum diisi data asli.',
      '3. Barcode boleh kosong (aplikasi bisa membuatkan barcode otomatis). Tulis barcode sebagai teks agar angka 0 di depan tidak hilang.',
      '4. Nama Barang wajib diisi. Kategori baru otomatis dibuat.',
      '5. Harga Beli & Harga Jual diisi angka saja tanpa Rp dan titik, contoh: 3500',
      '6. Stok boleh desimal (contoh 2,5 untuk kg).',
      '7. Stok Minimum = batas peringatan stok menipis.',
      '8. Barang yang sudah ada (barcode atau nama sama) akan DIPERBARUI, sisanya ditambahkan sebagai barang baru.',
      '9. Simpan sebagai .xlsx lalu upload dari menu Barang > Import Excel.',
    ]) {
      h.row([t.startsWith('PETUNJUK') ? XC.title(t) : XC.text(t)]);
    }
    return wb.build();
  }
}

/// Label barcode untuk kertas A4 (stiker / dipotong manual)
class LabelExport {
  static Future<void> pdf(AppState app, List<MapEntry<Product, int>> items, {int cols = 4}) async {
    try {
      final labels = <Product>[];
      for (final e in items) {
        if (e.key.barcode.trim().isEmpty) continue;
        for (var i = 0; i < e.value; i++) {
          labels.add(e.key);
        }
      }
      if (labels.isEmpty) {
        Notify.warning('Tidak ada barang dengan barcode');
        return;
      }
      final showName = app.b('bc_show_name');
      final showPrice = app.b('bc_show_price');
      final doc = pw.Document(title: 'Label Barcode');
      const margin = 18.0;
      final cellW = (PdfPageFormat.a4.width - margin * 2) / cols;
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(margin),
        build: (c) => [
          pw.Wrap(
            children: [
              for (final p in labels)
                pw.Container(
                  width: cellW,
                  height: 82,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.4)),
                  child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
                    if (showName)
                      pw.Text(TextFmt.ascii(p.name),
                          maxLines: 1, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 2),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.code128(),
                      data: p.barcode.trim(),
                      width: cellW - 18,
                      height: 38,
                      textStyle: const pw.TextStyle(fontSize: 7),
                    ),
                    if (showPrice) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(TextFmt.ascii(rp(p.sellPrice)), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ],
                  ]),
                ),
            ],
          ),
        ],
      ));
      final bytes = await doc.save();
      await Activity.log('barang', 'Cetak label barcode (PDF)', '${labels.length} label');
      await FileOut.saveAndOpen(bytes, 'Label_Barcode_${dbDay(DateTime.now())}.pdf', kPdfMime, sub: 'Barcode');
    } catch (e) {
      Notify.error('Gagal membuat PDF label: $e');
    }
  }
}
