-- AMANDA — Langkah 3 (backend): Tahun Anggaran, struktur seksi/pemetaan, penugasan, SK, Pengawas per TA, delegasi Plh./Plt.
-- Rujukan: D01 §1.1–1.3, §6, §8; D03 §2.2–2.3; D04 §2.2, §6. Semua tulis lewat RPC; setiap aksi tercatat di Jejak Audit.

-- ============ PEMBANTU ============
create or replace function amanda.rupiah(n bigint) returns text language sql immutable as $$
  select case when n is null then '—' else (case when n < 0 then '-' else '' end) || 'Rp ' || replace(to_char(abs(n), 'FM999,999,999,999,999,999'), ',', '.') end $$;
create or replace function amanda.nama_lengkap(p personel) returns text language sql immutable as $$
  select btrim(concat_ws(' ', nullif(p.gelar_depan,''), p.nama, nullif(p.gelar_belakang,''))) $$;
create or replace function amanda.ta_status(p_ta text) returns text language sql stable security definer set search_path = public, amanda as $$
  select status from tahun_anggaran where id = p_ta $$;

-- Pasangan Bendahara ≠ PPTK pada TA yang sama, termasuk Plh./Plt. (PEN-04, D01 §6 poin 1). Mengembalikan pesan galat atau NULL.
create or replace function amanda.cek_pemisahan_tugas(p_ta text, p_peran text, p_personel text, p_abaikan_penugasan text default null) returns text
language plpgsql stable security definer set search_path = public, amanda as $$
begin
  if p_peran not in ('pptk','bendahara') then return null; end if;
  if p_peran = 'pptk' and exists (select 1 from penugasan_ta t where t.ta_id = p_ta and t.tmt_selesai is null and t.peran = 'bendahara' and t.personel_id = p_personel and t.id is distinct from p_abaikan_penugasan) then
    return 'Personel ini sudah menjadi Bendahara pada TA ini. Bendahara tidak boleh merangkap PPTK.'; end if;
  if p_peran = 'bendahara' and exists (select 1 from penugasan_ta t where t.ta_id = p_ta and t.tmt_selesai is null and t.peran = 'pptk' and t.personel_id = p_personel and t.id is distinct from p_abaikan_penugasan) then
    return 'Personel ini sudah menjadi PPTK pada TA ini. Bendahara tidak boleh merangkap PPTK.'; end if;
  if p_peran = 'pptk' and exists (select 1 from penugasan_delegasi d where d.ta_id = p_ta and d.status = 'Delegasi Aktif' and d.peran_digantikan = 'bendahara' and d.personel_pengganti_id = p_personel) then
    return 'Personel ini menjadi Plh. Bendahara aktif. Tidak boleh merangkap PPTK.'; end if;
  if p_peran = 'bendahara' and exists (select 1 from penugasan_delegasi d where d.ta_id = p_ta and d.status = 'Delegasi Aktif' and d.peran_digantikan = 'pptk' and d.personel_pengganti_id = p_personel) then
    return 'Personel ini menjadi Plh. PPTK aktif. Tidak boleh merangkap Bendahara.'; end if;
  return null;
end $$;

-- Ekstensi/ukuran berkas SK (PEN-02): PDF/JPG/PNG, maksimal 5 MB
create or replace function amanda.validasi_berkas_sk(p_nama text, p_ukuran bigint) returns text language sql immutable as $$
  select case when p_nama is null then null
    when lower(regexp_replace(p_nama, '^.*\.', '')) not in ('pdf','jpg','jpeg','png') then 'Berkas SK harus berformat PDF, JPG, atau PNG.'
    when p_ukuran is not null and p_ukuran > 5 * 1024 * 1024 then 'Ukuran berkas SK melebihi batas 5 MB.' end $$;

-- ============ TA: BUAT, HAPUS, PAGU, STATUS ============
create or replace function amanda.salin_struktur(p_baru text, p_lama text) returns int
language plpgsql volatile security definer set search_path = public, amanda as $$
declare sl seksi_ta; idS text; jumlah int := 0;
begin
  for sl in select * from seksi_ta where ta_id = p_lama and status = 'Aktif' order by tmt_mulai, id loop
    idS := gen_random_uuid()::text;
    insert into seksi_ta (id, ta_id, sotk_id, nama_snapshot, tmt_mulai) values (idS, p_baru, sl.sotk_id, sl.nama_snapshot, sl.tmt_mulai);
    insert into pemetaan_subkegiatan_ta (ta_id, seksi_ta_id, subkegiatan_id, kode_snapshot, nama_snapshot)
      select p_baru, idS, p.subkegiatan_id, p.kode_snapshot, p.nama_snapshot from pemetaan_subkegiatan_ta p where p.seksi_ta_id = sl.id;
    jumlah := jumlah + 1;
  end loop;
  return jumlah;
