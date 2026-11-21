# Aplikasi Toko (Android – Flutter)

Aplikasi kasir & manajemen toko / minimarket: penjualan, pembelian, stok, laporan, scan & cetak barcode, printer thermal Bluetooth, backup otomatis, aktivasi online sekali.

## 1. Aktivasi (model sederhana, sekali online)
- Pasang server dari zip **server_aktivasi_toko** (lihat `BACA_DULU.md`): upload ke hosting, isi `config.php`, buka `admin.php` → tabel dibuat otomatis → buat kode `TOKO-XXXX-XXXX`.
- Di aplikasi, halaman aktivasi: ketik **alamat server** (mis. `domainanda.com/aktivasi-toko`, `/api.php` ditambahkan otomatis) + **kode** → AKTIFKAN.
- Opsional: isi `kAktivasiUrl` di `lib/config.dart` agar alamat terisi otomatis, `kKontakAdmin` untuk nomor WA admin, `kWajibAktivasi = false` untuk uji coba tanpa kode.
- ID perangkat memakai ID Android, jadi install ulang di HP yang sama tidak menghabiskan kuota kode.

## 2. Build APK lewat GitHub Actions (tanpa install Flutter)
1. Buat repository **Private** di GitHub (mis. `toko_android`), upload semua isi zip ini termasuk folder `.github`.
   > Repo harus Private karena berisi kunci tanda tangan APK (`android/keystore/toko.jks`).
2. Buka tab **Actions** → workflow **Build APK** berjalan otomatis (±8–10 menit).
3. Selesai → klik run-nya → bagian **Artifacts** → unduh `aplikasi-toko-apk` (berisi `AplikasiToko.apk`).
4. APK selalu ditandatangani kunci yang sama, jadi update cukup install ulang di atasnya (data tidak hilang).

Build di komputer (Flutter terpasang):
```
flutter create --org com.sandi --project-name aplikasi_toko --platforms android .
python3 tool/patch_android.py
flutter pub get
flutter build apk --release
```

## 3. Alur pertama kali
1. **Aktivasi** (butuh internet sekali) → alamat server + kode dari admin.php.
2. **Pengaturan awal** → isi nama toko & buat akun owner.
3. Isi barang: **Barang › ⋮ › Unduh template Excel** → isi → **Import dari Excel**.
4. Atur printer: **Pengaturan › Printer Thermal** (pair printer dulu di Bluetooth HP).

## Fitur
- **Penjualan**: grid/daftar barang, kategori, cari, scan kamera (scan terus-menerus) atau scanner USB/Bluetooth (ketik + Enter), keranjang samping (tablet) / bawah (HP), ubah jumlah, **ubah harga jual & stok langsung dari halaman penjualan** (tekan lama barang, atau tap barang di keranjang), diskon per barang & per nota, simpan keranjang sementara, bayar Tunai (uang pas & nominal cepat) / QRIS / Transfer / Debit, cetak struk.
- **Pembelian / barang masuk**: scan atau cari barang, jumlah, harga beli (atau isi total → dibagi otomatis), ubah harga jual sekaligus, supplier & no faktur, stok otomatis bertambah, cetak bukti.
- **Barang**: tambah/ubah, kategori, satuan, harga beli/jual + untung, stok minimum, barcode (scan / buat otomatis), nonaktifkan, import/ekspor Excel.
- **Cetak barcode**: label ke printer thermal (CODE128 + nama + harga) atau PDF A4.
- **Stok**: semua stok, stok menipis, riwayat (kartu stok), **stok opname dengan scan**, nilai persediaan, cetak/ekspor stok menipis.
- **Notifikasi stok menipis**: notifikasi HP + pemberitahuan di layar saat stok ≤ stok minimum, ringkasan saat login, badge di menu.
- **Transaksi**: riwayat penjualan & pembelian, detail, cetak ulang, batalkan (khusus owner, stok kembali, wajib alasan).
- **Laporan**: ringkasan, grafik harian, per metode bayar, per kasir, barang terlaris, laba (owner), pengeluaran, pembelian.
  - **Cetak ke printer thermal** (ringkas / + daftar transaksi / + laba rugi).
  - **Ekspor PDF & Excel**: penjualan, pembelian, stok → `Download/AplikasiToko/Laporan/` dan langsung dibuka.
- **Pengeluaran**, **Supplier**.
- **Log Aktivitas (khusus owner)**: login/gagal login, transaksi, batal, ubah harga, ubah stok, barang, pengguna, pengaturan, backup/restore, ekspor. Bisa difilter & diekspor Excel.
- **Pengaturan**: profil toko & struk, **layout HP / Tablet / Otomatis**, orientasi, **warna tema** (10 pilihan + warna bebas), mode gelap, ukuran teks, kolom grid, **pengguna kasir & owner + hak akses kasir**, printer 58/80mm, stok & notifikasi, backup & pulihkan.
- **Backup otomatis** setiap login & logout. Hanya **2 file bergantian** (`backup_toko_1.db` → `backup_toko_2.db` → kembali menimpa `_1`) di `Download/AplikasiToko/Backup/`. Pulihkan dari daftar atau pilih file (pindah HP).

## Struktur
```
lib/config.dart                 alamat server & kunci aktivasi
lib/main.dart                   tema & halaman awal
lib/app_state.dart              pengaturan, user, hak akses
lib/db/database.dart            SQLite + semua query
lib/services/                   printer ESC/POS, backup, export PDF/Excel, import Excel, aktivasi, notifikasi
lib/screens/                    semua halaman
lib/widgets/                    komponen UI, scanner kamera
android/app/src/main/kotlin/... Bluetooth printer, simpan ke Download, notifikasi, ID perangkat
tool/patch_android.py           tanda tangan APK & minSdk (dipakai GitHub Actions)
template_excel/                 draft Excel data barang
```
