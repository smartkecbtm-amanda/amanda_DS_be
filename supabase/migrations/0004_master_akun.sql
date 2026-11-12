-- AMANDA — Langkah 2 (backend): Master Data & Akun. Setiap perubahan Admin memakai fungsi RPC dan otomatis
-- tercatat di Jejak Audit. Penulisan langsung ke tabel master oleh klien dicabut.
-- Rujukan: D01 §1.1–1.2, §8; D03 §2.1; D04 §2.1, §3, §6; D05 §2.

-- ============ PEMBANTU ============
create or replace function amanda.gagal(p text) returns jsonb language sql immutable as $$ select jsonb_build_object('ok', false, 'error', p) $$;

create or replace function amanda.label_peran(p text) returns text language sql immutable as $$
  select case p when 'admin' then 'Administrator' when 'bendahara' then 'Bendahara Pengeluaran' when 'pptk' then 'PPTK/Seksi'
    when 'verifikator' then 'Verifikator' when 'pa_kpa' then 'PA/KPA' when 'pengawas' then 'Pengawas/Auditor' else p end $$;

-- Jejak Audit: aktor selalu dari sesi (tidak dapat dipalsukan klien). Tanpa sesi => efek otomatis sistem.
-- aktor_id: Admin/Pengawas = id akun; personel = id personel (sejajar data contoh).
create or replace function amanda.catat_audit(
  p_ta text, p_entitas text, p_aksi text, p_sebelum text default null, p_sesudah text default null, p_alasan text default null,
  p_otomatis boolean default false, p_kuitansi text default null, p_spj text default null, p_seksi text default null,
  p_definitif text default null, p_delegasi text default null) returns void
language plpgsql volatile security definer set search_path = public, amanda as $$
declare s sesi_amanda := amanda.sesi();
begin
  if s.sesi_id is null then
    insert into audit_event (ta_id, aktor_id, aktor_nama_snapshot, aktor_nip_snapshot, aktor_peran_snapshot, entitas, aksi, nilai_sebelum, nilai_sesudah, alasan, otomatis,
                             definitive_officer_id, delegate_officer_id, kuitansi_id, spj_id, seksi_ta_id)
    values (p_ta, 'system', 'Sistem', '—', 'Otomatis', p_entitas, p_aksi, p_sebelum, p_sesudah, p_alasan, true, p_definitif, p_delegasi, p_kuitansi, p_spj, p_seksi);
  else
    insert into audit_event (ta_id, aktor_id, aktor_nama_snapshot, aktor_nip_snapshot, aktor_peran_snapshot, entitas, aksi, nilai_sebelum, nilai_sesudah, alasan, otomatis,
                             definitive_officer_id, delegate_officer_id, kuitansi_id, spj_id, seksi_ta_id)
    values (p_ta, case when s.peran in ('admin','pengawas') then s.akun_id else coalesce(s.personel_id, s.akun_id) end,
            s.nama_snapshot, coalesce(s.nip_snapshot, '—'), amanda.label_peran(s.peran), p_entitas, p_aksi, p_sebelum, p_sesudah, p_alasan,
            p_otomatis, p_definitif, p_delegasi, p_kuitansi, p_spj, p_seksi);
  end if;
end $$;

create or replace function amanda.bukan_admin() returns boolean language sql stable security definer set search_path = public, amanda as $$
  select amanda.peran() is distinct from 'admin' $$;
create or replace function amanda.sentuh() returns void language sql volatile security definer set search_path = public, amanda as $$
  update sesi_amanda set terakhir_aktif = now() where sesi_id = (amanda.sesi()).sesi_id $$;

-- ============ CABUT TULIS LANGSUNG ATAS TABEL MASTER ============
do $$ declare t text; begin
  foreach t in array array['sotk','subkegiatan','rekening_belanja','jenis_pajak','direktori_transaksional','direktori_rekening_bank','konfigurasi','personel','riwayat_pangkat']
  loop
    execute format('drop policy if exists admin_semua on %I', t);
    execute format('create policy admin_baca on %I for select to authenticated using (amanda.peran() = ''admin'')', t);
    execute format('revoke insert, update, delete on %I from authenticated', t);
  end loop;
end $$;
drop policy if exists admin_tambah on form_dinamis;
revoke insert on form_dinamis from authenticated;

-- ============ MASTER SOTK (MST-01) ============
create or replace function public.adm_sotk_tambah(p_nama text, p_tmt date, p_dasar text default '') returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare id text := gen_random_uuid()::text;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola Master SOTK.'); end if;
  if btrim(coalesce(p_nama,'')) = '' then return amanda.gagal('Nama unit wajib diisi.'); end if;
  if p_tmt is null then return amanda.gagal('TMT mulai wajib diisi.'); end if;
  insert into sotk (id, nama_unit, tmt_mulai, dasar_hukum) values (id, btrim(p_nama), p_tmt, coalesce(p_dasar,''));
  perform amanda.catat_audit(null, 'Master SOTK: ' || btrim(p_nama), 'aksi_administratif', null, 'Unit baru ditambahkan');
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'id', id);
end $$;