end $$;

create or replace function public.adm_ta_buat(p_tahun text, p_pagu bigint, p_salin_dari text default null) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare th text := btrim(coalesce(p_tahun,'')); v_id text; n int;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat membuat TA.'); end if;
  if th !~ '^\d{4}$' then return amanda.gagal('Tahun harus 4 digit angka.'); end if;
  if p_pagu is null or p_pagu <= 0 then return amanda.gagal('Pagu Induk harus lebih dari 0.'); end if;
  if exists (select 1 from tahun_anggaran where tahun = th) then return amanda.gagal('TA sudah ada.'); end if;
  v_id := 'ta-' || th;
  insert into tahun_anggaran (id, tahun, pagu_induk) values (v_id, th, p_pagu);
  insert into jendela_alokasi (ta_id) values (v_id);
  insert into format_nomor_verifikasi (ta_id) values (v_id);
  insert into urut_verifikasi (ta_id) values (v_id);
  insert into urut_pergeseran (ta_id) values (v_id);
  perform amanda.catat_audit(v_id, 'TA ' || th, 'aksi_administratif', null, 'TA Draft dibuat');
  if p_salin_dari is not null and p_salin_dari <> '' then
    if not exists (select 1 from tahun_anggaran where id = p_salin_dari) then return amanda.gagal('TA sumber salinan tidak ditemukan.'); end if;
    n := amanda.salin_struktur(v_id, p_salin_dari);
    perform amanda.catat_audit(v_id, 'TA ' || th, 'aksi_administratif', null, 'Salin struktur dari TA lain (' || n || ' seksi)');
  end if;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.adm_ta_salin_struktur(p_baru text, p_lama text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare n int; th text;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola struktur TA.'); end if;
  select tahun into th from tahun_anggaran where id = p_baru and status = 'Draft';
  if not found then return amanda.gagal('TA target harus Draft.'); end if;
  if p_baru = p_lama then return amanda.gagal('TA sumber dan target harus berbeda.'); end if;
  n := amanda.salin_struktur(p_baru, p_lama);
  perform amanda.catat_audit(p_baru, 'TA ' || th, 'aksi_administratif', null, 'Salin struktur dari TA lain (' || n || ' seksi)');
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'jumlah', n);
end $$;

