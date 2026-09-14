# Unitas Backend API

REST API untuk **Unitas — Platform Alumni Digital**, dibangun dengan Express.js dan Supabase.

## Stack
- **Runtime**: Node.js 20+
- **Framework**: Express.js
- **Database**: Supabase (PostgreSQL)
- **Auth**: Custom JWT (bcryptjs + jsonwebtoken)
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
# Edit .env dengan kredensial Supabase dan JWT secret kamu
```

### 3. Setup Supabase
- Buka [Supabase Dashboard](https://supabase.com)
- Buat project baru
- Buka **SQL Editor** → paste isi file `supabase/migrations/001_initial_schema.sql` → Run
- Buka **Storage** → buat 2 bucket:
  - `avatars` (public)
  - `post-images` (public)
- Copy **Project URL** dan **service_role key** ke `.env`

### 4. Jalankan Lokal
```bash
npm run dev
# Server berjalan di http://localhost:3000
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
Di Vercel Dashboard → Project → Settings → Environment Variables, tambahkan semua variable dari `.env.example`.

---

## API Endpoints

| Method | Endpoint | Auth | Deskripsi |
|--------|----------|------|-----------|
| GET | `/api/health` | - | Health check |
| **Auth** | | | |
| POST | `/api/auth/register` | - | Daftar akun baru |
| POST | `/api/auth/login` | - | Login |
| POST | `/api/auth/logout` | - | Logout |
| POST | `/api/auth/refresh` | - | Refresh token |
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

### Contoh Request — Upload Foto
```bash
curl -X POST https://your-api.vercel.app/api/upload/avatar \
  -H "Authorization: Bearer <token>" \
  -F "file=@/path/to/foto.jpg"
```
