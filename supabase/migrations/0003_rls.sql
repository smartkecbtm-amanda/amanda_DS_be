-- AMANDA — Row Level Security per peran (Dokumen 05 §2). Penegakan di sisi data, bukan hanya UI.
-- Pola: tabel master dikelola Admin langsung; semua tabel transaksi hanya DIBACA lewat kebijakan di sini
-- dan DITULIS lewat fungsi RPC (0004+). Tidak ada kebijakan insert/update/delete untuk peran non-Admin.
-- Pengawas, PA/KPA, dan Publik membaca angka lewat fungsi laporan/analitik/portal (security definer), bukan tabel.

-- Pembantu: apakah baris berada pada TA sesi aktif
create or replace function amanda.di_ta(p_ta text) returns boolean
language sql stable security definer set search_path = public, amanda as $$ select p_ta is not null and p_ta = amanda.ta() $$;

-- Pembantu lintas tabel (security definer): menghindari rekursi kebijakan kuitansi <-> spj
create or replace function amanda.seksi_kuitansi(p_kuitansi text) returns text
language sql stable security definer set search_path = public, amanda as $$ select seksi_ta_id from kuitansi where id = p_kuitansi $$;
create or replace function amanda.kuitansi_punya_spj_terajukan(p_kuitansi text) returns boolean
language sql stable security definer set search_path = public, amanda as $$ select exists (select 1 from spj where kuitansi_id = p_kuitansi and status <> 'Draft') $$;

do $$ declare t text; begin
  foreach t in array array[
    'sotk','personel','riwayat_pangkat','akun_login','akun_pengawas','subkegiatan','rekening_belanja','jenis_pajak',
    'direktori_transaksional','direktori_transaksional_ref','direktori_rekening_bank','form_dinamis','konfigurasi',
    'tahun_anggaran','seksi_ta','pemetaan_subkegiatan_ta','penugasan_ta','penugasan_delegasi','penugasan_pengawas_ta','register_sk',
    'versi_alokasi','versi_alokasi_rincian','jendela_alokasi','alokasi_subkegiatan','alokasi_rekening','ledger_spd','urut_pergeseran',
    'kuitansi','spj','spj_pajak','spj_rekening_penerima','rentang_penugasan_spj','bku','format_nomor_verifikasi','urut_verifikasi',
    'token_verifikasi_spj','audit_event']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force row level security', t);   -- berlaku juga untuk pemilik tabel (fungsi security definer memakai peran postgres/bypass, lihat 0004)
  end loop;
end $$;

-- ============ MASTER GLOBAL: Admin kelola; peran lain baca seperlunya ============
-- Admin: seluruh operasi
do $$ declare t text; begin
  foreach t in array array['sotk','subkegiatan','rekening_belanja','jenis_pajak','direktori_transaksional','direktori_rekening_bank','konfigurasi']
  loop
    execute format($f$create policy admin_semua on %I for all to authenticated
      using (amanda.peran() = 'admin') with check (amanda.peran() = 'admin')$f$, t);
    execute format('grant select, insert, update, delete on %I to authenticated', t);
  end loop;
end $$;
-- Peran operasional membaca kamus/konfigurasi (isi dropdown, cetak dokumen)
create policy baca_internal on sotk for select to authenticated using (amanda.peran() in ('bendahara','pptk','verifikator','pa_kpa'));
create policy baca_internal on subkegiatan for select to authenticated using (amanda.peran() in ('bendahara','pptk','verifikator','pa_kpa','pengawas'));
create policy baca_internal on rekening_belanja for select to authenticated using (amanda.peran() in ('bendahara','pptk','verifikator'));
create policy baca_internal on jenis_pajak for select to authenticated using (amanda.peran() in ('bendahara','pptk','verifikator'));
create policy baca_internal on konfigurasi for select to authenticated using (amanda.peran() in ('bendahara','pptk','verifikator'));
-- PPTK memakai direktori untuk lookup/auto-fill (nama dari NIP/NIK dan rekening penerima)
create policy baca_pptk on direktori_transaksional for select to authenticated using (amanda.peran() = 'pptk');
create policy baca_pptk on direktori_rekening_bank for select to authenticated using (amanda.peran() = 'pptk');

-- Form dinamis: berversi; Admin hanya menambah versi baru (tanpa ubah/hapus); peran lain membaca yang dibutuhkan
create policy admin_baca on form_dinamis for select to authenticated using (amanda.peran() in ('admin','pptk','verifikator','bendahara','pengawas'));
create policy admin_tambah on form_dinamis for insert to authenticated with check (amanda.peran() = 'admin');
grant select, insert on form_dinamis to authenticated;

