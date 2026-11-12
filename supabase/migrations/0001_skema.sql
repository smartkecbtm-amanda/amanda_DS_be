-- AMANDA — Skema inti (Dokumen 04 v1.38). Postgres / Supabase.
-- Nominal: bigint rupiah tanpa sen. Kode/NIP/NIK/no. rekening: text. Zona waktu: WITA.
-- ID bertipe text agar sejajar dengan data contoh frontend; baris baru memakai uuid acak.
-- Penulisan ke tabel transaksional hanya lewat fungsi RPC (migrasi 0004+); tidak ada kebijakan tulis langsung.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists amanda;       -- fungsi internal, tidak diekspos ke API

create or replace function amanda.hari_ini_wita() returns date
language sql stable as $$ select (now() at time zone 'Asia/Makassar')::date $$;

-- ============ MASTER GLOBAL (D04 §2.1) ============
create table sotk (
  id text primary key default gen_random_uuid()::text,
  nama_unit text not null,
  tmt_mulai date not null,
  tmt_selesai date,
  dasar_hukum text not null default '',
  pengganti_dari_id text references sotk(id),
  status_versi text not null default 'Aktif' check (status_versi in ('Aktif','Diarsipkan'))
);

create table personel (
  id text primary key default gen_random_uuid()::text,
  gelar_depan text not null default '',
  nama text not null check (btrim(nama) <> ''),
  gelar_belakang text not null default '',
  nip text not null default '',
  nik text not null default '',
  pangkat text not null check (btrim(pangkat) <> ''),
  tmt date not null,
  no_whatsapp text not null check (no_whatsapp ~ '^[0-9+]+$'),
  constraint ck_identitas check (nip <> '' or nik <> ''),
  constraint ck_angka check (nip ~ '^[0-9]*$' and nik ~ '^[0-9]*$')
);
-- NIP, atau NIK bila NIP kosong, unik di direktori personel (D04 §3)
create unique index ux_personel_identitas on personel ((coalesce(nullif(nip,''), nik)));

create table riwayat_pangkat (
  id text primary key default gen_random_uuid()::text,
  personel_id text not null references personel(id) on delete cascade,
  pangkat text not null,
  gelar_depan text not null default '',
  gelar_belakang text not null default '',
  tmt_mulai date not null,
  tmt_selesai date
);

-- Akun login internal. Kata sandi disimpan sebagai hash bcrypt (pgcrypto); sesi dikeluarkan Supabase Auth
-- melalui fungsi masuk (Edge Function). auth_user_id terisi saat akun dibuat.
create table akun_login (
  id text primary key default gen_random_uuid()::text,
  personel_id text unique references personel(id),   -- null untuk Admin murni
  username text not null unique,                      -- otomatis dari NIP/NIK
  kata_sandi_hash text not null,
  auth_user_id uuid unique,
  status text not null default 'ACTIVE' check (status in ('Belum Ada Akun','ACTIVE','NON-ACTIVE')),
  failed_attempts int not null default 0,
  locked boolean not null default false,
  is_admin boolean not null default false,
  dibuat timestamptz not null default now()
);

create table akun_pengawas (
  id text primary key default gen_random_uuid()::text,
  nama_lengkap text not null,
  instansi_asal text not null,
  nomor_surat_tugas text not null,
  tanggal_surat_tugas date not null,
  email text not null unique,
  tanggal_akhir_akses date not null,
  kata_sandi_hash text not null,
  auth_user_id uuid unique,
  status text not null default 'ACTIVE' check (status in ('Belum Ada Akun','ACTIVE','NON-ACTIVE')),
  failed_attempts int not null default 0,
  locked boolean not null default false
);

create table subkegiatan (
  id text primary key default gen_random_uuid()::text,
  kode text not null,
  nama text not null,
  rincian text not null default '',
  status text not null default 'Aktif' check (status in ('Aktif','Nonaktif'))
);

create table rekening_belanja (
  id text primary key default gen_random_uuid()::text,
  kode_rekening text not null,
  nama text not null,
  rincian text not null default '',
  status text not null default 'Aktif' check (status in ('Aktif','Nonaktif'))
);

