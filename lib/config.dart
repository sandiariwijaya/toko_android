// =====================================================================
//  PENGATURAN APLIKASI & AKTIVASI (versi sederhana, tanpa tanda tangan digital)
// =====================================================================

/// Alamat api.php BAWAAN (http/https). Boleh dibiarkan: alamat juga bisa diketik
/// manual di halaman aktivasi. Contoh: 'https://domainanda.com/aktivasi-toko/api.php'
const String kAktivasiUrl = 'https://DOMAIN-ANDA.com/aktivasi-toko/api.php';

/// false = aplikasi tidak meminta kode aktivasi (mis. untuk uji coba).
const bool kWajibAktivasi = true;

/// Nomor WhatsApp / kontak admin yang ditampilkan di halaman aktivasi (boleh kosong).
const String kKontakAdmin = '';

class AppConfig {
  static const String appName = 'Aplikasi Toko';

  /// Nama folder di penyimpanan HP (Download/<folder>)
  static const String folder = 'AplikasiToko';
}