-- Personel dan akun: data pribadi hanya Admin. Kolom hash kata sandi tidak pernah dapat dibaca klien.
create policy admin_semua on personel for all to authenticated using (amanda.peran() = 'admin') with check (amanda.peran() = 'admin');
create policy admin_semua on riwayat_pangkat for all to authenticated using (amanda.peran() = 'admin') with check (amanda.peran() = 'admin');
grant select, insert, update, delete on personel, riwayat_pangkat to authenticated;
create policy admin_baca on akun_login for select to authenticated using (amanda.peran() = 'admin');
create policy admin_baca on akun_pengawas for select to authenticated using (amanda.peran() = 'admin');
grant select (id, personel_id, username, auth_user_id, status, failed_attempts, locked, is_admin, dibuat) on akun_login to authenticated;
grant select (id, nama_lengkap, instansi_asal, nomor_surat_tugas, tanggal_surat_tugas, email, tanggal_akhir_akses, auth_user_id, status, failed_attempts, locked)
  on akun_pengawas to authenticated;
create policy admin_baca on direktori_transaksional_ref for select to authenticated using (amanda.peran() = 'admin');
grant select on direktori_transaksional_ref to authenticated;

-- ============ TAHUN ANGGARAN ============
create policy baca on tahun_anggaran for select to authenticated using (amanda.peran() = 'admin' or id = amanda.ta());
-- Pagu Induk tidak tampil bagi PPTK (D05); akses hanya melalui view v_tahun_anggaran. Kolom tersebut tidak diberikan langsung.
grant select (id, tahun, status, mode_apbd_p, tanggal_arsip_terakhir, pernah_transaksi) on tahun_anggaran to authenticated;
create view v_tahun_anggaran as
  select t.id, t.tahun, t.status, t.mode_apbd_p, t.tanggal_arsip_terakhir, t.pernah_transaksi,
         case when amanda.peran() in ('admin','bendahara','verifikator','pa_kpa','pengawas') then t.pagu_induk end as pagu_induk,
         case when amanda.peran() in ('admin','bendahara','verifikator','pa_kpa','pengawas') then t.pagu_induk_perubahan end as pagu_induk_perubahan
  from tahun_anggaran t
  where amanda.peran() = 'admin' or t.id = amanda.ta();
grant select on v_tahun_anggaran to authenticated;

-- Struktur TA: Admin kelola; peran operasional baca dalam TA sesi (PPTK hanya seksinya)
create policy admin_baca on seksi_ta for select to authenticated using (amanda.peran() = 'admin');
create policy baca_ta on seksi_ta for select to authenticated using (amanda.di_ta(ta_id) and (amanda.peran() <> 'pptk' or id = amanda.seksi()));
create policy admin_baca on pemetaan_subkegiatan_ta for select to authenticated using (amanda.peran() = 'admin');
create policy baca_ta on pemetaan_subkegiatan_ta for select to authenticated using (amanda.di_ta(ta_id) and (amanda.peran() <> 'pptk' or seksi_ta_id = amanda.seksi()));
create policy admin_baca on penugasan_ta for select to authenticated using (amanda.peran() = 'admin');
create policy baca_ta on penugasan_ta for select to authenticated using (amanda.di_ta(ta_id) and amanda.peran() in ('bendahara','pptk','verifikator','pa_kpa'));
create policy admin_baca on penugasan_delegasi for select to authenticated using (amanda.peran() = 'admin');
create policy baca_ta on penugasan_delegasi for select to authenticated using (amanda.di_ta(ta_id) and amanda.peran() in ('bendahara','pptk','verifikator','pa_kpa'));
create policy admin_baca on penugasan_pengawas_ta for select to authenticated using (amanda.peran() = 'admin');
create policy admin_baca on register_sk for select to authenticated using (amanda.peran() = 'admin');
create policy admin_baca on format_nomor_verifikasi for select to authenticated using (amanda.peran() = 'admin' or (amanda.di_ta(ta_id) and amanda.peran() in ('pptk','verifikator','bendahara')));
grant select on seksi_ta, pemetaan_subkegiatan_ta, penugasan_ta, penugasan_delegasi, penugasan_pengawas_ta, register_sk, format_nomor_verifikasi to authenticated;