create table jenis_pajak (
  id text primary key default gen_random_uuid()::text,
  kode text,
  nama_jenis_pajak text not null,
  status text not null default 'Aktif' check (status in ('Aktif','Nonaktif'))
);

create table direktori_transaksional (
  id text primary key default gen_random_uuid()::text,
  nip_nik text not null unique,
  nama text not null
);
create table direktori_transaksional_ref (
  direktori_id text not null references direktori_transaksional(id) on delete cascade,
  spj_id text not null,
  primary key (direktori_id, spj_id)
);

create table direktori_rekening_bank (
  id text primary key default gen_random_uuid()::text,
  account_name text not null,
  bank_name text not null,
  account_number text not null,
  alias text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Form dinamis berversi: setiap perubahan membentuk versi baru (tidak menimpa)
create table form_dinamis (
  id text primary key default gen_random_uuid()::text,
  jenis_belanja text not null,
  versi text not null,
  fields jsonb not null default '[]',
  blok_berulang jsonb,
  tanggal_dibuat date not null default amanda.hari_ini_wita(),
  unique (jenis_belanja, versi)
);

-- Template kuitansi / template Hasil Verifikasi: teks konfigurasi (kunci: 'template_kuitansi', 'template_verifikasi')
create table konfigurasi (
  kunci text primary key,
  nilai jsonb not null,
  diubah timestamptz not null default now()
);

-- ============ WORKSPACE TA (D04 §2.2) ============
create table tahun_anggaran (
  id text primary key default gen_random_uuid()::text,
  tahun text not null unique,
  pagu_induk bigint not null check (pagu_induk >= 0),
  status text not null default 'Draft' check (status in ('Draft','Aktif Penuh','Masa Transisi','Arsip Read-Only')),
  mode_apbd_p boolean not null default false,
  pagu_induk_perubahan bigint check (pagu_induk_perubahan is null or pagu_induk_perubahan >= 0),
  tanggal_arsip_terakhir date,
  pernah_transaksi boolean not null default false
);
-- paling banyak satu TA Aktif Penuh pada satu waktu
create unique index ux_ta_aktif_penuh on tahun_anggaran ((status)) where status = 'Aktif Penuh';

create table seksi_ta (
  id text primary key default gen_random_uuid()::text,
  ta_id text not null references tahun_anggaran(id) on delete cascade,
  sotk_id text not null references sotk(id),
  nama_snapshot text not null,
  tmt_mulai date not null,
  tmt_selesai date,
  status text not null default 'Aktif' check (status in ('Aktif','Diarsipkan'))
);
create index on seksi_ta (ta_id);

create table pemetaan_subkegiatan_ta (
  id text primary key default gen_random_uuid()::text,
  ta_id text not null references tahun_anggaran(id) on delete cascade,
  seksi_ta_id text not null references seksi_ta(id) on delete cascade,
  subkegiatan_id text not null references subkegiatan(id),
  kode_snapshot text not null,
  nama_snapshot text not null,
  unique (ta_id, subkegiatan_id)            -- satu subkegiatan hanya untuk satu seksi per TA
);
create index on pemetaan_subkegiatan_ta (seksi_ta_id);

create table penugasan_ta (
  id text primary key default gen_random_uuid()::text,
  ta_id text not null references tahun_anggaran(id) on delete cascade,
  peran text not null check (peran in ('pa_kpa','bendahara','verifikator','pptk')),
  personel_id text not null references personel(id),
  seksi_ta_id text references seksi_ta(id) on delete cascade,
  tmt_mulai date not null,
  tmt_selesai date,
  provisional boolean not null default false,
  nama_snapshot text not null,
  nip_snapshot text not null,
  check ((peran = 'pptk') = (seksi_ta_id is not null))
);
create index on penugasan_ta (ta_id, peran);
create index on penugasan_ta (personel_id);

create table penugasan_delegasi (
  id text primary key default gen_random_uuid()::text,
  ta_id text not null references tahun_anggaran(id) on delete cascade,
  personel_pengganti_id text not null references personel(id),
  peran_digantikan text not null check (peran_digantikan in ('pa_kpa','bendahara','pptk')),
  seksi_ta_id text references seksi_ta(id) on delete cascade,
  tanggal_mulai date not null,
  tanggal_berakhir date not null,
  status text not null default 'Delegasi Aktif' check (status in ('Delegasi Aktif','Berakhir','Dicabut')),
  alasan_pencabutan text,
  definitive_officer_id text not null references personel(id),
  nama_snapshot text not null,
  nip_snapshot text not null,
  check (tanggal_berakhir >= tanggal_mulai),
  check ((peran_digantikan = 'pptk') = (seksi_ta_id is not null))
);
create index on penugasan_delegasi (ta_id, status);

create table penugasan_pengawas_ta (
  id text primary key default gen_random_uuid()::text,
  ta_id text not null references tahun_anggaran(id) on delete cascade,
  pengawas_id text not null references akun_pengawas(id),
  tanggal_mulai date not null,
  tanggal_akhir date not null,
  check (tanggal_akhir >= tanggal_mulai)
);
create index on penugasan_pengawas_ta (pengawas_id);

create table register_sk (
  id text primary key default gen_random_uuid()::text,
  penugasan_id text not null references penugasan_ta(id) on delete cascade,
  nomor_sk text not null default '',
  tanggal_sk date,
  berkas_key text,                 -- kunci objek Storage (PDF/JPG/PNG, maks 5 MB)
  berkas_nama text,
  berkas_ukuran int,
  provisional boolean not null default false,
  check (provisional or (nomor_sk <> '' and tanggal_sk is not null and berkas_key is not null))
);

-- Versi alokasi: berhistori, tidak menimpa jejak lama
create table versi_alokasi (
  id text primary key default gen_random_uuid()::text,
  ta_id text not null references tahun_anggaran(id) on delete cascade,
  fase text not null check (fase in ('murni','perubahan','pergeseran')),
  tanggal_efektif timestamptz not null default now(),
  aktor_id text not null,
  aktor_nama_snapshot text not null,
  aktor_peran_snapshot text not null,
  keterangan text not null default ''
);
create index on versi_alokasi (ta_id);
create table versi_alokasi_rincian (
  versi_id text not null references versi_alokasi(id) on delete cascade,
  pemetaan_subkegiatan_id text not null,
  rekening_id text,                -- null = baris pagu subkegiatan
  pagu bigint not null check (pagu >= 0)
);
create index on versi_alokasi_rincian (versi_id);

create table jendela_alokasi (
  ta_id text primary key references tahun_anggaran(id) on delete cascade,
  tutup_at timestamptz             -- null = belum dibuka
);

create table alokasi_subkegiatan (
  id text primary key default gen_random_uuid()::text,
  ta_id text not null references tahun_anggaran(id) on delete cascade,
  pemetaan_subkegiatan_id text not null unique references pemetaan_subkegiatan_ta(id) on delete cascade,
  pagu bigint not null check (pagu >= 0)
);
create index on alokasi_subkegiatan (ta_id);

create table alokasi_rekening (
  id text primary key default gen_random_uuid()::text,
  ta_id text not null references tahun_anggaran(id) on delete cascade,
  pemetaan_subkegiatan_id text not null references pemetaan_subkegiatan_ta(id) on delete cascade,
  rekening_id text not null references rekening_belanja(id),
  kode_rekening_snapshot text not null,
  nama_rekening_snapshot text not null,
  pagu bigint not null check (pagu >= 0),
  disahkan boolean not null default false,
  spd_aktif bigint not null default 0 check (spd_aktif >= 0),
  unique (ta_id, pemetaan_subkegiatan_id, rekening_id),
  check (spd_aktif <= pagu)
);
create index on alokasi_rekening (ta_id);

-- Ledger SPD: append-only (D04 §2.2). Penghapusan hanya saat retensi TA (set amanda.retensi=1).
create table ledger_spd (
  id text primary key default gen_random_uuid()::text,
  ta_id text not null references tahun_anggaran(id) on delete cascade,
  alokasi_rekening_id text not null references alokasi_rekening(id) on delete cascade,
  jenis text not null check (jenis in ('terbit','efisiensi','kenaikan','penyesuaian_apbdp','pergeseran')),
  perubahan bigint not null,
  spd_sesudah bigint not null check (spd_sesudah >= 0),
  keterangan text not null default '',
  waktu timestamptz not null default now(),
  aktor_id text not null,
  aktor_nama_snapshot text not null,
  aktor_peran_snapshot text not null,
  referensi text
);
create index on ledger_spd (alokasi_rekening_id);

-- Nomor pergeseran otomatis Pergeseran/{urut 3 digit}/{tahun TA}
create table urut_pergeseran (ta_id text primary key references tahun_anggaran(id) on delete cascade, terakhir int not null default 0);

-- ============ TRANSAKSI ============
create table kuitansi (
  id text primary key default gen_random_uuid()::text,
  ta_id text not null references tahun_anggaran(id) on delete cascade,
  seksi_ta_id text not null references seksi_ta(id),
  pemetaan_subkegiatan_id text not null references pemetaan_subkegiatan_ta(id),
  rekening_id text not null references rekening_belanja(id),
  penerima text not null,
  bruto bigint not null check (bruto > 0),
  uraian text not null default '',
  tanggal_kuitansi date not null,
  status text not null default 'Aktif' check (status in ('Aktif','Terkunci')),
  pa_kpa_nama text not null, pa_kpa_nip text not null,
  bendahara_nama text not null, bendahara_nip text not null,
  pptk_nama text not null, pptk_nip text not null,
  versi_alokasi_snapshot_id text references versi_alokasi(id)
);
create index on kuitansi (ta_id, seksi_ta_id);

create table spj (
  id text primary key default gen_random_uuid()::text,
  ta_id text not null references tahun_anggaran(id) on delete cascade,
  kuitansi_id text not null unique references kuitansi(id) on delete cascade,   -- 1:1
  jenis_belanja text not null,
  versi_form text not null,
  jawaban jsonb not null default '{}',
  status text not null default 'Draft' check (status in ('Draft','Terkunci','Menunggu BKU','Dibukukan')),
  catatan_revisi text,
  dikembalikan boolean not null default false,       -- pembeda Draf persiapan vs perlu perbaikan (D04 §2.3)
  tanggal_pengajuan date,
  penandatangan_pengajuan jsonb,
  lampiran_key text,
  lampiran_nama_asli text,
  lampiran_ukuran_asal bigint,
  lampiran_ukuran_final bigint,
  lampiran_status_optimasi text check (lampiran_status_optimasi in ('BYPASSED','CLIENT_COMPRESSED','SERVER_FALLBACK_COMPRESSED','FAILED'))
);
create index on spj (ta_id, status);

create table spj_pajak (
  id text primary key default gen_random_uuid()::text,
  spj_id text not null references spj(id) on delete cascade,
  jenis_pajak_id text not null references jenis_pajak(id),
  nominal bigint not null check (nominal >= 0)
);
create table spj_rekening_penerima (      -- snapshot immutable (D04 §6.1)
  id text primary key default gen_random_uuid()::text,
  spj_id text not null references spj(id) on delete cascade,
  account_name text not null, bank_name text not null, account_number text not null, alias text
);

-- Rentang penugasan SPJ untuk validasi bentrok jadwal (hanya saat pengajuan)
create table rentang_penugasan_spj (
  id text primary key default gen_random_uuid()::text,
  ta_id text not null references tahun_anggaran(id) on delete cascade,
  spj_id text not null references spj(id) on delete cascade,
  nip_nik text not null,
  mulai date not null,
  selesai date not null,
  check (selesai >= mulai)
);
create index on rentang_penugasan_spj (ta_id, nip_nik);

create table bku (
  id text primary key default gen_random_uuid()::text,
  ta_id text not null references tahun_anggaran(id) on delete cascade,
  kuitansi_id text not null references kuitansi(id) on delete cascade,
  spj_id text not null references spj(id) on delete cascade,
  nomor_bku text not null check (btrim(nomor_bku) <> ''),
  tanggal_bku date not null,
  status text not null default 'Aktif' check (status in ('Aktif','Dicabut'))
);
create unique index ux_bku_nomor_aktif on bku (ta_id, nomor_bku) where status = 'Aktif';
create unique index ux_bku_kuitansi_aktif on bku (kuitansi_id) where status = 'Aktif';

create table format_nomor_verifikasi (
  ta_id text primary key references tahun_anggaran(id) on delete cascade,
  awalan text not null default 'VER',
  pemisah text not null default '/',
  pola_tahun text not null default 'YYYY' check (pola_tahun in ('YYYY','YY','TANPA')),
  digit int not null default 4 check (digit between 1 and 10),
  urutan text not null default 'urut/awalan/tahun'
);
create table urut_verifikasi (ta_id text primary key references tahun_anggaran(id) on delete cascade, terakhir int not null default 0);

create table token_verifikasi_spj (
  id text primary key default gen_random_uuid()::text,
  ta_id text not null references tahun_anggaran(id) on delete cascade,
  spj_id text not null references spj(id) on delete cascade,
  token text not null unique,
  nomor_verifikasi text not null,
  urut int not null,
  tanggal_verifikasi date not null,
  verifikator_nama text not null,
  verifikator_nip text not null,
  status text not null default 'Berlaku' check (status in ('Berlaku','Tidak berlaku')),
  unique (ta_id, nomor_verifikasi),
  unique (ta_id, urut)
);
create index on token_verifikasi_spj (spj_id);

create table audit_event (
  id text primary key default gen_random_uuid()::text,
  ta_id text references tahun_anggaran(id) on delete cascade,
  waktu timestamptz not null default now(),
  aktor_id text not null,
  aktor_nama_snapshot text not null,
  aktor_nip_snapshot text not null default '',
  aktor_peran_snapshot text not null,
  entitas text not null,
  aksi text not null check (aksi in ('sahkan','alokasi_pasca_sahkan','alokasi_apbd_p','verifikasi_setujui','verifikasi_kembalikan',
    'pencatatan_bku','koreksi_bku','pencabutan_bku','delegasi_tetapkan','delegasi_pencabutan_dini','delegasi_berakhir_otomatis',
    'perubahan_status_ta','perubahan_status_akun','aksi_administratif','aksi_pengawas','efisiensi_spd','kenaikan_spd','pergeseran_spd')),
  nilai_sebelum text,
  nilai_sesudah text,
  alasan text,
  otomatis boolean not null default false,
  definitive_officer_id text,
  delegate_officer_id text,
  kuitansi_id text,
  spj_id text,
  seksi_ta_id text            -- untuk pembatasan baca PPTK (entri seksinya sendiri)
);
create index on audit_event (ta_id, waktu desc);
create index on audit_event (kuitansi_id) where kuitansi_id is not null;
create index on audit_event (spj_id) where spj_id is not null;

-- ============ SESI (D04 §3) ============
-- Satu baris per sesi login. Konteks (TA, peran, seksi) dikunci sekali dan tidak dapat diubah.
create table sesi_amanda (
  sesi_id uuid primary key,                 -- = klaim session_id pada JWT Supabase
  tipe text not null check (tipe in ('internal','auditor')),
  akun_id text not null,                    -- akun_login.id atau akun_pengawas.id
  personel_id text,
  ta_id text references tahun_anggaran(id) on delete cascade,
  peran text check (peran in ('admin','bendahara','pptk','verifikator','pa_kpa','pengawas')),
  seksi_ta_id text,
  nama_snapshot text,
  nip_snapshot text,
  dibuat timestamptz not null default now(),
  terakhir_aktif timestamptz not null default now(),
  berakhir timestamptz                      -- diisi saat logout
);
create index on sesi_amanda (akun_id);

-- Larangan ubah/hapus ledger SPD dan nilai riwayat
create or replace function amanda.tolak_ubah() returns trigger language plpgsql as $$
begin
  if current_setting('amanda.retensi', true) = '1' then
    if tg_op = 'DELETE' then return old; end if;
  end if;
  raise exception 'Data % bersifat append-only (tidak boleh diubah atau dihapus).', tg_table_name;
end $$;
create trigger tr_ledger_append_only before update or delete on ledger_spd
  for each row execute function amanda.tolak_ubah();
