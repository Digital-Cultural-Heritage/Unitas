# 📘 Dokumentasi Lengkap Proyek UNITAS (Platform Alumni Digital)

Dokumen ini berisi arsitektur, panduan instalasi, konfigurasi jaringan, daftar modul/fitur, API endpoint, serta petunjuk build APK untuk aplikasi **Unitas**.

---

## 📑 Daftar Isi
1. [Tentang Unitas](#1-tentang-unitas)
2. [Arsitektur Sistem & Tech Stack](#2-arsitektur-sistem--tech-stack)
3. [Struktur Direktori Proyek](#3-struktur-direktori-proyek)
4. [Konfigurasi Environment (.env)](#4-konfigurasi-environment-env)
5. [Panduan Menjalankan Backend](#5-panduan-menjalankan-backend)
6. [Panduan Menjalankan Flutter & Build APK](#6-panduan-menjalankan-flutter--build-apk)
7. [Daftar Fitur & Modul Aplikasi](#7-daftar-fitur--modul-aplikasi)
8. [Spesifikasi API Endpoint (REST API)](#8-spesifikasi-api-endpoint-rest-api)
9. [Troubleshooting Umum](#9-troubleshooting-umum)

---

## 1. Tentang Unitas
**Unitas** adalah platform jejaring alumni digital yang menghubungkan alumni, mahasiswa, dan institusi pendidikan (seperti Universitas Udayana / UNUD). Platform ini memfasilitasi komunikasi, direktori kontak profesional, publikasi informasi lowongan pekerjaan (*Job Board*), agenda kegiatan kampus/alumni (*Events*), serta feed linimasa interaktif (*Posts & Comments*).

---

## 2. Arsitektur Sistem & Tech Stack

```text
┌─────────────────────────┐               ┌──────────────────────────────┐
│  Flutter Mobile App     │  HTTP / REST  │  Unitas Express Backend      │
│  (Android APK / iOS)    ├──────────────►│  (Node.js + JWT Auth)        │
└────────────┬────────────┘               └──────────────┬───────────────┘
             │                                           │
             │                                           ▼
             │                                ┌──────────────────────────┐
             └───────────────────────────────►│  Supabase Cloud          │
               (Direct Cloud Storage/Image)   │  - PostgreSQL Database   │
                                              │  - Storage (Avatars/Post)│
                                              └──────────────────────────┘
```

### 📱 Frontend (Mobile)
- **Framework:** Flutter 3.x (Dart SDK `^3.13.3`)
- **State & HTTP Management:** `http`, `flutter_dotenv`, `shared_preferences`
- **UI & Typography:** Material Design 3, Google Fonts (`Inter`, `Plus Jakarta Sans`)
- **Media Picker:** `image_picker`

### 🖥️ Backend (REST API)
- **Runtime:** Node.js (v20+)
- **Framework:** Express.js 5.x
- **Authentication:** Custom JWT (`bcryptjs` untuk hash password, `jsonwebtoken` untuk Access & Refresh Token)
- **Image Processing:** `multer` + `sharp` (optimasi dan konversi gambar otomatis ke format WebP)
- **Database & Cloud Storage:** Supabase (PostgreSQL & Supabase Storage)

---

## 3. Struktur Direktori Proyek

```text
D:\Unitas
├── unitas_backend/                 # REST API Node.js / Express
│   ├── api/
│   │   └── index.js                # Entry point server Express & route loader
│   ├── src/
│   │   ├── lib/
│   │   │   ├── jwt.js              # Token signing & verification
│   │   │   └── supabase.js         # Supabase client connector
│   │   ├── middleware/
│   │   │   ├── auth.js             # JWT verification middleware
│   │   │   └── errorHandler.js     # Global API error handler
│   │   └── routes/
│   │       ├── auth.js             # Register, login, refresh token, change password
│   │       ├── users.js            # Profil, direktori alumni, update profile
│   │       ├── posts.js            # Feed postingan, like, komentar
│   │       ├── events.js           # Event kampus, registrasi event, peserta
│   │       ├── jobs.js             # Lowongan kerja, filter, tambah loker
│   │       ├── upload.js           # Endpoint upload avatar & gambar postingan
│   │       └── stats.js            # Statistik ringkasan data alumni
│   ├── supabase/migrations/        # File skrip SQL DDL & schema database
│   ├── .env                        # Variabel environment backend
│   └── package.json
│
└── unitas_flutter/                 # Aplikasi Flutter Android/iOS
    ├── android/                    # Native Android project configuration
    │   ├── app/src/main/
    │   │   └── AndroidManifest.xml # Izin internet & cleartext HTTP config
    │   └── gradle.properties       # Optimasi memori & stabilitas build Kotlin
    ├── assets/                     # Asset lokal
    ├── lib/
    │   ├── core/
    │   │   ├── api/                # Service layer (HTTP client & REST consumer)
    │   │   │   ├── api_client.dart # Base HTTP client & interceptor
    │   │   │   ├── auth_service.dart
    │   │   │   ├── users_service.dart
    │   │   │   ├── posts_service.dart
    │   │   │   ├── events_service.dart
    │   │   │   ├── jobs_service.dart
    │   │   │   └── stats_service.dart
    │   │   └── theme/              # Skema warna dan gaya teks
    │   ├── screens/                # Halaman UI
    │   │   ├── login_screen.dart
    │   │   ├── register_screen.dart
    │   │   ├── home_screen.dart          # Linimasa / feed utama
    │   │   ├── post_detail_screen.dart   # Detail post & komentar
    │   │   ├── directory_screen.dart     # Direktori pencarian alumni
    │   │   ├── events_screen.dart        # Daftar acara alumni
    │   │   ├── create_event_screen.dart  # Form pembuatan acara
    │   │   ├── manage_event_screen.dart  # Kelola peserta event
    │   │   ├── jobs_screen.dart          # Portal info lowongan kerja
    │   │   ├── create_job_screen.dart    # Form pasang info loker
    │   │   ├── profile_screen.dart       # Halaman profil alumni
    │   │   └── edit_profile_screen.dart  # Edit biodata, keahlian, & tautan
    │   └── main.dart               # Entry point aplikasi Flutter
    ├── .env                        # Environment client Flutter
    └── pubspec.yaml                # Dependensi package
```

---

## 4. Konfigurasi Environment (.env)

### A. Backend (`unitas_backend/.env`)
File ini digunakan oleh Express.js:
```env
# ── Supabase ──────────────────────────────────────────────────────────────
SUPABASE_URL=https://zbiobfljovhuisslbncp.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1Ni... (kunci service role supabase)

# ── JWT ───────────────────────────────────────────────────────────────────
JWT_SECRET=OyQV3s4vCrtmVYXVlGFE4wmVN9WQbSvl
JWT_EXPIRES_IN=7d
REFRESH_TOKEN_SECRET=TxNLH2rKsX3D0hwb9mmzsWwKyLQ0q8ts
REFRESH_TOKEN_EXPIRES_IN=30d

# ── App & Jaringan ────────────────────────────────────────────────────────
PORT=3002
NODE_ENV=development
CORS_ORIGIN=*
PASSWORD_SUPABASE=unitasunud27
```

### B. Flutter (`unitas_flutter/.env`)
File ini dibaca oleh `flutter_dotenv` untuk menentukan endpoint tujuan API:
```env
# ── Backend API URL ────────────────────────────────────────────────────────
# Gunakan IP LAN laptop jika menguji di HP fisik (WiFi sama):
BACKEND_URL=http://192.168.1.8:3002

# Gunakan ini jika menguji di Android Studio Emulator:
# BACKEND_URL=http://10.0.2.2:3002

# ── Supabase Config ───────────────────────────────────────────────────────
SUPABASE_URL=https://zbiobfljovhuisslbncp.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1Ni...
```

> **Catatan Kritis Jaringan:**
> 1. Jika mengetes APK di **HP fisik Android**, HP dan Laptop harus tersambung ke **satu Wi-Fi yang sama**.
> 2. Jika IP laptop berubah (akibat restart router/DHCP), periksa IP baru dengan `ipconfig` dan sesuaikan nilai `BACKEND_URL` di `unitas_flutter/.env`, lalu build ulang APK.

---

## 5. Panduan Menjalankan Backend

1. Buka PowerShell atau Terminal.
2. Masuk ke folder backend:
   ```powershell
   cd D:\Unitas\unitas_backend
   ```
3. Install dependensi (hanya perlu sekali di awal):
   ```powershell
   npm install
   ```
4. Jalankan server:
   * **Mode Development (dengan reload otomatis):**
     ```powershell
     npm run dev
     ```
   * **Mode Standar:**
     ```powershell
     npm start
     ```
5. Pastikan muncul pesan:
   ```text
   Unitas API running on port 3002
   ```

---

## 6. Panduan Menjalankan Flutter & Build APK

### A. Menjalankan di Mode Debug (Langsung ke Emulator / HP USB Debugging)
```powershell
cd D:\Unitas\unitas_flutter
flutter run
```

### B. Mengompilasi Menjadi File APK Release
1. Pastikan setting `BACKEND_URL` di `unitas_flutter/.env` sudah mengarah ke IP Wi-Fi laptop.
2. Jalankan perintah pembersihan dan build:
   ```powershell
   cd D:\Unitas\unitas_flutter
   flutter clean
   flutter pub get
   flutter build apk --release
   ```
3. File APK output siap pakai berada di:
   ```text
   D:\Unitas\unitas_flutter\build\app\outputs\flutter-apk\app-release.apk
   ```
4. Transfer file `app-release.apk` tersebut ke smartphone Android Anda melalui kabel data, WhatsApp, Google Drive, atau jalankan perintah:
   ```powershell
   flutter install
   ```

---

## 7. Daftar Fitur & Modul Aplikasi

| Modul | Deskripsi Fitur |
|---|---|
| **Otentikasi (Auth)** | Registrasi alumni dengan NIM/Angkatan/Program Studi, Login akun, Session Token JWT dengan auto-refresh, Logout. |
| **Linimasa (Home Feed)** | Melihat feed postingan alumni, membuat kiriman teks & lampiran foto, tombol Like interaktif, serta komentar bertingkat. |
| **Direktori Alumni** | Menjelajahi data alumni terdaftar, fitur pencarian nama/instansi/posisi pekerjaan, filter per angkatan atau program studi. |
| **Portal Acara (Events)** | Daftar event reuni, webinar kampus, lokakarya; pendaftaran peserta event (*RSVP*); dan manajemen peserta bagi pembuat event. |
| **Papan Lowongan (Jobs)** | Informasi karir & magang eksklusif dari alumni; filter tipe pekerjaan (*Full-time*, *Part-time*, *Remote*); formulir publikasi lowongan. |
| **Profil & Biodata** | Melihat riwayat pengalaman kerja, informasi kontak (LinkedIn, WhatsApp, Email), upload foto profil/avatar, dan edit portofolio keahlian. |

---

## 8. Spesifikasi API Endpoint (REST API)

Semua endpoint diawali dengan base URL: `http://<IP_HOST>:3002/api`

### Auth (`/api/auth`)
- `POST /register` — Pendaftaran alumni baru (nama, email, password, nim, tahun_masuk, jurusan, dll).
- `POST /login` — Masuk ke akun & mendapatkan pair access token dan refresh token.
- `POST /refresh` — Memperbarui access token yang kedaluwarsa menggunakan refresh token.
- `PUT /change-password` — Mengubah password akun lama.

### Pengguna / Alumni (`/api/users`)
- `GET /` — Mengambil daftar direktori alumni (mendukung query `search`, `batch`, `major`, `page`, `limit`).
- `GET /:id` — Mengambil detail profil lengkap alumni berdasarkan user ID.
- `PUT /profile` — Memperbarui data diri, instansi, LinkedIn, dan kontak pengguna yang sedang login.

### Linimasa & Postingan (`/api/posts`)
- `GET /` — Mengambil daftar postingan terbaru.
- `POST /` — Membuat postingan baru (mendukung lampiran URL gambar).
- `POST /:id/like` — Toggle Like / Unlike pada sebuah postingan.
- `GET /:id/comments` — Mengambil daftar komentar pada postingan tertentu.
- `POST /:id/comments` — Menambahkan komentar baru ke sebuah postingan.

### Acara Alumni (`/api/events`)
- `GET /` — Menampilkan daftar agenda acara yang akan datang maupun lampau.
- `POST /` — Membuat agenda acara baru.
- `POST /:id/register` — Mendaftar sebagai peserta acara.
- `GET /:id/attendees` — Melihat daftar peserta yang telah mendaftar ke acara.

### Bursa Karir & Lowongan (`/api/jobs`)
- `GET /` — Mengambil daftar lowongan pekerjaan aktif.
- `POST /` — Mempublikasikan postingan lowongan kerja baru.

### Media & Upload (`/api/upload`)
- `POST /avatar` — Upload foto profil (diproses oleh `sharp` menjadi WebP dan disimpan ke Supabase Storage bucket `avatars`).
- `POST /post-image` — Upload gambar untuk postingan feed ke Supabase Storage bucket `post-images`.

---

## 9. Troubleshooting Umum

### A. Gagal Terhubung ke Backend dari APK Android
1. **Penyebab:** HP tidak bisa menjangkau IP laptop.
2. **Solusi:**
   - Pastikan laptop dan HP tersambung ke WiFi yang sama.
   - Buka browser Chrome di HP, buka alamat: `http://192.168.1.8:3002/api/health`. Jika muncul JSON `{"status":"ok"}`, koneksi aman.
   - Jika browser HP tidak bisa membuka alamat tersebut, periksa **Windows Defender Firewall** pada laptop Anda dan izinkan koneksi masuk untuk Node.js pada port `3002`.

### B. Error `Daemon compilation failed: Could not close incremental caches` saat Build APK
1. **Penyebab:** Konflik locking file cache Kotlin Daemon di OS Windows.
2. **Solusi:** Konfigurasi penonaktifan cache inkremental telah diterapkan di [gradle.properties](file:///d:/Unitas/unitas_flutter/android/gradle.properties). Jika masih muncul, jalankan:
   ```powershell
   cd D:\Unitas\unitas_flutter
   ./android/gradlew --stop
   flutter clean
   flutter pub get
   flutter build apk --release
   ```

### C. Error `Building with plugins requires symlink support`
1. **Penyebab:** Windows memerlukan hak istimewa untuk membuat shortcut symlink bagi package Flutter.
2. **Solusi:** Buka **Windows Settings** -> Cari **Developer Settings** -> Nyalakan opsi **Developer Mode**, atau jalankan terminal PowerShell dengan mode **Run as Administrator**.

