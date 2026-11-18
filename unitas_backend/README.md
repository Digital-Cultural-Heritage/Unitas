# Unitas Backend API

REST API untuk **Unitas — Platform Alumni Digital**, dibangun dengan Express.js dan Supabase.

## Stack
- **Runtime**: Node.js 20+
- **Framework**: Express.js
- **Database**: Supabase (PostgreSQL)
- **Auth**: Custom JWT (`bcryptjs` + `jsonwebtoken` + `google-auth-library` + `express-rate-limit`)
- **Upload**: Multer + Sharp (konversi otomatis ke .webp) + Supabase Storage
- **Deploy**: Vercel (Serverless)

---

## Setup Lokal

### 1. Clone & Install
```bash
cd unitas_backend
npm install
```

### 2. Konfigurasi Environment
```bash
cp .env.example .env
# Edit .env dengan kredensial Supabase, JWT secret, dan Google Client ID kamu
```

Variabel lingkungan penting:
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`: kredensial Supabase project.
- `JWT_SECRET`, `REFRESH_TOKEN_SECRET`: string acak panjang & unik untuk menandatangani token.
- `GOOGLE_CLIENT_ID`: **Web OAuth 2.0 Client ID** dari Google Cloud Console (harus sama dengan `serverClientId` yang dipakai di Flutter `google_sign_in`).
- `GOOGLE_SERVER_CLIENT_IDS` *(opsional)*: daftar Client ID tambahan dipisahkan koma (misal untuk beberapa flavor/environment).
- `CORS_ORIGIN`: `*` atau daftar origin dipisahkan koma.
- `RESEND_API_KEY`, `EMAIL_FROM` *(opsional)*: untuk mengirim OTP reset password via Resend.

### 3. Setup Supabase
- Buka [Supabase Dashboard](https://supabase.com)
- Buat project baru
- Buka **SQL Editor** → jalankan file migrasi di `supabase/migrations/` secara berurutan (`001_initial_schema.sql`, `002_add_comments.sql`, `003_add_features.sql`, `004_add_comment_replies.sql`, `005_google_auth.sql`, dan migrasi berikutnya bila ada)
- Buka **Storage** → buat 2 bucket:
  - `avatars` (public)
  - `post-images` (public)
- Copy **Project URL** dan **service_role key** ke `.env`

### 4. Jalankan Lokal
```bash
npm run dev
# Server berjalan di http://localhost:3000
```

### 5. Jalankan Test
```bash
npm test
```

---

## Deploy ke Vercel

### Pertama kali
```bash
npm install -g vercel
vercel login
vercel
```

### Update
```bash
vercel --prod
```

### Environment Variables di Vercel
Di Vercel Dashboard → Project → Settings → Environment Variables, tambahkan semua variable dari `.env.example` (minimal `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `JWT_SECRET`, `REFRESH_TOKEN_SECRET`, serta `GOOGLE_CLIENT_ID` untuk Google Sign-In).

---

## API Endpoints

| Method | Endpoint | Auth | Deskripsi |
|--------|----------|------|-----------|
| GET | `/api/health` | - | Health check |
| **Auth** | | | |
| POST | `/api/auth/register` | - | Daftar akun baru |
| POST | `/api/auth/login` | - | Login email & password |
| POST | `/api/auth/google` | - | Login / daftar dengan Google ID token |
| GET | `/api/auth/me` | 🔒 | Profil akun yang sedang login |
| POST | `/api/auth/logout` | - | Logout (cabut refresh token) |
| POST | `/api/auth/refresh` | - | Rotasi access & refresh token |
| POST | `/api/auth/change-password` | 🔒 | Ubah password |
| POST | `/api/auth/forgot-password` | - | Kirim OTP reset password |
| POST | `/api/auth/reset-password` | - | Verifikasi OTP & set password baru |
| **Users** | | | |
| GET | `/api/users` | - | Direktori alumni |
| GET | `/api/users/me` | 🔒 | Profil sendiri |
| PUT | `/api/users/me` | 🔒 | Update profil |
| GET | `/api/users/:id` | - | Profil alumni |
| POST | `/api/users/:id/connect` | 🔒 | Kirim koneksi |
| GET | `/api/users/me/connections` | 🔒 | Daftar koneksi |
| **Posts** | | | |
| GET | `/api/posts` | - | Feed terbaru |
| POST | `/api/posts` | 🔒 | Buat post |
| DELETE | `/api/posts/:id` | 🔒 | Hapus post |
| POST | `/api/posts/:id/like` | 🔒 | Toggle like |
| GET | `/api/posts/leaderboard` | - | Papan peringkat |
| **Events** | | | |
| GET | `/api/events` | - | Daftar acara |
| GET | `/api/events/:id` | - | Detail acara |
| POST | `/api/events` | 🔒 | Buat acara |
| POST | `/api/events/:id/register` | 🔒 | Daftar acara |
| DELETE | `/api/events/:id/register` | 🔒 | Batal daftar |
| **Jobs** | | | |
| GET | `/api/jobs` | - | Daftar lowongan |
| GET | `/api/jobs/:id` | - | Detail lowongan |
| POST | `/api/jobs` | 🔒 | Post lowongan |
| POST | `/api/jobs/:id/save` | 🔒 | Toggle simpan |
| GET | `/api/jobs/saved` | 🔒 | Lowongan tersimpan |
| **Upload** | | | |
| POST | `/api/upload/avatar` | 🔒 | Upload foto profil (→ .webp) |
| POST | `/api/upload/post` | 🔒 | Upload foto post (→ .webp) |
| **Stats** | | | |
| GET | `/api/stats` | - | Statistik platform |

### Format Auth Header
```
Authorization: Bearer <access_token>
```

### Contoh Request — Register
```bash
curl -X POST https://your-api.vercel.app/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123","full_name":"Budi Santoso","prodi":"Informatika","angkatan":"2020"}'
```

### Contoh Request — Google Sign-In
```bash
curl -X POST https://your-api.vercel.app/api/auth/google \
  -H "Content-Type: application/json" \
  -d '{"id_token":"<Google_ID_Token>"}'
```
Respons `200 OK` sama persis dengan `POST /api/auth/login`:
```json
{
  "access_token": "...",
  "refresh_token": "...",
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "role": "alumni",
    "full_name": "Budi Santoso",
    "avatar_url": "https://..."
  }
}
```

### Contoh Request — Upload Foto
```bash
curl -X POST https://your-api.vercel.app/api/upload/avatar \
  -H "Authorization: Bearer <token>" \
  -F "file=@/path/to/foto.jpg"
```