-- ============ ANGKA ANGGARAN (Admin tidak mendapat akses; Pengawas dan PA/KPA lewat laporan/analitik) ============
-- Alokasi subkegiatan: Bendahara dan Verifikator se-TA; PA/KPA sampai subkegiatan; PPTK seksi sendiri
create policy baca on alokasi_subkegiatan for select to authenticated using (
  amanda.di_ta(ta_id) and (
    amanda.peran() in ('bendahara','verifikator','pa_kpa')
    or (amanda.peran() = 'pptk' and exists (select 1 from pemetaan_subkegiatan_ta p where p.id = pemetaan_subkegiatan_id and p.seksi_ta_id = amanda.seksi()))));
-- Alokasi rekening, ledger, versi: tingkat rekening — PA/KPA tidak boleh
create policy baca on alokasi_rekening for select to authenticated using (
  amanda.di_ta(ta_id) and (
    amanda.peran() in ('bendahara','verifikator')
    or (amanda.peran() = 'pptk' and exists (select 1 from pemetaan_subkegiatan_ta p where p.id = pemetaan_subkegiatan_id and p.seksi_ta_id = amanda.seksi()))));
create policy baca on ledger_spd for select to authenticated using (
  amanda.di_ta(ta_id) and (
    amanda.peran() in ('bendahara','verifikator')
    or (amanda.peran() = 'pptk' and exists (select 1 from alokasi_rekening a where a.id = alokasi_rekening_id))));
create policy baca on versi_alokasi for select to authenticated using (amanda.di_ta(ta_id) and amanda.peran() in ('bendahara','verifikator'));
create policy baca on versi_alokasi_rincian for select to authenticated using (exists (select 1 from versi_alokasi v where v.id = versi_id));
create policy baca on jendela_alokasi for select to authenticated using (amanda.di_ta(ta_id) and amanda.peran() in ('bendahara','pptk','verifikator','pa_kpa'));
grant select on alokasi_subkegiatan, alokasi_rekening, ledger_spd, versi_alokasi, versi_alokasi_rincian, jendela_alokasi to authenticated;

-- ============ TRANSAKSI ============
create policy baca on kuitansi for select to authenticated using (
  amanda.di_ta(ta_id) and (
    amanda.peran() = 'bendahara'
    or (amanda.peran() = 'pptk' and seksi_ta_id = amanda.seksi())
    or (amanda.peran() = 'verifikator' and amanda.kuitansi_punya_spj_terajukan(id))));
create policy baca on spj for select to authenticated using (
  amanda.di_ta(ta_id) and (
    amanda.peran() = 'bendahara'
    or (amanda.peran() = 'pptk' and amanda.seksi_kuitansi(kuitansi_id) = amanda.seksi())
    or (amanda.peran() = 'verifikator' and status <> 'Draft')));
create policy baca on spj_pajak for select to authenticated using (exists (select 1 from spj s where s.id = spj_id));
create policy baca on spj_rekening_penerima for select to authenticated using (exists (select 1 from spj s where s.id = spj_id));
create policy baca on rentang_penugasan_spj for select to authenticated using (exists (select 1 from spj s where s.id = spj_id));
create policy baca on bku for select to authenticated using (
  amanda.di_ta(ta_id) and (amanda.peran() in ('bendahara','verifikator')
    or (amanda.peran() = 'pptk' and amanda.seksi_kuitansi(kuitansi_id) = amanda.seksi())));
create policy baca on token_verifikasi_spj for select to authenticated using (
  amanda.di_ta(ta_id) and amanda.peran() in ('verifikator','pptk') and exists (select 1 from spj s where s.id = spj_id));
-- token mentah hanya dikembalikan ke peran yang berhak mencetak (Verifikator; PPTK seksi sendiri setelah disetujui)
grant select on kuitansi, spj, spj_pajak, spj_rekening_penerima, rentang_penugasan_spj, bku, token_verifikasi_spj to authenticated;

-- ============ JEJAK AUDIT (D05 §2): Admin semua; Bendahara aksinya sendiri; PPTK seksinya; Verifikator se-TA; Pengawas TA; PA tidak ============
create policy baca on audit_event for select to authenticated using (
  amanda.peran() = 'admin'
  or (amanda.di_ta(ta_id) and (
        amanda.peran() in ('verifikator','pengawas')
        or (amanda.peran() = 'bendahara' and aktor_id = amanda.personel())
        or (amanda.peran() = 'pptk' and seksi_ta_id = amanda.seksi()))));
grant select on audit_event to authenticated;

-- urut_* hanya internal (tanpa kebijakan = tidak terbaca klien); tiket/sesi tanpa kebijakan.

-- Fungsi pembantu kebijakan harus dapat dijalankan oleh peran yang dievaluasi RLS
grant execute on all functions in schema amanda to authenticated;
