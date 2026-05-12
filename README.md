<div align="center">

<img src="https://img.shields.io/badge/Flutter-3.24+-02569B?style=for-the-badge&logo=flutter&logoColor=white"/>
<img src="https://img.shields.io/badge/Supabase-PostgreSQL-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white"/>
<img src="https://img.shields.io/badge/Version-3.7.2-D4A574?style=for-the-badge"/>
<img src="https://img.shields.io/badge/Platform-Android%20%7C%20Web-27AE60?style=for-the-badge"/>

# 🌸 TOKO PARFUME POS LENGKAP

### Sistem Kasir Parfumeria Multi-Cabang — Flutter + Supabase

*Point of Sale lengkap untuk toko parfum: kelola stok, pelanggan member, laporan, dan cetak struk langsung dari HP.*

</div>

---

## ✨ Fitur Utama

| Fitur | Keterangan |
|-------|-----------|
| 🛒 **POS Multi-Cabang** | Kasir, jual botol & bibit parfum, cetak struk Bluetooth + PDF |
| 👥 **Sistem Member** | Loyalitas pelanggan — diskon otomatis tiap kelipatan Rp 500.000 belanja |
| 📦 **Manajemen Stok** | Pergerakan stok real-time, export Excel, saldo awal otomatis |
| 💰 **Pengeluaran** | Catat operasional, gaji, insentif — fitur sembunyikan dari kasir |
| 📊 **Laporan** | Laporan harian/bulanan/tahunan, filter tanggal, cetak ulang struk |
| 🔒 **Role-based Access** | Owner vs Kasir — owner lihat semua, kasir hanya yang diizinkan |
| 📵 **Mode Offline** | Cache lokal (sqflite) — tetap jalan meski internet mati |
| 🌐 **Versi Web PWA** | Satu file HTML, bisa dibuka di browser, fungsi sama dengan APK |
| 📤 **Export Excel** | Export pergerakan stok ke file Excel langsung dari HP |

---

## 🚀 Cara Setup

### Prasyarat

- [Flutter](https://flutter.dev) versi 3.24+
- [Supabase](https://supabase.com) project (gratis tersedia)
- Java 17+ (untuk build Android)

---

### 📱 Setup APK (Flutter)

#### 1. Clone repo ini

```bash
git clone https://github.com/harimuliawan999-sys/TOKO-PARFUME-POS-LENGKAP.git
cd TOKO-PARFUME-POS-LENGKAP
```

#### 2. Masukkan kunci Supabase kamu

Buka file **`lib/main.dart`**, cari bagian ini (sekitar baris 13):

```dart
await Supabase.initialize(
  url: 'YOUR_SUPABASE_URL',          // ← Ganti ini
  anonKey: 'YOUR_SUPABASE_ANON_KEY', // ← Ganti ini
);
```

> **Supabase Dashboard → Settings → API → Project URL** dan **anon public key**

#### 3. Install dependencies & Build

```bash
flutter pub get
flutter build apk --release
```

APK siap di: `build/app/outputs/flutter-apk/app-release.apk`

---

### 🌐 Setup Versi Web (HTML)

Buka file **`versi_html/index.html`**, cari bagian ini (sekitar baris 448):

```javascript
const SB_URL = 'YOUR_SUPABASE_URL';        // ← Ganti ini
const SB_KEY = 'YOUR_SUPABASE_ANON_KEY';  // ← Ganti ini
```

Ganti dengan URL dan anon key Supabase kamu, lalu upload `index.html` ke hosting manapun (Netlify, Vercel, GitHub Pages, dll).

---

### 🗄️ Setup Database (Supabase)

Jalankan SQL berikut di **Supabase Dashboard → SQL Editor**, secara berurutan:

| Urutan | File | Keterangan |
|--------|------|-----------|
| 1 | `sql/v3.7_member_system.sql` | Tabel pelanggan, sistem member, RPC transaksi |
| 2 | `sql/v3.7.1_patch_pelanggan_kolom.sql` | Tambah kolom hp, alamat, created_at |
| 3 | `sql/v3.7.2_fix_fk_dan_hide_kasir.sql` | Fix FK + kolom hide_kasir pengeluaran |

> Setiap file sudah dibungkus `BEGIN/COMMIT` dan aman untuk database yang sudah punya data.

---

## 🗂️ Struktur Project

```
📁 TOKO-PARFUME-POS-LENGKAP/
├── 📁 lib/
│   ├── 📁 screens/
│   │   ├── pos_screen.dart          # Layar kasir utama
│   │   ├── home_screen.dart         # Dashboard & riwayat
│   │   ├── laporan_screen.dart      # Laporan penjualan
│   │   ├── pelanggan_screen.dart    # Manajemen pelanggan member
│   │   ├── pengeluaran_screen.dart  # Catatan pengeluaran
│   │   ├── pergerakan_screen.dart   # Stok & export Excel
│   │   └── login_screen.dart        # Login PIN
│   ├── 📁 services/
│   │   ├── api.dart                 # Semua komunikasi ke Supabase
│   │   ├── bluetooth_printer_service.dart
│   │   └── offline_cache.dart
│   └── main.dart                    # ← Letakkan kunci Supabase di sini
├── 📁 sql/
│   ├── v3.7_member_system.sql
│   ├── v3.7.1_patch_pelanggan_kolom.sql
│   └── v3.7.2_fix_fk_dan_hide_kasir.sql
├── 📁 versi_html/
│   └── index.html                   # ← Versi web PWA (letakkan kunci di sini juga)
└── pubspec.yaml
```

---

## 🛠️ Tech Stack

- **Frontend Mobile:** Flutter 3.24 + Dart 3.5
- **Frontend Web:** HTML/CSS/JS murni (single-file PWA)
- **Backend:** Supabase (PostgreSQL + RPC)
- **Database Lokal:** sqflite (offline cache)
- **Print:** Bluetooth ESC/POS + PDF
- **Export:** excel package (APK) + SheetJS (Web)

---

## 📋 Role & Akses

| Fitur | Owner | Kasir |
|-------|:-----:|:-----:|
| Semua transaksi & laporan | ✅ | ✅ |
| Stok bibit (detail ml) | ✅ | ❌ |
| Semua pengeluaran | ✅ | ❌ |
| Hide pengeluaran dari kasir | ✅ | ❌ |
| Hapus pelanggan / data | ✅ | ❌ |
| Manajemen pelanggan member | ✅ | ✅ |
| Cetak struk & export Excel | ✅ | ✅ |

---

## 👨‍💻 Developer

**Hari Muliawan, S.Mat**
- WhatsApp: [083113177107](https://wa.me/6283113177107)

---

<div align="center">
<sub>Dibuat dengan ❤️ untuk pengusaha parfumeria Indonesia</sub>
</div>
