# Kasir Rumah Makan (Android – Flutter)

Aplikasi kasir offline untuk rumah makan. Nyaman di HP maupun tablet, printer thermal Bluetooth 58mm/80mm.

## Aktivasi & login pertama
Setelah install, aplikasi meminta **kode aktivasi** (hanya diketahui pembuat aplikasi).
Setelah aktif, login pertama memakai akun awal owner (lihat catatan pembuat), lalu segera ganti password di **Pengaturan > Ganti Password**.

## Cara build APK

### Cara 1 – di komputer (Flutter sudah terpasang, versi 3.24 ke atas)
1. Ekstrak zip ke folder, mis. `C:\kasir_rumah_makan`
2. Windows: klik 2x `build_apk.bat` (Linux/Mac: `./build_apk.sh`)
3. APK jadi di `build/app/outputs/flutter-apk/app-release.apk`

Isi script (bisa diketik manual):
```
flutter create --org com.sandi --project-name kasir_rumah_makan --platforms android .
flutter pub get
flutter build apk --release
```
> `flutter create .` hanya melengkapi file Android yang belum ada (gradle, icon, dll). File `AndroidManifest.xml` dan `MainActivity.kt` dari zip tidak ditimpa.

### Cara 2 – tanpa install Flutter (GitHub Actions, gratis)
1. Buat repository baru di GitHub, upload semua isi zip (termasuk folder `.github`).
2. Buka tab **Actions** → workflow **Build APK** berjalan otomatis (±8 menit).
3. Setelah selesai, unduh APK di bagian **Artifacts**.

## Fitur
- **Penjualan** (bawa pulang, tanpa meja): grid gambar menu, kategori, cari, tap = tambah, keranjang samping (tablet) / bar bawah (HP), catatan per item, diskon Rp/%, pajak & service, simpan pesanan sementara atas nama pelanggan.
- **Pembayaran**: Tunai (tombol uang pas & nominal cepat, kembalian otomatis), QRIS (gambar QRIS ditampilkan ke pelanggan), Transfer, Debit, E-Wallet – bisa tambah sendiri.
- **Menu**: tambah/ubah dengan foto (kamera/galeri), harga, kategori, tandai habis.
- **Pengeluaran**: catat per kategori, tunai/non tunai.
- **Laporan**: ringkasan, grafik harian, per metode bayar & per kasir, transaksi (cetak ulang; **hapus hanya owner**), menu terlaris, pengeluaran.
  - **Cetak Laporan Harian** ke printer thermal (ringkasan, atau + daftar transaksi).
  - **Export PDF & Excel (.xlsx)** – tersimpan di `Download/KasirRumahMakan/Laporan/` dan bisa langsung dibagikan (WA, Drive, dll).
- **Laba Rugi**: pendapatan bersih − HPP (kategori pengeluaran bahan baku) − beban operasional = laba bersih; tampil di layar, cetak struk, PDF & Excel.
- **Log Aktivitas** (owner): login/logout, transaksi baru, hapus transaksi (beserta alasan & isi nota), cetak ulang, perubahan menu/harga, pengeluaran, pengguna, pengaturan, backup/restore, export.
- **Pengaturan**: profil & logo toko, isi struk + pratinjau, pajak/service, pembayaran & QRIS, printer, tampilan (Otomatis/HP/Tablet, orientasi, warna tema, mode gelap, ukuran teks & kartu), pengguna owner/kasir + hak akses kasir, backup & restore.
- **Backup otomatis tiap login**, 3 file berputar: `backup_kasir_rm_1.db` → `_2` → `_3` → kembali ke `_1` (ditimpa). Lokasi: `Download/KasirRumahMakan/`. Restore dari file untuk pindah HP.

## Printer thermal Bluetooth 58mm
1. Pair printer dulu di Pengaturan Bluetooth HP (PIN umumnya `0000` atau `1234`).
2. Aplikasi: **Pengaturan > Printer Bluetooth > Pilih Printer**, lalu **Tes Cetak**.
3. Layout struk tetap untuk kertas 58mm (32 karakter per baris, 384 dot).

## Struktur kode
```
lib/
  main.dart                 tema & start aplikasi
  app_state.dart            pengaturan + user login
  cart_state.dart           keranjang & hitung total
  models.dart
  db/database.dart          SQLite (sqflite) + query
  services/printer.dart     ESC/POS, struk, logo raster
  services/native.dart      jembatan ke Kotlin (Bluetooth klasik SPP)
  services/backup.dart      backup berputar & restore
  screens/…                 login, penjualan, bayar, menu, pengeluaran, laporan, pengaturan
android/app/src/main/kotlin/com/sandi/kasir_rumah_makan/MainActivity.kt
```