-- Perubahan nomenklatur: versi lama ditutup H-1 dan diarsipkan, versi baru Aktif (D04 §2.1)
create or replace function public.adm_sotk_ubah_nomenklatur(p_id text, p_nama_baru text, p_tmt_baru date) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare lama sotk; baru text := gen_random_uuid()::text;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola Master SOTK.'); end if;
  select * into lama from sotk where id = p_id for update;
  if not found then return amanda.gagal('Unit tidak ditemukan.'); end if;
  if lama.status_versi <> 'Aktif' then return amanda.gagal('Hanya versi aktif yang dapat diubah nomenklaturnya.'); end if;
  if btrim(coalesce(p_nama_baru,'')) = '' then return amanda.gagal('Nama unit baru wajib diisi.'); end if;
  if p_tmt_baru is null or p_tmt_baru <= lama.tmt_mulai then return amanda.gagal('TMT baru harus setelah TMT mulai versi lama.'); end if;
  update sotk set tmt_selesai = p_tmt_baru - 1, status_versi = 'Diarsipkan' where id = lama.id;
  insert into sotk (id, nama_unit, tmt_mulai, dasar_hukum, pengganti_dari_id) values (baru, btrim(p_nama_baru), p_tmt_baru, lama.dasar_hukum, lama.id);
  perform amanda.catat_audit(null, 'Master SOTK: ' || lama.nama_unit, 'aksi_administratif', lama.nama_unit,
    btrim(p_nama_baru) || ' (TMT ' || p_tmt_baru || '; lama diarsipkan H-1)');
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'id', baru);
end $$;

