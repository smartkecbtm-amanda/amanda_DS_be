# AMANDA — Backend (`amanda_DS_be`)

Backend aplikasi AMANDA di atas **Supabase** (Postgres + Row Level Security + RPC + satu Edge Function).
Seluruh aturan bisnis ditegakkan di basis data; klien hanya memanggil RPC dan membaca data lewat RLS.

Frontend: [`amanda_DS_fe`](https://github.com/smartkecbtm-amanda/amanda_DS_fe)

## Struktur repo

```
amanda_DS_be/
├─ supabase/
│  ├─ migrations/        Skema dan logika basis data, jalankan berurutan 0001 → 0012
│  ├─ functions/masuk/   Edge Function login (dua langkah: verifikasi, buka sesi)
│  ├─ seed.sql           Data contoh — HANYA untuk uji/lokal
│  ├─ seed/gen_seed.ts   Pembangkit seed.sql (butuh src/data/sampleData.ts dari repo frontend)
│  └─ tests/             Uji basis data (Postgres lokal) + tiruan skema auth Supabase
├─ klien/                Klien TypeScript terketik untuk semua RPC (disalin ke frontend)
├─ docs/
│  └─ PETA_FITUR_KE_RPC.md   Peta fitur/layar → RPC
├─ .env.example
└─ .gitignore
```

## Isi migrasi

| Berkas | Isi |
|---|---|
| `0001_skema` | Skema seluruh tabel |
| `0002_sesi_login` | Login, tiket, sesi satu konteks, kunci 10x gagal |
| `0003_rls` | RLS per peran, hak tabel |
| `0004_master_akun` | Master data dan akun (`adm_*`) |
| `0005_ta_penugasan` | TA, seksi, penugasan, SK, Pengawas per TA, delegasi |
| `0006_penjadwal` | Penutupan delegasi otomatis 23:59 WITA (butuh `pg_cron`) |
| `0007_anggaran_spd` | Jendela waktu, alokasi, Sahkan, SPD (efisiensi/kenaikan/final), pergeseran bernomor, APBD-P |
| `0008_kuitansi_spj_bku` | Kuitansi, SPJ, pajak, rekening penerima, lampiran, pengajuan, bentrok jadwal, verifikasi, token dan nomor, BKU |
| `0009_laporan_analitik_publik` | Laporan a–g dan kustom, drill-down, analitik, heatmap, portal publik, retensi 12 tahun |
| `0010_storage` | Bucket Storage `lampiran-spj` dan `sk` beserta kebijakannya |
| `0011_pengerasan` | Hak eksekusi fungsi `amanda.*` dicabut (hanya helper kebijakan RLS/Storage yang diberi); pembatasan laju login (`percobaan_masuk`, `cek_laju_masuk`) |
| `0012_lampiran_status_jujur` | Status optimasi lampiran dicatat jujur: berkas > 5 MB tanpa kompresi sungguhan dicatat `FAILED` (disimpan utuh) |

Urutan: jalankan 0001 → 0012 apa adanya. `0012` mengatur hak eksekusinya sendiri (revoke/grant eksplisit pada
`public.pptk_spj_lampiran`), sehingga `0011` tidak perlu dijalankan ulang setelahnya. Bila kelak menambah fungsi di skema
`amanda`, jalankan ulang bagian GRANT di `0011`.

## Pemasangan di proyek Supabase

1. Buat proyek (wilayah Singapura). Simpan kata sandi database.
2. **SQL Editor**: jalankan berurutan semua berkas `supabase/migrations/` (0001 → 0012).
   Jalankan `supabase/seed.sql` hanya bila ingin data contoh (lihat peringatan keamanan di bawah).
3. **Authentication → Sign In / Providers**: matikan "Allow new users to sign up".
4. **Database → Extensions**: aktifkan `pg_cron`. Tanpa ini `0006` dilewati dan delegasi tidak berakhir otomatis.
5. **Edge Function** (butuh Supabase CLI):
   ```bash
   supabase link --project-ref <ref-proyek>
   supabase secrets set ALLOWED_ORIGIN=https://alamat-frontend-anda
   supabase functions deploy masuk --no-verify-jwt
   ```
   `SUPABASE_URL`, `SUPABASE_ANON_KEY`, dan `SUPABASE_SERVICE_ROLE_KEY` disediakan otomatis untuk Edge Function.
   Tanpa `ALLOWED_ORIGIN`, CORS terbuka untuk semua asal (hanya untuk uji).
6. Catat **Project URL** dan **anon public key** (Settings → API) untuk frontend.

## Menyambungkan frontend

Salin isi `klien/` ke frontend (mis. `src/lib/amanda/`) dan isi variabel lingkungan frontend, contoh untuk Vite:

```
VITE_SUPABASE_URL=https://<ref-proyek>.supabase.co
VITE_SUPABASE_ANON_KEY=<anon public key>
```

- `klien/api.ts` — satu fungsi per RPC (`buatApi(klienSupabase)`). Dibangkitkan otomatis dari fungsi basis data; jangan diedit tangan.
- `klien/masuk.ts` — alur login dua langkah lewat Edge Function `masuk`.
- `klien/storage.ts` — unggah/unduh lampiran dan SK.
- `docs/PETA_FITUR_KE_RPC.md` — RPC mana untuk layar mana.

Aksi tulis mengembalikan `{ ok, error? }`. Klien tidak dapat menulis langsung ke tabel.

## Aturan yang ditegakkan di basis data

Kunci akun 10x gagal (kecuali Admin); sesi 1 jam tanpa aktivitas; sesi mengunci satu konteks; pejabat definitif kehilangan
hak transaksi saat delegasi; Admin tanpa angka transaksi; PPTK tanpa Pagu Induk; PA/KPA tanpa tingkat rekening; hash sandi
tak terbaca klien; ledger SPD append-only; satu TA Aktif Penuh; komitmen/realisasi/Sisa SPD Bebas dihitung server dan semua
aksi mengunci baris TA (tidak balapan); gatekeeper (Sahkan + semua seksi seimbang) untuk kuitansi dan SPJ; BKU unik per TA;
nomor verifikasi unik berformat; token lama tidak berlaku saat SPJ dikembalikan; bentrok jadwal NIP/NIK saat pengajuan;
portal publik anonim hanya agregat tanpa nominal; retensi 12 tahun menghapus total tanpa catatan.

## Uji lokal

Butuh `psql` dan server Postgres 15+ lokal. Uji memakai tiruan skema `auth` Supabase (`supabase/tests/00_tiruan_supabase.sql`).

```bash
PGHOST=... PGPORT=... PGUSER=postgres bash supabase/tests/jalankan.sh
# atau satu berkas:
PGHOST=... PGPORT=... PGUSER=postgres bash supabase/tests/jalankan.sh tests/t06_anggaran.sql
```

Tiap berkas uji berjalan pada salinan segar basis data (migrasi + seed). Hasil dinyatakan bersih hanya bila tidak ada baris
`GAGAL` dan tidak ada ERROR SQL (keluaran akhir: `SEMUA UJI BERSIH`).

## Keamanan — baca sebelum mempublikasikan repo

- **`seed.sql` hanya untuk uji.** Semua akun contoh memakai sandi `amanda123`. Jangan jalankan di basis data produksi.
  Bila repo ini publik, siapa pun dapat melihat sandi itu.
- **Jangan pernah meng-commit `service_role` key**, kata sandi database, atau berkas `.env`. Hanya `anon public key` yang
  boleh ada di frontend. `.gitignore` sudah mengecualikan `.env*` (kecuali `.env.example`).
- Pertimbangkan menjadikan repo **private** karena memuat seluruh aturan bisnis dan kebijakan RLS.

## Yang belum diuji / belum ada

- **Belum diuji pada Supabase nyata**: Edge Function `masuk`, `pg_cron` (`0006`), kebijakan Storage (`0010`), dan perilaku
  PostgREST. Basis data diuji pada Postgres lokal.
- **Layar frontend belum tersambung ke backend** (masih memakai data contoh di memori). Penyambungan butuh perubahan
  `repo.ts` dari sinkron ke asinkron dan pembacaan lewat RLS/RPC; paling aman dikerjakan bertahap bersama proyek Supabase yang hidup.
- **Kompresi PDF di server belum ada**: Edge Function tidak dapat menjalankan Ghostscript. Lampiran > 5 MB harus dikompresi
  di peramban sebelum diunggah; basis data menolak > 30 MB dan mencatat status optimasi.
- `supabase/seed/gen_seed.ts` mengimpor `@/data/sampleData` milik frontend, jadi hanya dapat dijalankan dari dalam repo frontend.
