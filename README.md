# Aplikasi Timbangan (Android)

Aplikasi mobile berbasis Flutter yang dirancang untuk kebutuhan penimbangan kelapa sawit di lapangan secara real-time. Aplikasi ini terhubung langsung dengan hardware timbangan berbasis **ESP32** dan dilengkapi dengan sistem aktivasi lisensi berbasis **Hardware ID (Device ID)** secara offline dan permanen.

---

## 🚀 Fitur Utama

- **Integrasi Hardware ESP32:** Komunikasi data timbangan secara real-time dari modul ESP32 ke aplikasi Android.
- **Sistem Lisensi Permanen (Hardware-Bound):** Validasi lisensi aman secara lokal berbasis enkripsi SHA-256 tanpa memerlukan koneksi internet/server eksternal.
- **Pencatatan Transaksi:** Mengelola dan mencatat data berat/timbangan sawit secara akurat.
- **Cetak Resi/Struk:** Dukungan cetak nota transaksi menggunakan printer thermal Bluetooth.
- **Penyimpanan Lokal:** Menggunakan SQLite (`sqflite`) untuk penyimpanan data transaksi dan lisensi lokal yang cepat dan andal.

---

## 🛠️ Spesifikasi & Tech Stack

- **Framework:** [Flutter](https://flutter.dev/) (Dart)
- **Target Platform:** Android (Minimum SDK disesuaikan)
- **Database:** SQLite (`sqflite`)
- **Perangkat Keras / Modul:** ESP32, Printer Thermal Bluetooth
- **Enkripsi & Keamanan:** `crypto` (SHA-256)
- **Komunikasi Hardware:** Wi-Fi (HTTP/Local Web Server) / Bluetooth

---

## 🔒 Sistem Lisensi

Aplikasi ini menggunakan skema aktivasi lisensi **Permanen (Lifetime)** yang terikat pada *Device ID* perangkat Android:

1. Aplikasi mengambil **Device ID** unik dari perangkat pengguna.
2. Kode lisensi dikalkulasi menggunakan fungsi SHA-256 dengan kombinasi *Device ID* dan *Secret Key*.
3. Pengguna menginputkan **License Key** yang dihasilkan dari generator lisensi.
4. Aplikasi memvalidasi dan menyimpan lisensi di database lokal secara permanen tanpa batas waktu kedaluwarsa.

---

## 📁 Struktur Proyek Utama

```text
lib/
├── models/             # Model data (Transaksi, Lisensi, dll.)
├── services/           # Service layer (LicenseService, Bluetooth/Wi-Fi Service)
├── database/           # Pengelolaan SQLite (LicenseDatabase, TransactionDatabase)
├── screens/            # Tampilan UI (Dashboard, Activation, Settings, dll.)
└── main.dart           # Entry point aplikasi
```
## 💻 Cara Menjalankan Proyek (Getting Started)

Ikuti langkah-langkah di bawah ini untuk mengunduh, mengonfigurasi, dan menjalankan aplikasi di lingkungan lokal kamu.

---

### 📋 Prasyarat Sistem

Sebelum menjalankan proyek, pastikan perangkat kamu telah terinstal perangkat lunak berikut:

* **Flutter SDK**: Versi 3.x.x atau yang terbaru
* **Dart SDK**: Terikut bersama Flutter SDK
* **Android Studio**: Versi terbaru (disertai Android SDK Build-Tools)
* **Android NDK**: Versi `27.0.12077973`
* **Git**: Untuk manajemen versi pustaka kode
* **Perangkat Android Fisik**: Direkomendasikan menggunakan HP/Tablet Android fisik (karena fitur akses Device ID & koneksi hardware/Bluetooth tidak berjalan optimal di Emulator).

---

### ⚙️ Langkah-Langkah Instalasi & Mengoperasikan

#### 1. Clone Repository
Buka terminal atau Git Bash, lalu jalankan perintah:
```bash
git clone [https://github.com/fasshashaa/timbangan_app.git](https://github.com/fasshashaa/timbangan_app.git)
cd timbangan_app
```
#### 2. Install Dependency
```bash
flutter pub get
```
#### 3. Konfigurasi Android NDK
Pastikan konfigurasi ndkVersion di dalam file android/app/build.gradle.kts sudah diatur ke versi 27.0.12077973
```bash
android {
    ndkVersion = "27.0.12077973"
    // ...
}
```
#### 4. Hubungkan perangkat Android
1. Aktifkan Developer Options dan USB Debugging di HP Android Anda.  
2. Sambungkan HP ke laptop menggunakan kabel USB.  
3. Verifikasi perangkat terdeteksi dengan perintah:
```bash
flutter devices
```
---
## 🔑 Generator Lisensi (Untuk Aktivasi Perangkat)
1. Buka file generator.html yang tersedia di direktori proyek menggunakan browser (Chrome, Edge, dll.).
2. Salin Device ID yang tertera pada halaman awal aplikasi di HP Android.
3. Masukkan Device ID tersebut ke dalam kolom input pada halaman generator.html.
4. Klik tombol Generate License Key.
5. Masukkan kode lisensi yang dihasilkan ke dalam aplikasi Android untuk mengaktifkan lisensi secara permanen.