create or replace function public.adm_sotk_koreksi_typo(p_id text, p_nama text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare lama text;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola Master SOTK.'); end if;
  if btrim(coalesce(p_nama,'')) = '' then return amanda.gagal('Nama unit wajib diisi.'); end if;
  select nama_unit into lama from sotk where id = p_id;
  if not found then return amanda.gagal('Unit tidak ditemukan.'); end if;
  update sotk set nama_unit = btrim(p_nama) where id = p_id;
  perform amanda.catat_audit(null, 'Master SOTK: ' || btrim(p_nama), 'aksi_administratif', lama, btrim(p_nama));
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.adm_sotk_arsipkan(p_id text, p_tanggal date) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare s sotk;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola Master SOTK.'); end if;
  select * into s from sotk where id = p_id for update;
  if not found then return amanda.gagal('Unit tidak ditemukan.'); end if;
  if p_tanggal is null or p_tanggal < s.tmt_mulai then return amanda.gagal('Tanggal efektif tidak boleh sebelum TMT mulai.'); end if;
  update sotk set tmt_selesai = p_tanggal, status_versi = 'Diarsipkan' where id = p_id;
  perform amanda.catat_audit(null, 'Master SOTK: ' || s.nama_unit, 'aksi_administratif', null, 'Diarsipkan efektif ' || p_tanggal);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- ============ MASTER PERSONEL (MST-02, MST-03) ============
create or replace function amanda.validasi_personel(p jsonb, p_id text) returns text
language plpgsql stable security definer set search_path = public, amanda as $$
declare nip text := btrim(coalesce(p->>'nip','')); nik text := btrim(coalesce(p->>'nik','')); kunci text;
begin
  if btrim(coalesce(p->>'nama','')) = '' then return 'Nama wajib diisi.'; end if;
  if btrim(coalesce(p->>'pangkat','')) = '' then return 'Pangkat/golongan wajib diisi.'; end if;
  if coalesce(p->>'tmt','') = '' then return 'TMT wajib diisi.'; end if;
  if nip = '' and nik = '' then return 'NIP atau NIK wajib diisi.'; end if;
  if nip !~ '^[0-9]*$' or nik !~ '^[0-9]*$' then return 'NIP/NIK hanya boleh berisi angka.'; end if;
  if coalesce(p->>'no_whatsapp','') !~ '^[0-9+]+$' then return 'Nomor WhatsApp wajib diisi (angka, boleh diawali +).'; end if;
  kunci := coalesce(nullif(nip,''), nik);
  if exists (select 1 from personel x where (x.nip = kunci or x.nik = kunci) and x.id is distinct from p_id) then
    return 'Nomor sudah digunakan personel lain.';
  end if;
  return null;
end $$;

create or replace function public.adm_personel_tambah(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare err text; id text := gen_random_uuid()::text;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola personel.'); end if;
  err := amanda.validasi_personel(p, null);
  if err is not null then return amanda.gagal(err); end if;
  insert into personel (id, gelar_depan, nama, gelar_belakang, nip, nik, pangkat, tmt, no_whatsapp)
  values (id, btrim(coalesce(p->>'gelar_depan','')), btrim(p->>'nama'), btrim(coalesce(p->>'gelar_belakang','')),
          btrim(coalesce(p->>'nip','')), btrim(coalesce(p->>'nik','')), btrim(p->>'pangkat'), (p->>'tmt')::date, p->>'no_whatsapp');
  insert into riwayat_pangkat (personel_id, pangkat, gelar_depan, gelar_belakang, tmt_mulai)
  values (id, btrim(p->>'pangkat'), btrim(coalesce(p->>'gelar_depan','')), btrim(coalesce(p->>'gelar_belakang','')), (p->>'tmt')::date);
  perform amanda.catat_audit(null, 'Personel: ' || btrim(p->>'nama'), 'aksi_administratif', null, 'Personel baru');
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'id', id);
end $$;

-- Perbarui profil di tempat (tanpa membuat riwayat pangkat baru). Username akun mengikuti NIP/NIK.
create or replace function public.adm_personel_edit(p_id text, p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare err text; lama personel; baru jsonb;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola personel.'); end if;
  select * into lama from personel where id = p_id for update;
  if not found then return amanda.gagal('Personel tidak ditemukan.'); end if;
  baru := jsonb_build_object('gelar_depan', lama.gelar_depan, 'nama', lama.nama, 'gelar_belakang', lama.gelar_belakang, 'nip', lama.nip, 'nik', lama.nik,
                             'pangkat', lama.pangkat, 'tmt', lama.tmt, 'no_whatsapp', lama.no_whatsapp) || p;
  err := amanda.validasi_personel(baru, p_id);
  if err is not null then return amanda.gagal(err); end if;
  update personel set gelar_depan = btrim(coalesce(baru->>'gelar_depan','')), nama = btrim(baru->>'nama'), gelar_belakang = btrim(coalesce(baru->>'gelar_belakang','')),
    nip = btrim(coalesce(baru->>'nip','')), nik = btrim(coalesce(baru->>'nik','')), pangkat = btrim(baru->>'pangkat'), tmt = (baru->>'tmt')::date,
    no_whatsapp = baru->>'no_whatsapp' where id = p_id;
  update riwayat_pangkat set pangkat = btrim(baru->>'pangkat'), gelar_depan = btrim(coalesce(baru->>'gelar_depan','')), gelar_belakang = btrim(coalesce(baru->>'gelar_belakang',''))
    where personel_id = p_id and tmt_selesai is null;
  update akun_login set username = coalesce(nullif(btrim(coalesce(baru->>'nip','')),''), btrim(baru->>'nik')) where personel_id = p_id;
  perform amanda.catat_audit(null, 'Personel: ' || btrim(baru->>'nama'), 'aksi_administratif', null, 'Profil diperbarui');
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- Perubahan pangkat/gelar berversi: riwayat berjalan ditutup H-1, entri baru dibuka (D04 §3)
create or replace function public.adm_personel_perubahan_pangkat(p_id text, p_pangkat text, p_gelar_depan text, p_gelar_belakang text, p_tmt date) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare per personel;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola personel.'); end if;
  select * into per from personel where id = p_id for update;
  if not found then return amanda.gagal('Personel tidak ditemukan.'); end if;
  if btrim(coalesce(p_pangkat,'')) = '' then return amanda.gagal('Pangkat/golongan wajib diisi.'); end if;
  if p_tmt is null then return amanda.gagal('TMT wajib diisi.'); end if;
  if exists (select 1 from riwayat_pangkat where personel_id = p_id and tmt_selesai is null and tmt_mulai >= p_tmt) then
    return amanda.gagal('TMT baru harus setelah TMT riwayat berjalan.');
  end if;
  update riwayat_pangkat set tmt_selesai = p_tmt - 1 where personel_id = p_id and tmt_selesai is null;
  insert into riwayat_pangkat (personel_id, pangkat, gelar_depan, gelar_belakang, tmt_mulai)
    values (p_id, btrim(p_pangkat), btrim(coalesce(p_gelar_depan,'')), btrim(coalesce(p_gelar_belakang,'')), p_tmt);
  update personel set pangkat = btrim(p_pangkat), gelar_depan = btrim(coalesce(p_gelar_depan,'')), gelar_belakang = btrim(coalesce(p_gelar_belakang,'')), tmt = p_tmt where id = p_id;
  perform amanda.catat_audit(null, 'Pangkat: ' || per.nama, 'aksi_administratif', null, 'Perubahan baru TMT ' || p_tmt || '; histori lama ditutup H-1');
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- ============ AKUN LOGIN (AKN-01, AKN-02) ============
create or replace function public.adm_akun_buat(p_personel_id text, p_sandi text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda, extensions as $$
declare per personel;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola akun.'); end if;
  if length(coalesce(p_sandi,'')) < 6 then return amanda.gagal('Password minimal 6 karakter.'); end if;
  select * into per from personel where id = p_personel_id;
  if not found then return amanda.gagal('Personel tidak ditemukan.'); end if;
  if exists (select 1 from akun_login where personel_id = p_personel_id) then return amanda.gagal('Akun sudah ada.'); end if;
  insert into akun_login (personel_id, username, kata_sandi_hash) values (p_personel_id, coalesce(nullif(per.nip,''), per.nik), crypt(p_sandi, gen_salt('bf')));
  perform amanda.catat_audit(null, 'Akun: ' || per.nama, 'aksi_administratif', null, 'Akun dibuat');
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- Reset kata sandi (Admin lupa kata sandi dipulihkan lewat backend/pemilik, bukan fitur ini). Membuka kunci dan mengakhiri sesi lama.
create or replace function public.adm_akun_reset_sandi(p_akun_id text, p_sandi text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda, extensions as $$
declare a akun_login; v_nama text;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola akun.'); end if;
  if length(coalesce(p_sandi,'')) < 6 then return amanda.gagal('Password minimal 6 karakter.'); end if;
  select * into a from akun_login where id = p_akun_id for update;
  if not found then return amanda.gagal('Akun tidak ditemukan.'); end if;
  update akun_login set kata_sandi_hash = crypt(p_sandi, gen_salt('bf')), failed_attempts = 0, locked = false where id = a.id;
  update sesi_amanda set berakhir = now() where akun_id = a.id and berakhir is null and sesi_id is distinct from (amanda.sesi()).sesi_id;
  select coalesce((select pe.nama from personel pe where pe.id = a.personel_id), a.username) into v_nama;
  perform amanda.catat_audit(null, 'Akun: ' || v_nama, 'aksi_administratif', null, 'Password direset');
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- Dampak penonaktifan: penugasan aktif yang masih melekat pada akun (AKN-03)
create or replace function public.adm_akun_dampak(p_akun_id text) returns jsonb
language sql stable security definer set search_path = public, amanda as $$
  select case when amanda.bukan_admin() then '[]'::jsonb else coalesce((
    select jsonb_agg(jsonb_build_object('tahun', ta.tahun, 'peran', t.peran, 'seksi', s.nama_snapshot) order by ta.tahun desc, t.peran)
    from akun_login a join penugasan_ta t on t.personel_id = a.personel_id and t.tmt_selesai is null
    join tahun_anggaran ta on ta.id = t.ta_id left join seksi_ta s on s.id = t.seksi_ta_id where a.id = p_akun_id), '[]'::jsonb) end $$;

create or replace function public.adm_akun_set_status(p_akun_id text, p_status text, p_alasan text default null) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare a akun_login; v_nama text;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola akun.'); end if;
  if p_status not in ('ACTIVE','NON-ACTIVE') then return amanda.gagal('Status tidak dikenal.'); end if;
  select * into a from akun_login where id = p_akun_id for update;
  if not found then return amanda.gagal('Akun tidak ditemukan.'); end if;
  if a.status = p_status then return amanda.gagal('Akun sudah berstatus ' || p_status || '.'); end if;
  if p_status = 'NON-ACTIVE' then
    if btrim(coalesce(p_alasan,'')) = '' then return amanda.gagal('Alasan penonaktifan wajib diisi.'); end if;
    if a.id = amanda.akun() then return amanda.gagal('Anda tidak dapat menonaktifkan akun Anda sendiri.'); end if;
    if a.is_admin and not exists (select 1 from akun_login x where x.is_admin and x.status = 'ACTIVE' and x.id <> a.id) then
      return amanda.gagal('Tidak dapat menonaktifkan Admin aktif terakhir.');
    end if;
  end if;
  update akun_login set status = p_status where id = a.id;   -- NON-ACTIVE memutus sesi (amanda.sesi) tanpa mengubah penugasan
  select coalesce((select pe.nama from personel pe where pe.id = a.personel_id), a.username) into v_nama;
  perform amanda.catat_audit(null, 'Akun: ' || v_nama, 'perubahan_status_akun', a.status, p_status, nullif(btrim(coalesce(p_alasan,'')),''));
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- ============ AKUN PENGAWAS (AKN-04) ============
create or replace function public.adm_pengawas_tambah(p jsonb, p_sandi text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda, extensions as $$
declare id text := gen_random_uuid()::text;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola akun.'); end if;
  if length(coalesce(p_sandi,'')) < 6 then return amanda.gagal('Password minimal 6 karakter.'); end if;
  if btrim(coalesce(p->>'nama_lengkap','')) = '' or btrim(coalesce(p->>'instansi_asal','')) = '' then return amanda.gagal('Nama lengkap dan instansi asal wajib diisi.'); end if;
  if btrim(coalesce(p->>'nomor_surat_tugas','')) = '' then return amanda.gagal('Nomor surat tugas wajib diisi.'); end if;
  if coalesce(p->>'tanggal_surat_tugas','') = '' or coalesce(p->>'tanggal_akhir_akses','') = '' then return amanda.gagal('Tanggal surat tugas dan tanggal akhir akses wajib diisi.'); end if;
  if coalesce(p->>'email','') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return amanda.gagal('Email tidak valid.'); end if;
  if exists (select 1 from akun_pengawas where lower(email) = lower(p->>'email')) then return amanda.gagal('Email sudah digunakan.'); end if;
  insert into akun_pengawas (id, nama_lengkap, instansi_asal, nomor_surat_tugas, tanggal_surat_tugas, email, tanggal_akhir_akses, kata_sandi_hash)
  values (id, btrim(p->>'nama_lengkap'), btrim(p->>'instansi_asal'), btrim(p->>'nomor_surat_tugas'), (p->>'tanggal_surat_tugas')::date,
          lower(btrim(p->>'email')), (p->>'tanggal_akhir_akses')::date, crypt(p_sandi, gen_salt('bf')));
  perform amanda.catat_audit(null, 'Akun Pengawas: ' || btrim(p->>'nama_lengkap'), 'aksi_administratif', null, 'Akun dibuat');
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'id', id);
end $$;

-- Perpanjang/ubah tanggal akhir akses mewajibkan alasan dan tercatat (nilai lama -> baru)
create or replace function public.adm_pengawas_edit(p_id text, p jsonb, p_alasan text default null) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare a akun_pengawas; baru jsonb; tgl_baru date;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola akun.'); end if;
  select * into a from akun_pengawas where id = p_id for update;
  if not found then return amanda.gagal('Akun tidak ditemukan.'); end if;
  baru := jsonb_build_object('nama_lengkap', a.nama_lengkap, 'instansi_asal', a.instansi_asal, 'nomor_surat_tugas', a.nomor_surat_tugas,
    'tanggal_surat_tugas', a.tanggal_surat_tugas, 'email', a.email, 'tanggal_akhir_akses', a.tanggal_akhir_akses) || p;
  if btrim(baru->>'nama_lengkap') = '' or btrim(baru->>'instansi_asal') = '' or btrim(baru->>'nomor_surat_tugas') = '' then
    return amanda.gagal('Nama, instansi, dan nomor surat tugas wajib diisi.'); end if;
  if baru->>'email' !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return amanda.gagal('Email tidak valid.'); end if;
  if exists (select 1 from akun_pengawas where lower(email) = lower(baru->>'email') and id <> p_id) then return amanda.gagal('Email sudah digunakan.'); end if;
  tgl_baru := (baru->>'tanggal_akhir_akses')::date;
  if tgl_baru is distinct from a.tanggal_akhir_akses and btrim(coalesce(p_alasan,'')) = '' then
    return amanda.gagal('Alasan perubahan tanggal akhir akses wajib diisi.'); end if;
  update akun_pengawas set nama_lengkap = btrim(baru->>'nama_lengkap'), instansi_asal = btrim(baru->>'instansi_asal'),
    nomor_surat_tugas = btrim(baru->>'nomor_surat_tugas'), tanggal_surat_tugas = (baru->>'tanggal_surat_tugas')::date,
    email = lower(btrim(baru->>'email')), tanggal_akhir_akses = tgl_baru where id = p_id;
  if tgl_baru is distinct from a.tanggal_akhir_akses then
    perform amanda.catat_audit(null, 'Akun Pengawas: ' || a.nama_lengkap, 'aksi_administratif', a.tanggal_akhir_akses::text, tgl_baru::text, btrim(p_alasan));
  else
    perform amanda.catat_audit(null, 'Akun Pengawas: ' || a.nama_lengkap, 'aksi_administratif', null, 'Profil diperbarui');
  end if;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.adm_pengawas_reset_sandi(p_id text, p_sandi text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda, extensions as $$
declare a akun_pengawas;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola akun.'); end if;
  if length(coalesce(p_sandi,'')) < 6 then return amanda.gagal('Password minimal 6 karakter.'); end if;
  select * into a from akun_pengawas where id = p_id for update;
  if not found then return amanda.gagal('Akun tidak ditemukan.'); end if;
  update akun_pengawas set kata_sandi_hash = crypt(p_sandi, gen_salt('bf')), failed_attempts = 0, locked = false where id = p_id;
  update sesi_amanda set berakhir = now() where akun_id = p_id and berakhir is null;
  perform amanda.catat_audit(null, 'Akun Pengawas: ' || a.nama_lengkap, 'aksi_administratif', null, 'Password direset');
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.adm_pengawas_set_status(p_id text, p_status text, p_alasan text default null) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare a akun_pengawas;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola akun.'); end if;
  if p_status not in ('ACTIVE','NON-ACTIVE') then return amanda.gagal('Status tidak dikenal.'); end if;
  select * into a from akun_pengawas where id = p_id for update;
  if not found then return amanda.gagal('Akun tidak ditemukan.'); end if;
  if a.status = p_status then return amanda.gagal('Akun sudah berstatus ' || p_status || '.'); end if;
  if p_status = 'NON-ACTIVE' and btrim(coalesce(p_alasan,'')) = '' then return amanda.gagal('Alasan penonaktifan wajib diisi.'); end if;
  update akun_pengawas set status = p_status where id = p_id;
  perform amanda.catat_audit(null, 'Akun Pengawas: ' || a.nama_lengkap, 'perubahan_status_akun', a.status, p_status, nullif(btrim(coalesce(p_alasan,'')),''));
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- ============ MASTER SUBKEGIATAN, REKENING, JENIS PAJAK (MST-05, MST-06) ============
-- p_id null = tambah. Perubahan master tidak mengubah snapshot TA yang sudah dibuat (D01 §1.1).
create or replace function public.adm_subkegiatan_simpan(p_id text, p_kode text, p_nama text, p_rincian text default '', p_status text default 'Aktif') returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare nid text := coalesce(p_id, gen_random_uuid()::text);
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola master.'); end if;
  if btrim(coalesce(p_kode,'')) = '' or btrim(coalesce(p_nama,'')) = '' then return amanda.gagal('Kode dan nama subkegiatan wajib diisi.'); end if;
  if p_status not in ('Aktif','Nonaktif') then return amanda.gagal('Status tidak dikenal.'); end if;
  if p_id is null then
    insert into subkegiatan (id, kode, nama, rincian, status) values (nid, btrim(p_kode), btrim(p_nama), coalesce(p_rincian,''), p_status);
    perform amanda.catat_audit(null, 'Subkegiatan: ' || btrim(p_nama), 'aksi_administratif', null, 'Ditambahkan');
  else
    update subkegiatan set kode = btrim(p_kode), nama = btrim(p_nama), rincian = coalesce(p_rincian,''), status = p_status where id = p_id;
    if not found then return amanda.gagal('Subkegiatan tidak ditemukan.'); end if;
    perform amanda.catat_audit(null, 'Subkegiatan: ' || btrim(p_nama), 'aksi_administratif', null, 'Diperbarui');
  end if;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'id', nid);
end $$;

create or replace function public.adm_rekening_simpan(p_id text, p_kode text, p_nama text, p_rincian text default '', p_status text default 'Aktif') returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare nid text := coalesce(p_id, gen_random_uuid()::text);
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola master.'); end if;
  if btrim(coalesce(p_kode,'')) = '' or btrim(coalesce(p_nama,'')) = '' then return amanda.gagal('Kode rekening dan nama wajib diisi.'); end if;
  if p_status not in ('Aktif','Nonaktif') then return amanda.gagal('Status tidak dikenal.'); end if;
  if p_id is null then
    insert into rekening_belanja (id, kode_rekening, nama, rincian, status) values (nid, btrim(p_kode), btrim(p_nama), coalesce(p_rincian,''), p_status);
    perform amanda.catat_audit(null, 'Rekening: ' || btrim(p_nama), 'aksi_administratif', null, 'Ditambahkan');
  else
    update rekening_belanja set kode_rekening = btrim(p_kode), nama = btrim(p_nama), rincian = coalesce(p_rincian,''), status = p_status where id = p_id;
    if not found then return amanda.gagal('Rekening tidak ditemukan.'); end if;
    perform amanda.catat_audit(null, 'Rekening: ' || btrim(p_nama), 'aksi_administratif', null, 'Diperbarui');
  end if;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'id', nid);
end $$;

create or replace function public.adm_jenis_pajak_simpan(p_id text, p_kode text, p_nama text, p_status text default 'Aktif') returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare nid text := coalesce(p_id, gen_random_uuid()::text);
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola master.'); end if;
  if btrim(coalesce(p_nama,'')) = '' then return amanda.gagal('Nama jenis pajak wajib diisi.'); end if;
  if p_status not in ('Aktif','Nonaktif') then return amanda.gagal('Status tidak dikenal.'); end if;
  if p_id is null then
    insert into jenis_pajak (id, kode, nama_jenis_pajak, status) values (nid, nullif(btrim(coalesce(p_kode,'')),''), btrim(p_nama), p_status);
    perform amanda.catat_audit(null, 'Pajak: ' || btrim(p_nama), 'aksi_administratif', null, 'Ditambahkan');
  else
    update jenis_pajak set kode = nullif(btrim(coalesce(p_kode,'')),''), nama_jenis_pajak = btrim(p_nama), status = p_status where id = p_id;
    if not found then return amanda.gagal('Jenis pajak tidak ditemukan.'); end if;
    perform amanda.catat_audit(null, 'Pajak: ' || btrim(p_nama), 'aksi_administratif', null, 'Diperbarui');
  end if;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'id', nid);
end $$;

create or replace function public.adm_jenis_pajak_toggle(p_id text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare j jenis_pajak; baru text;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola master.'); end if;
  select * into j from jenis_pajak where id = p_id for update;
  if not found then return amanda.gagal('Jenis pajak tidak ditemukan.'); end if;
  baru := case j.status when 'Aktif' then 'Nonaktif' else 'Aktif' end;
  update jenis_pajak set status = baru where id = p_id;
  perform amanda.catat_audit(null, 'Pajak: ' || j.nama_jenis_pajak, 'aksi_administratif', null, case baru when 'Aktif' then 'Diaktifkan' else 'Dinonaktifkan' end);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'status', baru);
end $$;

-- ============ DIREKTORI (BNT-01, REK-05) ============
create or replace function public.adm_direktori_koreksi(p_id text, p_nip_nik text, p_nama text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare d direktori_transaksional; kunci text := btrim(coalesce(p_nip_nik,''));
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola Direktori Transaksional.'); end if;
  if kunci = '' or btrim(coalesce(p_nama,'')) = '' then return amanda.gagal('NIP/NIK dan nama wajib diisi.'); end if;
  select * into d from direktori_transaksional where id = p_id for update;
  if not found then return amanda.gagal('Entri tidak ditemukan.'); end if;
  if exists (select 1 from direktori_transaksional where nip_nik = kunci and id <> p_id) then return amanda.gagal('NIP/NIK sudah ada di direktori. Gunakan Gabungkan.'); end if;
  update direktori_transaksional set nip_nik = kunci, nama = btrim(p_nama) where id = p_id;
  perform amanda.catat_audit(null, 'Direktori: ' || d.nama, 'aksi_administratif', d.nip_nik, kunci || ' / ' || btrim(p_nama));
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.adm_direktori_gabung(p_keep text, p_drop text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare k direktori_transaksional; d direktori_transaksional;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola Direktori Transaksional.'); end if;
  if p_keep = p_drop then return amanda.gagal('Pilih dua entri yang berbeda.'); end if;
  select * into k from direktori_transaksional where id = p_keep for update;
  select * into d from direktori_transaksional where id = p_drop for update;
  if k.id is null or d.id is null then return amanda.gagal('Entri tidak ditemukan.'); end if;
  insert into direktori_transaksional_ref (direktori_id, spj_id) select p_keep, spj_id from direktori_transaksional_ref where direktori_id = p_drop on conflict do nothing;
  delete from direktori_transaksional where id = p_drop;       -- referensi lama ikut terhapus (cascade)
  perform amanda.catat_audit(null, 'Direktori: ' || d.nama, 'aksi_administratif', d.nip_nik, 'Digabung ke ' || k.nama || ' (' || k.nip_nik || ')');
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.adm_rekening_bank_koreksi(p_id text, p_nama text, p_bank text, p_nomor text, p_alias text default null) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare r direktori_rekening_bank;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola Direktori Rekening Bank.'); end if;
  if btrim(coalesce(p_nama,'')) = '' or btrim(coalesce(p_bank,'')) = '' or btrim(coalesce(p_nomor,'')) = '' then
    return amanda.gagal('Nama penerima, nama bank, dan nomor rekening wajib diisi.'); end if;
  select * into r from direktori_rekening_bank where id = p_id for update;
  if not found then return amanda.gagal('Entri direktori tidak ditemukan.'); end if;
  -- hanya memengaruhi pencarian ke depan; snapshot rekening pada SPJ tidak berubah (O-114)
  update direktori_rekening_bank set account_name = btrim(p_nama), bank_name = btrim(p_bank), account_number = btrim(p_nomor),
    alias = nullif(btrim(coalesce(p_alias,'')),''), updated_at = now() where id = p_id;
  perform amanda.catat_audit(null, 'Direktori Rekening Bank: ' || r.account_name || ' / ' || r.bank_name || ' / ' || r.account_number, 'aksi_administratif',
    r.account_name || ' / ' || r.bank_name || ' / ' || r.account_number, btrim(p_nama) || ' / ' || btrim(p_bank) || ' / ' || btrim(p_nomor));
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.adm_rekening_bank_gabung(p_keep text, p_drop text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare k direktori_rekening_bank; d direktori_rekening_bank;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola Direktori Rekening Bank.'); end if;
  if p_keep = p_drop then return amanda.gagal('Pilih dua entri yang berbeda.'); end if;
  select * into k from direktori_rekening_bank where id = p_keep for update;
  select * into d from direktori_rekening_bank where id = p_drop for update;
  if k.id is null or d.id is null then return amanda.gagal('Entri direktori tidak ditemukan.'); end if;
  delete from direktori_rekening_bank where id = p_drop;
  update direktori_rekening_bank set updated_at = now() where id = p_keep;
  perform amanda.catat_audit(null, 'Direktori Rekening Bank: ' || d.account_name || ' / ' || d.bank_name || ' / ' || d.account_number, 'aksi_administratif',
    d.account_name || ' / ' || d.account_number, 'Digabung ke ' || k.account_name || ' / ' || k.bank_name || ' / ' || k.account_number);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- ============ FORM DINAMIS BERVERSI (TPL-02) ============
-- Aturan tag sistem (BNT-02): tiap tag sekali per konteks; ID dan nama personel harus berpasangan.
create or replace function amanda.validasi_tag(p_fields jsonb, p_konteks text) returns text
language plpgsql immutable as $$
declare tag text; ada_id boolean; ada_nama boolean;
begin
  for tag in select f->>'system_tag' from jsonb_array_elements(p_fields) f
             where coalesce(f->>'system_tag','') <> '' group by 1 having count(*) > 1 loop
    return 'Tag ' || tag || ' hanya boleh dipakai sekali dalam ' || p_konteks || '.';
  end loop;
  select bool_or(f->>'system_tag' = '[SYS_PERSONNEL_ID]'), bool_or(f->>'system_tag' = '[SYS_PERSONNEL_NAME]')
    into ada_id, ada_nama from jsonb_array_elements(p_fields) f;
  if coalesce(ada_id,false) <> coalesce(ada_nama,false) then
    return '[SYS_PERSONNEL_ID] dan [SYS_PERSONNEL_NAME] harus dipasangkan dalam ' || p_konteks || ' yang sama.';
  end if;
  return null;
end $$;

create or replace function public.adm_form_simpan_versi(p_jenis text, p_fields jsonb, p_blok jsonb default null) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare nama text := btrim(coalesce(p_jenis,'')); err text; maks int; versi text;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola form dinamis.'); end if;
  if nama = '' then return amanda.gagal('Nama jenis belanja wajib diisi.'); end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'array' or jsonb_array_length(p_fields) = 0 then return amanda.gagal('Form wajib memiliki minimal satu field.'); end if;
  if exists (select 1 from jsonb_array_elements(p_fields) f where btrim(coalesce(f->>'label','')) = '') then return amanda.gagal('Label setiap field wajib diisi.'); end if;
  if p_blok is not null and jsonb_typeof(p_blok) = 'object' then
    if btrim(coalesce(p_blok->>'nama','')) = '' or jsonb_array_length(coalesce(p_blok->'fields','[]'::jsonb)) = 0 then
      return amanda.gagal('Blok berulang wajib memiliki nama dan minimal satu field.'); end if;
    err := amanda.validasi_tag(p_blok->'fields', 'blok "' || (p_blok->>'nama') || '"');
    if err is not null then return amanda.gagal(err); end if;
  else p_blok := null; end if;
  err := amanda.validasi_tag(p_fields, 'field utama');
  if err is not null then return amanda.gagal(err); end if;
  select coalesce(max(substr(f.versi, 2)::int), 0) into maks from form_dinamis f where f.jenis_belanja = nama;
  versi := 'v' || (maks + 1);
  insert into form_dinamis (jenis_belanja, versi, fields, blok_berulang) values (nama, versi, p_fields, p_blok);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'versi', versi);
end $$;

-- ============ TEMPLATE (TPL-01, TPL-04): hanya teks konfigurasi ============
create or replace function public.adm_template_simpan(p_kunci text, p_nilai jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare lama jsonb;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengubah template.'); end if;
  if p_kunci not in ('template_kuitansi','template_verifikasi') then return amanda.gagal('Template tidak dikenal.'); end if;
  if btrim(coalesce(p_nilai->>'nama_instansi','')) = '' or btrim(coalesce(p_nilai->>'judul_dokumen','')) = '' then
    return amanda.gagal('Nama instansi dan judul dokumen wajib diisi.'); end if;
  select nilai into lama from konfigurasi where kunci = p_kunci;
  insert into konfigurasi (kunci, nilai, diubah) values (p_kunci, coalesce(lama, '{}'::jsonb) || p_nilai, now())
    on conflict (kunci) do update set nilai = konfigurasi.nilai || excluded.nilai, diubah = now();
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- ============ AKSI PENGAWAS (AUD-04): unduhan laporan tercatat ============
create or replace function public.pengawas_catat_aksi(p_entitas text, p_keterangan text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
begin
  if amanda.peran() is distinct from 'pengawas' then return jsonb_build_object('ok', true, 'dicatat', false); end if;  -- peran lain tidak menghasilkan jejak
  perform amanda.catat_audit(amanda.ta(), p_entitas, 'aksi_pengawas', null, p_keterangan);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'dicatat', true);
end $$;

-- ============ IZIN EKSEKUSI ============
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and (p.proname like 'adm\_%' or p.proname = 'pengawas_catat_aksi')
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
grant execute on all functions in schema amanda to authenticated;
