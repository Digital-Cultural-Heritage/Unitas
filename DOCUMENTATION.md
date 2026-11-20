# Dokumentasi Lengkap Proyek UNITAS (Platform Alumni Digital)

Dokumen ini berisi dokumentasi komprehensif mengenai arsitektur sistem, struktur pohon direktori lengkap, konfigurasi lingkungan (`.env`), petunjuk backend & database migration, modul keamanan native Android C++/NDK, daftar seluruh layar & layanan Flutter, katalog REST API endpoint, hingga panduan kompilasi APK release dan troubleshooting.

---

## Daftar Isi
1. [Tentang Unitas](#1-tentang-unitas)
2. [Arsitektur Sistem & Tech Stack](#2-arsitektur-sistem--tech-stack)
3. [Struktur Direktori Lengkap Proyek](#3-struktur-direktori-lengkap-proyek)
4. [Konfigurasi Environment (.env)](#4-konfigurasi-environment-env)
5. [Skema Database & Migrasi Supabase](#5-skema-database--migrasi-supabase)
6. [Modul Keamanan Native Android (C++ NDK & CMake)](#6-modul-keamanan-native-android-c-ndk--cmake)
7. [Modul & Fitur Frontend Flutter](#7-modul--fitur-frontend-flutter)
8. [Katalog REST API Endpoints](#8-katalog-rest-api-endpoints)
9. [Panduan Instalasi & Eksekusi](#9-panduan-instalasi--eksekusi)
10. [Panduan Kompilasi APK Android Release](#10-panduan-kompilasi-apk-android-release)
11. [Troubleshooting & Solusi Error Umum](#11-troubleshooting--solusi-error-umum)
12. [Arsitektur End-to-End Encryption (E2EE) Direct Message](#12-arsitektur-end-to-end-encryption-e2ee-direct-message)
13. [Panduan Optimasi Ukuran APK & Pembersihan Cache](#13-panduan-optimasi-ukuran-apk--pembersihan-cache)

---

## 1. Tentang Unitas
**Unitas** adalah platform jejaring sosial dan profesional alumni digital (khususnya civitas akademika Universitas Udayana / UNUD) yang menghubungkan alumni, mahasiswa aktif, dan instansi pendidikan. 

Platform ini memfasilitasi:
- **Linimasa & Jejaring Sosial:** Berbagi kabar, artikel, menyukai kiriman, serta berdiskusi via komentar dan balasan bertingkat (*nested replies*).
- **Direktori Alumni Terverifikasi:** Pencarian alumni berdasarkan nama, angkatan/tahun masuk, jurusan/prodi, pekerjaan, dan perusahaan.
- **Papan Informasi Karir (Job Board):** Publikasi lowongan kerja, filter status pekerjaan (*Full-time*, *Part-time*, *Freelance*, *Remote*), pengunggahan CV/Resume PDF, dan pelacakan lamaran kerja (*applicant tracking*).
- **Agenda & Acara Alumni (Events):** Pembuatan kegiatan webinar/reuni/seminar, pendaftaran peserta (RSVP) beserta detail kontak, dan manajemen daftar hadir.
- **Pesan Pribadi (Direct Messaging/Chat):** Komunikasi langsung antar-alumni secara real-time.
- **Pusat Notifikasi:** Pemberitahuan otomatis ketika ada aktivitas baru pada postingan, lamaran pekerjaan, event, dan pesan.
- **Keamanan Aplikasi Berlapis:** Proteksi level native Android (NDK C++) terhadap ancaman perangkat di-root serta anti-reverse engineering / debugging.

---

## 2. Arsitektur Sistem & Tech Stack

```text
┌────────────────────────────────────────────────────────┐
│             Flutter Mobile Client (Dart)               │
│  - Presentation (Screens, Widgets, Google Fonts)       │
│  - Core Layer (API Services, Theme, Utils, Security)   │
└──────────────┬───────────────────────────▲─────────────┘
               │                           │
  JNI / MethodChannel          HTTP REST   │ (JSON Response)
  ("com.unitas/security")                  │
               │                           ▼
┌──────────────▼─────────────┐   ┌────────────────────────────────┐
│   Native Android NDK (C++) │   │    Node.js Express Backend     │
│   - libsecurity.so         │   │  - Express 5.x REST API        │
│   - Multi-Indicator Root   │   │  - JWT (Access & Refresh)      │
│   - Passive Anti-Debug     │   │  - Multer + Sharp (WebP Opt)   │
│   - String Obfuscation     │   │  - Express Validator           │
└────────────────────────────┘   └──────────────┬─────────────────┘
                                                │
                                  PostgreSQL /  │ Supabase JS SDK
                                  Storage API   │
                                                ▼
                                 ┌────────────────────────────────┐
                                 │         Supabase Cloud         │
                                 │  - PostgreSQL Database         │
                                 │  - Storage: avatars, posts,    │
                                 │    resumes (.pdf)              │
                                 └────────────────────────────────┘
```

### Frontend (Mobile & Multiplatform)
- **Framework:** Flutter 3.x (Dart SDK `^3.13.3`)
- **State & Networking:** `http`, `flutter_dotenv`, `shared_preferences`
- **UI Design System:** Material Design 3, Google Fonts (`Outfit`, `Inter`)
- **Media & File Handling:** `image_picker`, custom PDF picker (web/native abstraction), dialog pemotong avatar
- **Native Security Engine:** C++17, Android NDK (28.x/27.x), CMake 3.22.1

### Backend (REST API Engine)
- **Runtime:** Node.js (v20+)
- **Framework:** Express.js 5.x
- **Otentikasi & Enkripsi:** Dual-Token JWT (Access Token 7 hari, Refresh Token 30 hari), hashing password via `bcryptjs`
- **Validasi Data:** `express-validator`
- **Media Optimization:** `multer` (in-memory buffer) & `sharp` (auto-resize + kompresi ke format `.webp`)
- **Database & Storage Provider:** Supabase Cloud (PostgreSQL 15+)

---

## 3. Struktur Direktori Lengkap Proyek

Berikut adalah struktur file dan folder lengkap di dalam repository `D:\Unitas`:

```text
D:\Unitas\
├── .gitignore                          # Global root gitignore (secrets, IDE, OS)
├── DOCUMENTATION.md                    # Dokumentasi utama proyek Unitas
│
├── unitas_backend\                     # Layanan Backend Node.js / Express
│   ├── .env                            # Konfigurasi environment rahasia backend
│   ├── .env.example                    # Template konfigurasi environment backend
│   ├── .gitignore                      # Aturan git ignore backend (node_modules, logs)
│   ├── package.json                    # Dependensi dan script NPM
│   ├── package-lock.json               # Lockfile dependensi backend
│   ├── README.md                       # Panduan singkat backend
│   ├── vercel.json                     # Konfigurasi deployment serverless Vercel
│   │
│   ├── api\
│   │   └── index.js                    # Server entrypoint Express & router aggregator
│   │
│   ├── src\
│   │   ├── lib\
│   │   │   ├── jwt.js                  # Generator & verifikator access/refresh token JWT
│   │   │   ├── notifications.js        # Helper pembuatan data notifikasi sistem
│   │   │   ├── supabase.js             # Inisialisasi Supabase Client (service role)
│   │   │   └── validate.js             # Reusable validation middleware
│   │   ├── middleware\
│   │   │   ├── auth.js                 # Middleware otentikasi Bearer Token JWT
│   │   │   └── errorHandler.js         # Global error handler middleware
│   │   └── routes\
│   │       ├── auth.js                 # Endpoint otentikasi (register, login, google)
│   │       ├── events.js               # Endpoint acara/event & peserta (RSVP)
│   │       ├── jobs.js                 # Endpoint lowongan kerja & pelamar kerja
│   │       ├── keys.js                 # Endpoint manajemen public key E2EE (X3DH / Ratchet)
│   │       ├── messages.js             # Endpoint direct message / percakapan alumni (ciphertext)
│   │       ├── notifications.js        # Endpoint notifikasi user
│   │       ├── posts.js                # Endpoint feed postingan, like, & komentar
│   │       ├── stats.js                # Endpoint agregasi statistik dashboard
│   │       ├── upload.js               # Endpoint upload gambar & file PDF ke Supabase
│   │       └── users.js                # Endpoint data alumni, pencarian, & update profil
│   │
│   ├── supabase\
│   │   └── migrations\                 # Riwayat migrasi DDL SQL database
│   │       ├── 001_initial_schema.sql  # Schema dasar tabel & relasi awal
│   │       ├── 002_add_comments.sql    # Penambahan tabel komentar postingan
│   │       ├── 003_add_features.sql    # Fitur interaksi & bookmark tambahan
│   │       ├── 004_add_comment_replies.sql          # Dukungan balasan komentar berantai
│   │       ├── 005_event_registration_details.sql   # Kolom rincian pendaftaran acara
│   │       ├── 005_google_auth.sql                  # Dukungan OAuth Google Sign-In
│   │       ├── 006_indexes_and_fixes.sql            # Indexing performa query pencarian
│   │       ├── 007_add_job_applications.sql         # Tabel pelamar kerja (CV, status)
│   │       └── 008_add_e2ee_keys.sql                # Tabel user_keys dan kolom ciphertext E2EE
│   │
│   └── test\
│       ├── api.test.js                 # Unit & integration testing API
│       └── routes.test.js              # Pengujian rute spesifik
│
└── unitas_flutter\                     # Aplikasi Mobile Client Flutter
    ├── .env                            # Konfigurasi environment Flutter (BACKEND_URL)
    ├── .env.example                    # Template environment Flutter
    ├── .gitignore                      # Aturan git ignore Flutter (.dart_tool, .cxx, build)
    ├── analysis_options.yaml           # Konfigurasi linter & static analysis Dart
    ├── pubspec.yaml                    # Konfigurasi dependencies dan assets Flutter
    ├── pubspec.lock                    # Dependency lockfile Flutter
    │
    ├── android\                        # Native Android Wrapper
    │   ├── gradle.properties           # Konfigurasi heap memory Gradle & flag Kotlin
    │   ├── local.properties            # Path SDK dan NDK lokal mesin
    │   ├── app\
    │   │   ├── build.gradle.kts        # Script build Gradle app + NDK CMake binding
    │   │   └── src\
    │   │       └── main\
    │   │           ├── AndroidManifest.xml # Izin internet, cleartext HTTP, activity
    │   │           ├── cpp\            # C++ Native Security Layer (NDK)
    │   │           │   ├── CMakeLists.txt  # Build script kompilasi libsecurity.so
    │   │           │   ├── security.h      # Deklarasi fungsi JNI & utilitas XOR string
    │   │           │   └── security.cpp    # Implementasi Root Detection & Anti-Debug
    │   │           └── kotlin\com\unitas\
    │   │               ├── security\
    │   │               │   ├── SecurityCheck.kt     # JNI Bridge Kotlin <-> C++
    │   │               │   └── SecurityCallback.kt  # Interface deteksi ancaman debugger
    │   │               └── unitas_flutter\
    │   │                   └── MainActivity.kt      # Registrasi MethodChannel saat startup
    │   └── res\                        # Icon launcher aplikasi dan tema native
    │
    └── lib\                            # Sumber Kode Aplikasi Flutter
        ├── main.dart                   # Entry point aplikasi + Security Pre-check Gate
        ├── core\
        │   ├── api\                    # Service Layer Penghubung ke REST API
        │   │   ├── api_client.dart     # HTTP client wrapper & authorization header
        │   │   ├── auth_service.dart   # Manajemen sesi user, JWT, dan login/register
        │   │   ├── events_service.dart # Permintaan data event & pendaftaran
        │   │   ├── jobs_service.dart   # Permintaan loker & upload berkas lamaran
        │   │   ├── messages_service.dart       # API pengiriman pesan dan riwayat chat
        │   │   ├── notifications_service.dart  # API pembacaan dan update notifikasi
        │   │   ├── posts_service.dart  # CRUD postingan linimasa & komentar
        │   │   ├── stats_service.dart  # Pengambilan data statistik umum
        │   │   └── users_service.dart  # Pencarian direktori alumni & profil
        │   ├── crypto\                 # End-to-End Encryption (E2EE) Engine
        │   │   ├── e2ee_service.dart   # Implementasi X3DH, Double Ratchet, ChaCha20, HKDF
        │   │   └── ratchet_state.dart  # Model serialisasi state ratchet per percakapan
        │   ├── security\
        │   │   ├── security_service.dart       # MethodChannel client "com.unitas/security"
        │   │   └── security_block_screen.dart  # Fullscreen blocking view jika root/debug
        │   ├── theme\
        │   │   ├── colors.dart         # Palet warna resmi Unitas (Navy, Gold, Background)
        │   │   └── text_styles.dart    # Konfigurasi tipografi teks aplikasi
        │   └── utils\
        │       ├── image_validator.dart# Validasi ukuran dan format berkas gambar
        │       ├── json_utils.dart     # Safe parser tipe data JSON
        │       ├── pdf_picker.dart     # Multiplatform abstraction pemilih file PDF
        │       ├── pdf_picker_stub.dart# Fallback pemilih PDF
        │       └── pdf_picker_web.dart # Implementasi pemilih file PDF di Web
        │
        ├── screens\                    # Tampilan / Halaman Pengguna
        │   ├── alumni_profile_screen.dart   # Detail profil alumni lain
        │   ├── chat_list_screen.dart        # Daftar inbox obrolan alumni
        │   ├── chat_room_screen.dart        # Ruang percakapan pesan langsung
        │   ├── create_event_screen.dart     # Formulir publikasi agenda acara baru
        │   ├── create_job_screen.dart       # Formulir publikasi info lowongan kerja
        │   ├── directory_screen.dart        # Halaman pencarian & filter direktori alumni
        │   ├── edit_profile_screen.dart     # Formulir pengubahan biodata, avatar, kontak
        │   ├── events_screen.dart           # Linimasa daftar agenda & kegiatan
        │   ├── home_screen.dart             # Linimasa kiriman utama (Feed post)
        │   ├── jobs_screen.dart             # Bursa karir dan lowongan pekerjaan
        │   ├── login_screen.dart            # Halaman masuk akun
        │   ├── manage_event_screen.dart     # Manajemen peserta acara bagi pembuat event
        │   ├── manage_job_screen.dart       # Manajemen berkas pelamar kerja
        │   ├── notifications_screen.dart    # Daftar notifikasi aktivitas pengguna
        │   ├── post_detail_screen.dart      # Rincian postingan, like, & komentar lengkap
        │   ├── profile_screen.dart          # Tampilan profil pribadi pengguna login
        │   └── register_screen.dart         # Halaman pendaftaran alumni baru
        │
        └── widgets\                    # Komponen UI Reusable
            ├── avatar.dart             # Komponen avatar circular dengan fallback inisial
            ├── image_cropper_dialog.dart # Dialog crop/preview foto sebelum di-upload
            └── skeleton.dart           # Placeholder animasi shimmer loading
```

---

## 4. Konfigurasi Environment (.env)

### A. Backend (`unitas_backend/.env`)
Konfigurasi wajib untuk menjalankan API Express dan koneksi database:
```env
# ── Supabase Cloud Configuration ──────────────────────────────────────────
SUPABASE_URL=https://zbiobfljovhuisslbncp.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9... # Token Service Role

# ── JWT Authentication Secrets ────────────────────────────────────────────
JWT_SECRET=OyQV3s4vCrtmVYXVlGFE4wmVN9WQbSvl
JWT_EXPIRES_IN=7d
REFRESH_TOKEN_SECRET=TxNLH2rKsX3D0hwb9mmzsWwKyLQ0q8ts
REFRESH_TOKEN_EXPIRES_IN=30d

# ── Server Port & Mode ───────────────────────────────────────────────────
PORT=3002
NODE_ENV=development

# ── Keamanan Jaringan & CORS ──────────────────────────────────────────────
CORS_ORIGIN=*
```

### B. Flutter App (`unitas_flutter/.env`)
Konfigurasi alamat endpoint API backend yang dikonsumsi oleh aplikasi Flutter:
```env
# ── URL Backend API ───────────────────────────────────────────────────────
# Opsi 1: Jika dijalankan di HP fisik via Wi-Fi lokal:
BACKEND_URL=http://192.168.1.8:3002

# Opsi 2: Jika dijalankan di Android Studio Emulator:
# BACKEND_URL=http://10.0.2.2:3002

# Opsi 3: Jika backend telah dideploy ke public server / cloud:
# BACKEND_URL=https://api-unitas.yourdomain.com

# ── Supabase Public (Client-side Direct Access jika diperlukan) ────────────
SUPABASE_URL=https://zbiobfljovhuisslbncp.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

> **Catatan Pengujian di Smartphone Fisik:**
> Agar smartphone dapat menghubungi server backend di laptop, keduanya wajib berada dalam **satu jaringan Wi-Fi lokal yang sama**. Alamat IP pada `BACKEND_URL` harus disesuaikan dengan IP IPv4 laptop saat ini (cek via perintah terminal `ipconfig`).

---

## 5. Skema Database & Migrasi Supabase

Database menggunakan Supabase (PostgreSQL). File DDL tersimpan di `unitas_backend/supabase/migrations/`:

| Nomor Migrasi | Nama File | Deskripsi Skema |
|---|---|---|
| **001** | `001_initial_schema.sql` | Membuat tabel dasar: `users`, `posts`, `events`, `jobs`, dan enumerasi peran (*roles*). |
| **002** | `002_add_comments.sql` | Membuat tabel `comments` dengan referensi foreign key ke `posts` dan `users`. |
| **003** | `003_add_features.sql` | Menambahkan fungsionalitas bookmark loker dan riwayat kontak alumni. |
| **004** | `004_add_comment_replies.sql` | Menambahkan kolom `parent_id` pada tabel `comments` untuk mendukung balasan bertingkat (*nested discussion*). |
| **005a**| `005_event_registration_details.sql` | Memperluas tabel pendaftaran acara dengan nomor WhatsApp, instansi, dan status kehadiran. |
| **005b**| `005_google_auth.sql` | Menambahkan kolom `google_id` dan penanganan autentikasi pihak ketiga. |
| **006** | `006_indexes_and_fixes.sql` | Penambahan *GIN index* dan *B-tree index* untuk optimasi kecepatan pencarian nama dan postingan. |
| **007** | `007_add_job_applications.sql` | Membuat tabel `job_applications` untuk menyimpan pengajuan lamaran, URL resume/CV (PDF), dan status seleksi. |

---

## 6. Modul Keamanan Native Android (C++ NDK & CMake)

Untuk menjamin integritas data dan keamanan aplikasi dari risiko penyadapan data pada perangkat yang tidak aman, Unitas dilengkapi modul keamanan tingkat native:

### A. Lokasi File Native
- Header C++: [`unitas_flutter/android/app/src/main/cpp/security.h`](file:///d:/Unitas/unitas_flutter/android/app/src/main/cpp/security.h)
- Implementasi C++: [`unitas_flutter/android/app/src/main/cpp/security.cpp`](file:///d:/Unitas/unitas_flutter/android/app/src/main/cpp/security.cpp)
- Konfigurasi CMake: [`unitas_flutter/android/app/src/main/cpp/CMakeLists.txt`](file:///d:/Unitas/unitas_flutter/android/app/src/main/cpp/CMakeLists.txt)
- JNI Kotlin Bridge: [`unitas_flutter/android/app/src/main/kotlin/com/unitas/security/SecurityCheck.kt`](file:///d:/Unitas/unitas_flutter/android/app/src/main/kotlin/com/unitas/security/SecurityCheck.kt)

### B. Mekanisme Root Detection (Multi-Indicator)
Native function `Java_com_unitas_security_SecurityCheck_isDeviceRooted` memvalidasi beberapa indikator sekaligus:
1. **Keberadaan Binary `su`:** Memeriksa path tersembunyi (`/system/bin/su`, `/system/xbin/su`, `/sbin/su`, `/data/local/xbin/su`, dll).
2. **Build Tags Mencurigakan:** Memeriksa system property `ro.build.tags` dari sistem operasi terhadap string `test-keys`.
3. **Pemeriksaan Paket Root:** Memeriksa keberadaan package manager root umum seperti Magisk (`com.topjohnwu.magisk`), SuperSU, dan Superuser melalui PackageManager Android.
4. **Izin Tulis Direktori Sistem:** Menguji pembuatan berkas sementara pada `/system/` untuk mendeteksi remount filesystem sebagai *read-write*.
5. **Path Environment:** Memeriksa keberadaan utility `busybox` di dalam environment variable `PATH`.
6. **Obfuscation String:** Seluruh path string dienkripsi sederhana dengan *byte-level XOR (Key: 0x5A)* sehingga tidak dapat dibaca melalui perintah `strings` pada file `.so`.

### C. Mekanisme Anti-Debug Stabil (Passive Mode)
- **Deteksi TracerPid:** Thread monitor native membaca `/proc/self/status` secara berkala setiap 5 detik. Apabila nilai `TracerPid > 0` (menandakan ada proses gdb, lldb, atau frida yang menempel), sistem akan memicu callback deteksi debugger.
- **PTRACE_TRACEME:** Mendeteksi apakah proses telah ditandai untuk debugging saat awal aplikasi berjalan.
- **Respon Flutter:** Jika terdeteksi root atau debugger, layar aplikasi akan langsung diblokir secara penuh oleh [`SecurityBlockScreen`](file:///d:/Unitas/unitas_flutter/lib/core/security/security_block_screen.dart) dan memblokir navigasi sebelum proses dimatikan secara aman.

---

## 7. Modul & Fitur Frontend Flutter

| Modul | File Screen Utama | Fungsionalitas |
|---|---|---|
| **Security Gate** | `lib/main.dart` & `security_block_screen.dart` | Mengecek integritas root sebelum `runApp()`. Menampilkan layar peringatan merah jika perangkat tidak aman. |
| **Autentikasi** | `login_screen.dart`, `register_screen.dart` | Form masuk dan registrasi alumni dengan validasi NIM, jurusan, angkatan, serta penyimpanan token JWT di `SharedPreferences`. |
| **Linimasa (Feed)**| `home_screen.dart`, `post_detail_screen.dart` | Menampilkan postingan terkini, membuat postingan baru dengan foto, memberikan like, serta menulis komentar dan balasan. |
| **Direktori Alumni**| `directory_screen.dart`, `alumni_profile_screen.dart` | Pencarian alumni real-time dengan filter fakultas/jurusan, tahun angkatan, dan detail kontak profesional (LinkedIn, Email). |
| **Portal Acara** | `events_screen.dart`, `create_event_screen.dart`, `manage_event_screen.dart` | Agenda kegiatan alumni, formulir publikasi acara, RSVP pendaftaran peserta, dan ekspor/manajemen daftar hadir. |
| **Papan Karir** | `jobs_screen.dart`, `create_job_screen.dart`, `manage_job_screen.dart` | Informasi lowongan kerja, filter tipe kerja, formulir pengajuan lamaran dengan lampiran dokumen PDF (CV). |
| **Pesan Pribadi** | `chat_list_screen.dart`, `chat_room_screen.dart` | Daftar kontak obrolan dan ruang percakapan personal antar alumni secara real-time. |
| **Notifikasi** | `notifications_screen.dart` | Riwayat pemberitahuan aktivitas akun (interaksi postingan, penerimaan lamaran, update event). |
| **Profil Pengguna**| `profile_screen.dart`, `edit_profile_screen.dart` | Ringkasan riwayat karir, avatar dinamis dengan crop tool, serta pembaruan data kontak diri. |

---

## 8. Katalog REST API Endpoints

Semua endpoint berbasis REST JSON dengan Base URL: `http://<HOST>:3002/api`

### 1. Autentikasi (`/api/auth`)
- `POST /api/auth/register` — Pendaftaran akun alumni baru.
- `POST /api/auth/login` — Masuk akun dan memperoleh pair Access Token & Refresh Token.
- `POST /api/auth/refresh` — Memperbarui Access Token menggunakan Refresh Token.
- `PUT /api/auth/change-password` — Mengubah kata sandi pengguna (Wajib Auth).

### 2. Pengguna & Direktori (`/api/users`)
- `GET /api/users` — Mengambil daftar direktori alumni (Query params: `search`, `batch`, `major`, `page`, `limit`).
- `GET /api/users/:id` — Mengambil data detail profil alumni tertentu.
- `PUT /api/users/profile` — Memperbarui profil pengguna yang sedang login (Wajib Auth).

### 3. Linimasa & Postingan (`/api/posts`)
- `GET /api/posts` — Mengambil daftar feed postingan terbaru beserta jumlah like dan komentar.
- `POST /api/posts` — Membuat postingan baru dengan teks dan lampiran foto (Wajib Auth).
- `POST /api/posts/:id/like` — Toggle like / unlike pada kiriman tertentu (Wajib Auth).
- `GET /api/posts/:id/comments` — Mengambil daftar komentar dan balasan komentar postingan.
- `POST /api/posts/:id/comments` — Menambahkan komentar baru atau balasan komentar (Wajib Auth).

### 4. Acara Alumni (`/api/events`)
- `GET /api/events` — Mengambil daftar kegiatan/event alumni.
- `POST /api/events` — Membuat agenda kegiatan baru (Wajib Auth).
- `POST /api/events/:id/register` — Pendaftaran kehadiran acara (RSVP) (Wajib Auth).
- `GET /api/events/:id/attendees` — Melihat daftar peserta terdaftar (Wajib Auth pembuat acara).

### 5. Karir & Lowongan Kerja (`/api/jobs`)
- `GET /api/jobs` — Mengambil daftar lowongan pekerjaan aktif.
- `POST /api/jobs` — Mempublikasikan lowongan kerja baru (Wajib Auth).
- `POST /api/jobs/:id/apply` — Mengajukan lamaran kerja dengan menyertakan URL resume/CV (Wajib Auth).
- `GET /api/jobs/:id/applications` — Mengambil data pelamar untuk lowongan yang dipasang (Wajib Auth).

### 6. Pesan Pribadi (`/api/messages`)
- `GET /api/messages/conversations` — Mengambil riwayat percakapan terkini (Wajib Auth).
- `GET /api/messages/:userId` — Mengambil riwayat obrolan dengan alumni tertentu (Wajib Auth).
- `POST /api/messages/:userId` — Mengirimkan pesan baru ke alumni tertentu (Wajib Auth).

### 7. Media & Berkas (`/api/upload`)
- `POST /api/upload/avatar` — Upload foto profil (Otomatis dikonversi ke `.webp` via Sharp dan disimpan ke Supabase Storage `avatars`).
- `POST /api/upload/post-image` — Upload foto postingan ke bucket `post-images`.
- `POST /api/upload/resume` — Upload dokumen resume/CV PDF ke bucket `resumes`.

### 8. Notifikasi & Statistik
- `GET /api/notifications` — Mengambil daftar notifikasi pengguna (Wajib Auth).
- `PUT /api/notifications/:id/read` — Menandai notifikasi telah dibaca (Wajib Auth).
- `GET /api/stats` — Mengambil statistik ringkasan alumni, acara, dan lowongan.

---

## 9. Panduan Instalasi & Eksekusi

### Langkah 1: Menjalankan Backend Express
1. Buka terminal PowerShell di folder backend:
   ```powershell
   cd D:\Unitas\unitas_backend
   ```
2. Pastikan dependensi Node telah terinstall:
   ```powershell
   npm install
   ```
3. Jalankan server:
   ```powershell
   npm run dev
   # Server akan berjalan pada http://localhost:3002
   ```

### Langkah 2: Menjalankan Aplikasi Flutter (Mode Debug)
1. Buka terminal baru di direktori Flutter:
   ```powershell
   cd D:\Unitas\unitas_flutter
   ```
2. Unduh paket dependensi:
   ```powershell
   flutter pub get
   ```
3. Hubungkan perangkat smartphone (USB Debugging) atau jalankan emulator Android Studio, lalu jalankan:
   ```powershell
   flutter run
   ```

---

## 10. Panduan Kompilasi APK Android Release

Untuk menghasilkan file APK produksi mandiri (*standalone*) yang sudah terhubung dengan modul C++ NDK:

1. **Sinkronisasi IP Backend:**
   Pastikan file `unitas_flutter/.env` mengarah ke IP Wi-Fi laptop Anda (misal: `http://192.168.1.8:3002`).

2. **Jalankan Perintah Build:**
   ```powershell
   cd D:\Unitas\unitas_flutter
   flutter clean
   flutter pub get
   flutter build apk --release
   ```

3. **Lokasi File Output:**
   File APK hasil kompilasi akan berada di direktori:
   ```text
   D:\Unitas\unitas_flutter\build\app\outputs\flutter-apk\app-release.apk
   ```

4. **Instalasi ke Perangkat Android:**
   Anda dapat langsung mentransfer file `app-release.apk` ke HP, atau menginstalnya via perintah ADB:
   ```powershell
   flutter install
   ```

---

## 11. Troubleshooting & Solusi Error Umum

### A. Aplikasi Force Close Setelah Beberapa Detik
- **Penyebab:** Mekanisme anti-debug lama yang menggunakan `fork() + ptrace()` diblokir oleh SELinux pada sistem Android modern, menyebabkan proses anak gagal dan memicu pembunuhan proses induk.
- **Solusi:** Modul keamanan telah diperbarui ke sistem *Passive Anti-Debug* (`PTRACE_TRACEME` & polling `TracerPid` tanpa fork).

### B. Error Kompilasi NDK C++ (`too many arguments to function call`)
- **Penyebab:** Menggunakan sintaks JNI gaya C (`(*env)->Method(env, ...)`) di dalam file berekstensi C++ (`.cpp`).
- **Solusi:** Pada C++, sintaks JNI wajib menggunakan format `env->Method(...)`. Hal ini telah diperbaiki di `security.cpp`.

### C. Error `Could not close incremental caches` pada Kotlin
- **Penyebab:** Bug file-locking cache inkremental pada Kotlin Daemon di platform Windows saat mengompilasi plugin `image_picker` atau `shared_preferences`.
- **Solusi:** Telah ditambahkan konfigurasi berikut pada [`unitas_flutter/android/gradle.properties`](file:///d:/Unitas/unitas_flutter/android/gradle.properties):
  ```properties
  kotlin.incremental=false
  kotlin.compiler.execution.strategy=in-process
  ```

### D. HP Fisik Tidak Dapat Terhubung ke Server Backend
- **Penyebab:** Nilai `BACKEND_URL` di `unitas_flutter/.env` masih berupa `localhost` atau diblokir oleh Windows Defender Firewall.
- **Solusi:**
  1. Ganti `localhost` menjadi IP laptop (contoh: `192.168.1.8:3002`).
  2. Buka izin port `3002` pada Windows Defender Firewall (Inbound Rules) untuk aplikasi Node.js.
  3. Pastikan izin `android:usesCleartextTraffic="true"` dan `<uses-permission android:name="android.permission.INTERNET"/>` aktif di [`AndroidManifest.xml`](file:///d:/Unitas/unitas_flutter/android/app/src/main/AndroidManifest.xml).

---

## 12. Arsitektur End-to-End Encryption (E2EE) Direct Message

Sistem obrolan langsung (1-on-1 Direct Message) pada Unitas menerapkan **End-to-End Encryption (E2EE)** penuh. Prinsip utamanya: **server backend dan database Supabase TIDAK PERNAH melihat plaintext isi pesan**. Backend bertindak murni sebagai *relay* dan penyimpan *ciphertext*. Semua proses enkripsi dan dekripsi terjadi eksklusif di sisi perangkat klien (Flutter).

### 12.1 Spesifikasi Algoritma Kriptografi
- **Key Agreement:** X25519 (Curve25519 Elliptic-Curve Diffie-Hellman / ECDH)
- **Digital Signature:** Ed25519 (penandatanganan prekey untuk mencegah serangan MITM)
- **Key Derivation Function (KDF):** HKDF-SHA256
- **AEAD Cipher:** ChaCha20-Poly1305 (dengan nonce acak 12-byte per pesan)
- **Protokol Sesi:** Double Ratchet Sederhana (DH Ratchet + Symmetric-Key Ratchet), terinspirasi dari Signal Protocol untuk sesi obrolan 1-on-1.

### 12.2 Alur Pertukaran Kunci & Ratchet
1. **Pendaftaran Kunci (First Login):**
   - Perangkat klien menghasilkan keypair identity (X25519 + Ed25519) dan signed prekey.
   - Private key disimpan secara aman di perangkat via `flutter_secure_storage` (dibackup hardware Android KeyStore). Private key **tidak pernah** meninggalkan perangkat.
   - Public key bundle diunggah ke backend melalui `POST /api/keys/register` dan disimpan pada tabel `user_keys`.
2. **Inisiasi Sesi (X3DH-lite):**
   - Ketika User A membuka chat dengan User B untuk pertama kali, A mengambil public bundle B via `GET /api/keys/:userId`.
   - A menghasilkan ephemeral key X25519 baru dan menghitung shared secret dari 3 operasi ECDH (DH1, DH2, DH3), lalu menurunkan Root Key awal via HKDF-SHA256.
3. **Double Ratchet (Sending & Receiving):**
   - **Symmetric Ratchet:** Setiap pesan yang dikirim menurunkan Message Key baru secara one-way dari Chain Key. Forward secrecy terjamin; kunci pesan lama dihapus seketika setelah enkripsi.
   - **DH Ratchet:** Saat menerima balasan dengan ratchet public key baru, kedua pihak melakukan langkah DH Ratchet untuk memperbarui Root Key dan mereset Chain Key.
   - **Out-of-Order Delivery:** Dilengkapi dengan buffer skipped-message-keys (hingga 100 kunci) untuk menangani pesan yang tiba tidak berurutan karena fluktuasi jaringan.

### 12.3 Analisis Keamanan & Batasan (Security Assessment)
- **Ancaman yang Ditangkal (Mitigated):**
  - *Database / Cloud Breach:* Jika database Supabase bocor, penyerang hanya mendapatkan data acak (*ciphertext* dan *nonce*). Plaintext pesan tidak dapat dibaca.
  - *Man-in-the-Middle (MITM):* Payload dienkripsi dengan autentikasi Poly1305 MAC, tamper-proof terhadap manipulasi paket di jaringan.
  - *Passive Server Snooping:* Admin backend atau penyedia hosting tidak dapat memantau isi percakapan.
  - *Replay Attacks:* Nomor urut pesan (`message_number`) dan rotasi kunci mencegah replay pesan lama.
- **Batasan Sistem (Known Limitations):**
  - *Single-Device Only:* Kunci disimpan lokal. Jika aplikasi diinstal ulang, sesi lama tidak dapat didekripsi (trade-off wajar untuk keamanan tanpa cloud backup).
  - *Metadata Visibility:* Server tetap mengetahui relasi siapa mengobrol dengan siapa dan stempel waktu pengiriman (`sender_id`, `receiver_id`, `created_at`).

---

## 13. Panduan Optimasi Ukuran APK & Pembersihan Cache

### 13.1 Pembersihan File Sampah Build
Folder cache kompilasi seperti `build/` dan `android/app/.cxx` dapat menumpuk hingga berukuran >1 GB setelah beberapa kali proses build. Bersihkan secara berkala menggunakan perintah:
```powershell
cd D:\Unitas\unitas_flutter
.\android\gradlew --stop
flutter clean
Remove-Item -Recurse -Force android\app\.cxx -ErrorAction SilentlyContinue
flutter pub get
```

### 13.2 Memperkecil Ukuran APK Hingga 70%
Secara default `flutter build apk --release` menghasilkan file "Fat APK" berukuran 50–70 MB yang berisi semua arsitektur native sekaligus. Untuk menghasilkan APK yang ringan (~15–20 MB):
```powershell
# Memecah APK per arsitektur CPU (arm64-v8a untuk HP modern, armeabi-v7a untuk HP lama)
flutter build apk --release --split-per-abi

# Menghapus simbol debug dan mengaburkan kode (obfuscate)
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
```
Hasil output akan berada di `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.
