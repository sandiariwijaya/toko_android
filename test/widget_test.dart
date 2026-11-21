import 'package:flutter_test/flutter_test.dart';

import 'package:aplikasi_toko/services/xlsx.dart';
import 'package:aplikasi_toko/utils/format.dart';

void main() {
  test('format rupiah & angka', () {
    expect(nf(15000), '15.000');
    expect(rp(3500), 'Rp3.500');
    expect(parseNum('Rp 12.500'), 12500);
    expect(parseQty('2,5'), 2.5);
  });

  test('angka dari excel', () {
    expect(excelWholeText('8.992388101010E+12'), '8992388101010');
    expect(excelNum('15.000'), 15000);
    expect(excelNum('3500'), 3500);
    expect(excelNum('2,5'), 2.5);
  });

  test('xlsx tulis lalu baca kembali', () {
    final wb = XlsxBuilder();
    final s = wb.sheet('Data Barang', [10, 10]);
    s.row([XC.header('Barcode'), XC.header('Nama Barang')]);
    s.row([XC.text('0899'), XC.text('Teh & Kopi')]);
    s.row([XC.number(12), XC.text('B')]);
    final rows = XlsxReader(wb.build()).rows('Data Barang');
    expect(rows[0], ['Barcode', 'Nama Barang']);
    expect(rows[1], ['0899', 'Teh & Kopi']);
    expect(rows[2][0], '12');
  });
}