create or replace function public.adm_ta_hapus(p_id text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare t tahun_anggaran;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat menghapus TA.'); end if;
  select * into t from tahun_anggaran where id = p_id for update;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  if t.status <> 'Draft' then return amanda.gagal('Hanya TA Draft yang dapat dihapus.'); end if;
  if t.pernah_transaksi then return amanda.gagal('TA yang pernah memiliki kuitansi tidak dapat dihapus kecuali melalui retensi 12 tahun.'); end if;
  update audit_event set ta_id = null where ta_id = p_id;      -- jejak aksi tetap tersimpan sebagai riwayat global
  delete from tahun_anggaran where id = p_id;                  -- seksi, pemetaan, penugasan, SK, Pengawas TA, delegasi ikut terhapus (cascade)
  perform amanda.catat_audit(null, 'TA ' || t.tahun, 'aksi_administratif', null, 'TA Draft dihapus');
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.adm_ta_edit_pagu(p_ta text, p_pagu bigint) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare t tahun_anggaran;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengubah Pagu Induk.'); end if;
  select * into t from tahun_anggaran where id = p_ta for update;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  if t.status <> 'Draft' then return amanda.gagal('Pagu Induk hanya dapat diubah pada TA Draft.'); end if;
  if p_pagu is null or p_pagu <= 0 then return amanda.gagal('Pagu Induk harus lebih dari 0.'); end if;
  update tahun_anggaran set pagu_induk = p_pagu where id = p_ta;
  perform amanda.catat_audit(p_ta, 'TA ' || t.tahun, 'aksi_administratif', amanda.rupiah(t.pagu_induk), amanda.rupiah(p_pagu));
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- Checklist kesiapan & aktivasi (TA-05)
create or replace function public.ta_checklist(p_ta text) returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
declare t tahun_anggaran; items jsonb; n_seksi int; n_pem_ok int; n_pptk_ok int; semua_sk boolean;
begin
  if amanda.peran() is distinct from 'admin' then return jsonb_build_object('lengkap', false, 'items', '[]'::jsonb); end if;
  select * into t from tahun_anggaran where id = p_ta;
  if not found then return jsonb_build_object('lengkap', false, 'items', '[]'::jsonb); end if;
  select count(*) into n_seksi from seksi_ta where ta_id = p_ta and status = 'Aktif';
  select count(*) into n_pem_ok from seksi_ta s where s.ta_id = p_ta and s.status = 'Aktif' and exists (select 1 from pemetaan_subkegiatan_ta p where p.seksi_ta_id = s.id);
  select count(*) into n_pptk_ok from seksi_ta s where s.ta_id = p_ta and s.status = 'Aktif'
    and exists (select 1 from penugasan_ta g where g.ta_id = p_ta and g.tmt_selesai is null and g.peran = 'pptk' and g.seksi_ta_id = s.id);
  select coalesce(bool_and(g.provisional or exists (select 1 from register_sk k where k.penugasan_id = g.id)), true) into semua_sk
    from penugasan_ta g where g.ta_id = p_ta and g.tmt_selesai is null;
  items := jsonb_build_array(
    jsonb_build_object('label', 'Pagu Induk > 0', 'ok', t.pagu_induk > 0),
    jsonb_build_object('label', 'Seluruh seksi terpetakan (ada pemetaan)', 'ok', n_seksi > 0 and n_pem_ok = n_seksi),
    jsonb_build_object('label', 'Penugasan PA/KPA', 'ok', exists (select 1 from penugasan_ta g where g.ta_id = p_ta and g.tmt_selesai is null and g.peran = 'pa_kpa')),
    jsonb_build_object('label', 'Penugasan Bendahara', 'ok', exists (select 1 from penugasan_ta g where g.ta_id = p_ta and g.tmt_selesai is null and g.peran = 'bendahara')),
    jsonb_build_object('label', 'Penugasan Verifikator', 'ok', exists (select 1 from penugasan_ta g where g.ta_id = p_ta and g.tmt_selesai is null and g.peran = 'verifikator')),
    jsonb_build_object('label', 'Penugasan PPTK untuk setiap seksi', 'ok', n_seksi > 0 and n_pptk_ok = n_seksi),
    jsonb_build_object('label', 'SK atau penugasan provisional', 'ok', semua_sk));
  return jsonb_build_object('lengkap', not exists (select 1 from jsonb_array_elements(items) i where not (i->>'ok')::boolean), 'items', items);
end $$;

-- Siklus status manual (TA-01): Draft→Aktif Penuh; Aktif Penuh→Masa Transisi; Masa Transisi→Arsip/Aktif Penuh; Arsip→Masa Transisi
create or replace function public.adm_ta_ubah_status(p_ta text, p_status text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare t tahun_anggaran; lain text; boleh boolean;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengubah status TA.'); end if;
  select * into t from tahun_anggaran where id = p_ta for update;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  boleh := (t.status = 'Draft' and p_status = 'Aktif Penuh') or (t.status = 'Aktif Penuh' and p_status = 'Masa Transisi')
        or (t.status = 'Masa Transisi' and p_status in ('Arsip Read-Only','Aktif Penuh')) or (t.status = 'Arsip Read-Only' and p_status = 'Masa Transisi');
  if not boleh then return amanda.gagal('Perpindahan status dari ' || t.status || ' ke ' || p_status || ' tidak diizinkan.'); end if;
  if p_status = 'Aktif Penuh' and t.status = 'Draft' and not (public.ta_checklist(p_ta)->>'lengkap')::boolean then
    return amanda.gagal('Checklist kesiapan belum lengkap. Aktivasi TA ditolak.'); end if;
  if p_status = 'Aktif Penuh' then
    select tahun into lain from tahun_anggaran where id <> p_ta and status = 'Aktif Penuh';
    if found then return amanda.gagal('Sudah ada TA Aktif Penuh: TA ' || lain || '. Hanya satu TA boleh Aktif Penuh.'); end if;
  end if;
  update tahun_anggaran set status = p_status,
    tanggal_arsip_terakhir = case when p_status = 'Arsip Read-Only' then amanda.hari_ini_wita() else tanggal_arsip_terakhir end
  where id = p_ta;
  perform amanda.catat_audit(p_ta, 'TA ' || t.tahun, 'perubahan_status_ta', t.status, p_status);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- ============ SNAPSHOT SEKSI & PEMETAAN (TA-04) ============
create or replace function public.adm_seksi_tambah(p_ta text, p_sotk text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare s sotk; st text := amanda.ta_status(p_ta); id text := gen_random_uuid()::text;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola struktur TA.'); end if;
  if st is null then return amanda.gagal('TA tidak ditemukan.'); end if;
  select * into s from sotk where sotk.id = p_sotk and status_versi = 'Aktif';
  if not found then return amanda.gagal('Master SOTK tidak ditemukan atau sudah diarsipkan.'); end if;
  if st <> 'Draft' then return amanda.gagal('Snapshot seksi hanya bisa ditambah pada TA Draft.'); end if;
  if exists (select 1 from seksi_ta x where x.ta_id = p_ta and x.sotk_id = p_sotk and x.status = 'Aktif') then return amanda.gagal('Seksi ini sudah ada di TA.'); end if;
  insert into seksi_ta (id, ta_id, sotk_id, nama_snapshot, tmt_mulai) values (id, p_ta, p_sotk, s.nama_unit, s.tmt_mulai);
  perform amanda.catat_audit(p_ta, 'Seksi TA', 'aksi_administratif', null, s.nama_unit);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'id', id);
end $$;

create or replace function public.adm_seksi_hapus(p_seksi text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare s seksi_ta;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola struktur TA.'); end if;
  select * into s from seksi_ta where id = p_seksi for update;
  if not found then return amanda.gagal('Seksi tidak ditemukan.'); end if;
  if amanda.ta_status(s.ta_id) <> 'Draft' then return amanda.gagal('Hanya TA Draft yang dapat menghapus seksi.'); end if;
  delete from seksi_ta where id = p_seksi;       -- pemetaan dan penugasan PPTK seksi ikut terhapus
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.adm_pemetaan_tambah(p_ta text, p_seksi text, p_sub text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare sub subkegiatan;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola struktur TA.'); end if;
  if amanda.ta_status(p_ta) is distinct from 'Draft' then return amanda.gagal('Pemetaan hanya dapat diubah pada TA Draft.'); end if;
  if not exists (select 1 from seksi_ta where id = p_seksi and ta_id = p_ta) then return amanda.gagal('Seksi tidak ditemukan pada TA ini.'); end if;
  select * into sub from subkegiatan where id = p_sub and status = 'Aktif';
  if not found then return amanda.gagal('Subkegiatan tidak ditemukan atau nonaktif.'); end if;
  if exists (select 1 from pemetaan_subkegiatan_ta where ta_id = p_ta and subkegiatan_id = p_sub) then
    return amanda.gagal('Subkegiatan ini sudah dipetakan ke seksi lain di TA ini. Satu subkegiatan hanya untuk satu seksi per TA.'); end if;
  insert into pemetaan_subkegiatan_ta (ta_id, seksi_ta_id, subkegiatan_id, kode_snapshot, nama_snapshot) values (p_ta, p_seksi, p_sub, sub.kode, sub.nama);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.adm_pemetaan_hapus(p_id text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare p pemetaan_subkegiatan_ta;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola struktur TA.'); end if;
  select * into p from pemetaan_subkegiatan_ta where id = p_id for update;
  if not found then return amanda.gagal('Pemetaan tidak ditemukan.'); end if;
  if amanda.ta_status(p.ta_id) <> 'Draft' then return amanda.gagal('Pemetaan hanya dapat diubah pada TA Draft.'); end if;
  delete from pemetaan_subkegiatan_ta where id = p_id;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- ============ PENUGASAN (PEN-01, PEN-03, PEN-04) ============
create or replace function public.adm_penugasan_tambah(p_ta text, p_peran text, p_personel text, p_seksi text, p_tmt date, p_provisional boolean default false) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare per personel; lama penugasan_ta; err text; id text := gen_random_uuid()::text; seksi text := nullif(p_seksi,'');
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola penugasan.'); end if;
  if amanda.ta_status(p_ta) is null then return amanda.gagal('TA tidak ditemukan.'); end if;
  if amanda.ta_status(p_ta) <> 'Draft' then return amanda.gagal('Penugasan hanya bisa ditambah pada TA Draft.'); end if;
  if p_peran not in ('pa_kpa','bendahara','verifikator','pptk') then return amanda.gagal('Peran penugasan tidak dikenal.'); end if;
  if p_tmt is null then return amanda.gagal('TMT mulai wajib diisi.'); end if;
  if (p_peran = 'pptk') and (seksi is null or not exists (select 1 from seksi_ta where seksi_ta.id = seksi and ta_id = p_ta)) then return amanda.gagal('PPTK wajib ditugaskan pada seksi yang ada di TA ini.'); end if;
  if p_peran <> 'pptk' then seksi := null; end if;
  select * into per from personel where personel.id = p_personel;
  if not found then return amanda.gagal('Personel tidak ditemukan.'); end if;
  err := amanda.cek_pemisahan_tugas(p_ta, p_peran, p_personel);
  if err is not null then return amanda.gagal(err); end if;
  select * into lama from penugasan_ta g where g.ta_id = p_ta and g.peran = p_peran and g.seksi_ta_id is not distinct from seksi and g.tmt_selesai is null for update;
  if found then
    if p_tmt <= lama.tmt_mulai then return amanda.gagal('TMT baru harus setelah TMT penugasan yang berjalan.'); end if;
    update penugasan_ta set tmt_selesai = p_tmt - 1 where penugasan_ta.id = lama.id;
  end if;
  insert into penugasan_ta (id, ta_id, peran, personel_id, seksi_ta_id, tmt_mulai, provisional, nama_snapshot, nip_snapshot)
    values (id, p_ta, p_peran, p_personel, seksi, p_tmt, coalesce(p_provisional,false), amanda.nama_lengkap(per), coalesce(nullif(per.nip,''), per.nik));
  perform amanda.catat_audit(p_ta, 'Penugasan ' || amanda.label_peran(p_peran) || ': ' || per.nama, 'aksi_administratif', null,
    'TMT ' || p_tmt || case when p_provisional then ' (provisional)' else '' end, null, false, null, null, seksi);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'id', id);
end $$;

create or replace function public.adm_penugasan_hapus(p_id text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare g penugasan_ta;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola penugasan.'); end if;
  select * into g from penugasan_ta where id = p_id for update;
  if not found then return amanda.gagal('Penugasan tidak ditemukan.'); end if;
  if amanda.ta_status(g.ta_id) <> 'Draft' then return amanda.gagal('Hanya TA Draft yang dapat menghapus penugasan.'); end if;
  delete from penugasan_ta where id = p_id;      -- SK terkait ikut terhapus (cascade)
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- Mutasi pejabat definitif di tengah TA (PEN-03): penugasan lama berakhir H-1, penugasan baru dibuat
create or replace function public.adm_penugasan_ganti(p_id text, p_pengganti text, p_tmt date) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare g penugasan_ta; per personel; err text; baru text := gen_random_uuid()::text;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola penugasan.'); end if;
  select * into g from penugasan_ta where id = p_id for update;
  if not found then return amanda.gagal('Penugasan tidak ditemukan.'); end if;
  if amanda.ta_status(g.ta_id) = 'Arsip Read-Only' then return amanda.gagal('TA Arsip Read-Only tidak dapat diubah.'); end if;
  if g.tmt_selesai is not null then return amanda.gagal('Penugasan ini sudah berakhir.'); end if;
  select * into per from personel where personel.id = p_pengganti;
  if not found then return amanda.gagal('Personel tidak ditemukan.'); end if;
  if p_tmt is null or p_tmt <= g.tmt_mulai then return amanda.gagal('TMT baru harus setelah TMT penugasan yang berjalan.'); end if;
  err := amanda.cek_pemisahan_tugas(g.ta_id, g.peran, p_pengganti, p_id);
  if err is not null then return amanda.gagal(err); end if;
  update penugasan_ta set tmt_selesai = p_tmt - 1 where id = p_id;
  insert into penugasan_ta (id, ta_id, peran, personel_id, seksi_ta_id, tmt_mulai, nama_snapshot, nip_snapshot)
    values (baru, g.ta_id, g.peran, p_pengganti, g.seksi_ta_id, p_tmt, amanda.nama_lengkap(per), coalesce(nullif(per.nip,''), per.nik));
  perform amanda.catat_audit(g.ta_id, 'Ganti Pejabat: ' || per.nama, 'aksi_administratif', g.nama_snapshot, 'TMT ' || p_tmt || '; penugasan lama berakhir H-1', null, false, null, null, g.seksi_ta_id);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'id', baru);
end $$;

-- ============ REGISTER SK (PEN-02) ============
create or replace function public.adm_sk_tambah(p_penugasan text, p_nomor text, p_tanggal date, p_berkas_key text, p_berkas_nama text, p_berkas_ukuran bigint, p_provisional boolean) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare err text; id text := gen_random_uuid()::text; nomor text := btrim(coalesce(p_nomor,''));
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola Register SK.'); end if;
  if not exists (select 1 from penugasan_ta where penugasan_ta.id = p_penugasan) then return amanda.gagal('Penugasan tidak ditemukan.'); end if;
  if not coalesce(p_provisional, false) then
    if nomor = '' then return amanda.gagal('SK final wajib memiliki nomor SK. Centang Provisional bila SK menyusul.'); end if;
    if p_tanggal is null then return amanda.gagal('SK final wajib memiliki tanggal SK. Centang Provisional bila SK menyusul.'); end if;
    if p_berkas_key is null or p_berkas_nama is null then return amanda.gagal('SK final wajib memiliki berkas SK. Centang Provisional bila SK menyusul.'); end if;
  end if;
  err := amanda.validasi_berkas_sk(p_berkas_nama, p_berkas_ukuran);
  if err is not null then return amanda.gagal(err); end if;
  insert into register_sk (id, penugasan_id, nomor_sk, tanggal_sk, berkas_key, berkas_nama, berkas_ukuran, provisional)
    values (id, p_penugasan, nomor, p_tanggal, p_berkas_key, p_berkas_nama, p_berkas_ukuran, coalesce(p_provisional,false));
  if not coalesce(p_provisional, false) then update penugasan_ta set provisional = false where penugasan_ta.id = p_penugasan; end if;
  perform amanda.catat_audit(null, 'SK: ' || case when nomor = '' then '(belum ada nomor)' else nomor end, 'aksi_administratif', null,
    'Tanggal ' || coalesce(p_tanggal::text, '—') || case when p_provisional then ' (provisional)' else ' (final)' end || case when p_berkas_nama is not null then ', berkas ' || p_berkas_nama else '' end);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'id', id);
end $$;

-- p_berkas: 'tetap' (jangan ubah), 'hapus', atau 'ganti' disertai key/nama/ukuran
create or replace function public.adm_sk_lengkapi(p_id text, p_nomor text, p_tanggal date, p_provisional boolean, p_berkas text default 'tetap',
  p_berkas_key text default null, p_berkas_nama text default null, p_berkas_ukuran bigint default null) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare sk register_sk; err text; nomor text := btrim(coalesce(p_nomor,'')); ada_berkas boolean;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengelola Register SK.'); end if;
  select * into sk from register_sk where id = p_id for update;
  if not found then return amanda.gagal('SK tidak ditemukan.'); end if;
  ada_berkas := case p_berkas when 'hapus' then false when 'ganti' then true else sk.berkas_key is not null end;
  if not coalesce(p_provisional, false) then
    if nomor = '' then return amanda.gagal('SK final wajib memiliki nomor SK.'); end if;
    if p_tanggal is null then return amanda.gagal('SK final wajib memiliki tanggal SK.'); end if;
    if not ada_berkas then return amanda.gagal('SK final wajib memiliki berkas SK.'); end if;
  end if;
  if p_berkas = 'ganti' then
    err := amanda.validasi_berkas_sk(p_berkas_nama, p_berkas_ukuran);
    if err is not null then return amanda.gagal(err); end if;
  end if;
  update register_sk set nomor_sk = nomor, tanggal_sk = p_tanggal, provisional = coalesce(p_provisional,false),
    berkas_key = case p_berkas when 'hapus' then null when 'ganti' then p_berkas_key else berkas_key end,
    berkas_nama = case p_berkas when 'hapus' then null when 'ganti' then p_berkas_nama else berkas_nama end,
    berkas_ukuran = case p_berkas when 'hapus' then null when 'ganti' then p_berkas_ukuran else berkas_ukuran end
  where id = p_id;
  if not coalesce(p_provisional, false) then update penugasan_ta set provisional = false where penugasan_ta.id = sk.penugasan_id; end if;
  perform amanda.catat_audit(null, 'SK: ' || case when nomor = '' then '(belum ada nomor)' else nomor end, 'aksi_administratif',
    sk.nomor_sk || case when sk.provisional then ' (provisional)' else '' end,
    nomor || case when p_provisional then ' (provisional)' else ' (final)' end || case when p_berkas = 'ganti' then ', berkas ' || p_berkas_nama else '' end);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- ============ PENGAWAS PER TA (AKN-05) ============
create or replace function public.adm_pengawas_ta_tambah(p_ta text, p_pengawas text, p_mulai date, p_akhir date) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare a akun_pengawas;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat menugaskan Pengawas.'); end if;
  if amanda.ta_status(p_ta) is null then return amanda.gagal('TA tidak ditemukan.'); end if;
  if amanda.ta_status(p_ta) = 'Arsip Read-Only' then return amanda.gagal('TA Arsip Read-Only tidak dapat diubah.'); end if;
  if p_mulai is null or p_akhir is null then return amanda.gagal('Tanggal mulai dan akhir wajib diisi.'); end if;
  if p_akhir < p_mulai then return amanda.gagal('Tanggal akhir tidak boleh mendahului tanggal mulai.'); end if;
  select * into a from akun_pengawas where id = p_pengawas;
  if not found then return amanda.gagal('Akun Pengawas tidak ditemukan.'); end if;
  if exists (select 1 from penugasan_pengawas_ta where ta_id = p_ta and pengawas_id = p_pengawas) then return amanda.gagal('Pengawas sudah ditugaskan di TA ini.'); end if;
  insert into penugasan_pengawas_ta (ta_id, pengawas_id, tanggal_mulai, tanggal_akhir) values (p_ta, p_pengawas, p_mulai, p_akhir);
  perform amanda.catat_audit(p_ta, 'Penugasan Pengawas: ' || a.nama_lengkap, 'aksi_administratif', null, 'Mulai ' || p_mulai || ', akhir ' || p_akhir);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.adm_pengawas_ta_hapus(p_id text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare t penugasan_pengawas_ta; nama text;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat menugaskan Pengawas.'); end if;
  select * into t from penugasan_pengawas_ta where id = p_id for update;
  if not found then return amanda.gagal('Penugasan tidak ditemukan.'); end if;
  if amanda.ta_status(t.ta_id) = 'Arsip Read-Only' then return amanda.gagal('TA Arsip Read-Only tidak dapat diubah.'); end if;
  select nama_lengkap into nama from akun_pengawas where id = t.pengawas_id;
  delete from penugasan_pengawas_ta where id = p_id;
  update sesi_amanda set berakhir = now() where akun_id = t.pengawas_id and ta_id = t.ta_id and berakhir is null;
  perform amanda.catat_audit(t.ta_id, 'Penugasan Pengawas: ' || coalesce(nama,''), 'aksi_administratif', null, 'Penugasan dihapus');
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- ============ DELEGASI Plh./Plt. (PEN-05..07) ============
create or replace function public.adm_delegasi_tetapkan(p_ta text, p_pengganti text, p_peran text, p_seksi text, p_mulai date, p_berakhir date, p_definitif text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare per personel; seksi text := nullif(p_seksi,''); id text := gen_random_uuid()::text; st text := amanda.ta_status(p_ta);
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat menetapkan delegasi.'); end if;
  if st is null then return amanda.gagal('TA tidak ditemukan.'); end if;
  if st = 'Arsip Read-Only' then return amanda.gagal('TA Arsip Read-Only tidak dapat diubah.'); end if;
  if p_peran not in ('pa_kpa','bendahara','pptk') then return amanda.gagal('Delegasi hanya untuk PA/KPA, Bendahara, atau PPTK.'); end if;
  if p_mulai is null or p_berakhir is null then return amanda.gagal('Tanggal mulai dan berakhir wajib diisi.'); end if;
  if p_berakhir < p_mulai then return amanda.gagal('Tanggal berakhir tidak boleh mendahului tanggal mulai.'); end if;
  if (p_peran = 'pptk') <> (seksi is not null) then return amanda.gagal(case when p_peran = 'pptk' then 'Delegasi PPTK wajib menyebut seksi.' else 'Seksi hanya untuk delegasi PPTK.' end); end if;
  select * into per from personel where personel.id = p_pengganti;
  if not found then return amanda.gagal('Personel pengganti tidak ditemukan.'); end if;
  if p_pengganti = p_definitif then return amanda.gagal('Pengganti tidak boleh sama dengan pejabat definitif.'); end if;
  if not exists (select 1 from penugasan_ta g where g.ta_id = p_ta and g.tmt_selesai is null and g.peran = p_peran and g.personel_id = p_definitif and g.seksi_ta_id is not distinct from seksi) then
    return amanda.gagal('Pejabat definitif tidak memiliki penugasan aktif pada peran/seksi ini.'); end if;
  -- PEN-04: peran bertentangan (penugasan definitif maupun delegasi aktif)
  if p_peran = 'bendahara' and exists (select 1 from penugasan_ta g where g.ta_id = p_ta and g.tmt_selesai is null and g.personel_id = p_pengganti and g.peran = 'pptk') then
    return amanda.gagal('Personel ini adalah PPTK pada TA ini. Tidak boleh menjadi Plh. Bendahara (Bendahara ≠ PPTK).'); end if;
  if p_peran = 'pptk' and exists (select 1 from penugasan_ta g where g.ta_id = p_ta and g.tmt_selesai is null and g.personel_id = p_pengganti and g.peran = 'bendahara') then
    return amanda.gagal('Personel ini adalah Bendahara pada TA ini. Tidak boleh menjadi Plh. PPTK (Bendahara ≠ PPTK).'); end if;
  if p_peran = 'bendahara' and exists (select 1 from penugasan_delegasi d where d.ta_id = p_ta and d.status = 'Delegasi Aktif' and d.personel_pengganti_id = p_pengganti and d.peran_digantikan = 'pptk') then
    return amanda.gagal('Personel ini menjadi Plh. PPTK aktif. Tidak boleh merangkap Plh. Bendahara.'); end if;
  if p_peran = 'pptk' and exists (select 1 from penugasan_delegasi d where d.ta_id = p_ta and d.status = 'Delegasi Aktif' and d.personel_pengganti_id = p_pengganti and d.peran_digantikan = 'bendahara') then
    return amanda.gagal('Personel ini menjadi Plh. Bendahara aktif. Tidak boleh merangkap Plh. PPTK.'); end if;
  insert into penugasan_delegasi (id, ta_id, personel_pengganti_id, peran_digantikan, seksi_ta_id, tanggal_mulai, tanggal_berakhir, definitive_officer_id, nama_snapshot, nip_snapshot)
    values (id, p_ta, p_pengganti, p_peran, seksi, p_mulai, p_berakhir, p_definitif, amanda.nama_lengkap(per), coalesce(nullif(per.nip,''), per.nik));
  perform amanda.catat_audit(p_ta, 'Delegasi: ' || per.nama || ' → Plh. ' || amanda.label_peran(p_peran), 'delegasi_tetapkan', null,
    'Status: Delegasi Aktif, berlaku ' || p_mulai || ' — ' || p_berakhir, null, false, null, null, seksi, p_definitif, p_pengganti);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'id', id);
end $$;

create or replace function public.adm_delegasi_cabut(p_id text, p_alasan text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare d penugasan_delegasi;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mencabut delegasi.'); end if;
  if btrim(coalesce(p_alasan,'')) = '' then return amanda.gagal('Alasan pencabutan dini wajib diisi.'); end if;
  select * into d from penugasan_delegasi where id = p_id for update;
  if not found then return amanda.gagal('Delegasi tidak ditemukan.'); end if;
  if d.status <> 'Delegasi Aktif' then return amanda.gagal('Delegasi sudah berakhir/dicabut.'); end if;
  update penugasan_delegasi set status = 'Dicabut', alasan_pencabutan = btrim(p_alasan) where id = p_id;
  perform amanda.catat_audit(d.ta_id, 'Delegasi: ' || d.nama_snapshot, 'delegasi_pencabutan_dini', null, 'Status: Dicabut (dari Delegasi Aktif)', btrim(p_alasan),
    false, null, null, d.seksi_ta_id, d.definitive_officer_id, d.personel_pengganti_id);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- Pengakhiran otomatis 23:59 WITA (PEN-06). Dijadwalkan pg_cron pada 15:59 UTC (lihat 0006) dan aman dipanggil kapan saja.
-- Hak per tanggal sudah dijaga oleh daftar_konteks/sesi (tanggal_berakhir); fungsi ini menutup status dan mencatat audit otomatis.
create or replace function public.akhiri_delegasi_jatuh_tempo() returns int
language plpgsql volatile security definer set search_path = public, amanda as $$
declare d penugasan_delegasi; n int := 0; wita timestamp := now() at time zone 'Asia/Makassar';
begin
  for d in select * from penugasan_delegasi x where x.status = 'Delegasi Aktif'
           and (x.tanggal_berakhir < wita::date or (x.tanggal_berakhir = wita::date and wita::time >= time '23:59')) for update loop
    update penugasan_delegasi set status = 'Berakhir' where id = d.id;
    perform amanda.catat_audit(d.ta_id, 'Delegasi: ' || d.nama_snapshot, 'delegasi_berakhir_otomatis', null,
      'Status: Berakhir (dari Delegasi Aktif), 23:59 WITA ' || d.tanggal_berakhir, null, true, null, null, d.seksi_ta_id, d.definitive_officer_id, d.personel_pengganti_id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ============ IZIN EKSEKUSI ============
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and (p.proname like 'adm\_%' or p.proname = 'ta_checklist') and p.proname !~ '^adm_(akun|personel|sotk|pengawas_(tambah|edit|reset|set)|subkegiatan|rekening|jenis|direktori|form|template)'
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
revoke all on function public.akhiri_delegasi_jatuh_tempo() from public, anon, authenticated;
grant execute on function public.akhiri_delegasi_jatuh_tempo() to service_role;
grant execute on all functions in schema amanda to authenticated;
