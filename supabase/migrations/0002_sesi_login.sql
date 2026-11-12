-- AMANDA — Sesi tunggal terisolasi, verifikasi login, kunci 10x gagal (Dokumen 04 §3, Dokumen 05 bagian P).
-- Alur: Edge Function `masuk` memanggil verifikasi_login (tiket) -> daftar_konteks -> buka_sesi.
-- Konteks (TA, peran, seksi) dikunci satu kali pada sesi_amanda; tidak ada fungsi yang mengubahnya.
-- Hak akses tabel/fungsi: lihat 0003 (RLS). Di sini fungsi service-only dicabut dari PUBLIC.

-- Cabut hak bawaan Supabase: akses tabel hanya lewat kebijakan RLS yang diberikan eksplisit di 0003.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

create table tiket_login (
  tiket text primary key,            -- hash sha256 dari tiket yang dikirim ke klien
  tipe text not null check (tipe in ('internal','auditor')),
  akun_id text not null,
  dibuat timestamptz not null default now(),
  kedaluwarsa timestamptz not null default now() + interval '5 minutes',
  dipakai boolean not null default false
);
alter table tiket_login enable row level security;
alter table sesi_amanda enable row level security;

-- ============ KONTEKS SESI AKTIF ============
-- Mengembalikan baris sesi bila valid: belum berakhir, aktivitas < 1 jam, akun masih ACTIVE dan tidak terkunci,
-- dan (Pengawas) akses belum berakhir serta penugasan TA masih berlaku. Selain itu NULL => semua kebijakan menolak.
create or replace function amanda.sesi() returns sesi_amanda
language plpgsql stable security definer set search_path = public, amanda as $$
declare
  sid uuid := nullif(auth.jwt()->>'session_id','')::uuid;
  s sesi_amanda;
begin
  if sid is null then return null; end if;
  select * into s from sesi_amanda where sesi_id = sid;
  if not found or s.berakhir is not null or s.peran is null then return null; end if;
  if s.terakhir_aktif < now() - interval '1 hour' then return null; end if;
  if s.tipe = 'internal' then
    if not exists (select 1 from akun_login a where a.id = s.akun_id and a.status = 'ACTIVE' and (a.is_admin or not a.locked)) then
      return null;
    end if;
  else
    if not exists (
      select 1 from akun_pengawas p
      where p.id = s.akun_id and p.status = 'ACTIVE' and not p.locked and p.tanggal_akhir_akses >= amanda.hari_ini_wita()
    ) then return null; end if;
    if not exists (
      select 1 from penugasan_pengawas_ta t
      where t.pengawas_id = s.akun_id and t.ta_id = s.ta_id
        and amanda.hari_ini_wita() between t.tanggal_mulai and t.tanggal_akhir
    ) then return null; end if;
  end if;
  return s;
end $$;

create or replace function amanda.peran() returns text language sql stable security definer set search_path = public, amanda as $$ select (amanda.sesi()).peran $$;
create or replace function amanda.ta() returns text language sql stable security definer set search_path = public, amanda as $$ select (amanda.sesi()).ta_id $$;
create or replace function amanda.seksi() returns text language sql stable security definer set search_path = public, amanda as $$ select (amanda.sesi()).seksi_ta_id $$;
create or replace function amanda.akun() returns text language sql stable security definer set search_path = public, amanda as $$ select (amanda.sesi()).akun_id $$;
create or replace function amanda.personel() returns text language sql stable security definer set search_path = public, amanda as $$ select (amanda.sesi()).personel_id $$;

-- ============ KONTEKS YANG BOLEH DIPILIH ============
-- Personel: penugasan definitif aktif + delegasi aktif. Pejabat definitif yang peran/seksinya sedang
-- didelegasikan (Delegasi Aktif) kehilangan hak transaksi pada peran itu (Dokumen 01 §6 poin 8).
create or replace function amanda.daftar_konteks(p_tipe text, p_akun_id text) returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
declare hasil jsonb;
begin
  if p_tipe = 'internal' then
    if exists (select 1 from akun_login where id = p_akun_id and is_admin) then
      return jsonb_build_array(jsonb_build_object('ta_id', null, 'tahun', null, 'peran', 'admin', 'seksi_ta_id', null, 'seksi_nama', null, 'delegasi', false));
    end if;
    select coalesce(jsonb_agg(x order by x->>'tahun' desc, x->>'peran', x->>'seksi_nama'), '[]'::jsonb) into hasil from (
      select jsonb_build_object('ta_id', t.ta_id, 'tahun', ta.tahun, 'peran', t.peran, 'seksi_ta_id', t.seksi_ta_id,
                                'seksi_nama', s.nama_snapshot, 'delegasi', false) as x
      from akun_login a
      join penugasan_ta t on t.personel_id = a.personel_id and t.tmt_selesai is null
      join tahun_anggaran ta on ta.id = t.ta_id
      left join seksi_ta s on s.id = t.seksi_ta_id
      where a.id = p_akun_id
        and not exists (
          select 1 from penugasan_delegasi d
          where d.ta_id = t.ta_id and d.peran_digantikan = t.peran
            and d.seksi_ta_id is not distinct from t.seksi_ta_id
            and d.status = 'Delegasi Aktif' and d.tanggal_mulai <= amanda.hari_ini_wita() and d.tanggal_berakhir >= amanda.hari_ini_wita())
      union all
      select jsonb_build_object('ta_id', d.ta_id, 'tahun', ta.tahun, 'peran', d.peran_digantikan, 'seksi_ta_id', d.seksi_ta_id,
                                'seksi_nama', s.nama_snapshot, 'delegasi', true)
      from akun_login a
      join penugasan_delegasi d on d.personel_pengganti_id = a.personel_id
      join tahun_anggaran ta on ta.id = d.ta_id
      left join seksi_ta s on s.id = d.seksi_ta_id
      where a.id = p_akun_id and d.status = 'Delegasi Aktif'
        and d.tanggal_mulai <= amanda.hari_ini_wita() and d.tanggal_berakhir >= amanda.hari_ini_wita()
    ) q;
    return hasil;
  else
    select coalesce(jsonb_agg(jsonb_build_object('ta_id', t.ta_id, 'tahun', ta.tahun, 'peran', 'pengawas', 'seksi_ta_id', null, 'seksi_nama', null, 'delegasi', false)
                              order by ta.tahun desc), '[]'::jsonb) into hasil
    from penugasan_pengawas_ta t join tahun_anggaran ta on ta.id = t.ta_id
    where t.pengawas_id = p_akun_id and amanda.hari_ini_wita() between t.tanggal_mulai and t.tanggal_akhir;
    return hasil;
  end if;
end $$;

-- ============ LOGIN (dipanggil Edge Function dengan service_role) ============
create or replace function public.verifikasi_login(p_identitas text, p_sandi text) returns jsonb
language plpgsql security definer set search_path = public, amanda, extensions as $$
declare
  generik constant text := 'Kredensial tidak dikenali atau akun tidak aktif.';
  ident text := btrim(coalesce(p_identitas, ''));
  a akun_login; p akun_pengawas;
  tiket text; nama text; konteks jsonb; ok boolean;
begin
  if ident = '' or coalesce(p_sandi, '') = '' then return jsonb_build_object('ok', false, 'error', 'Lengkapi identitas dan kata sandi.'); end if;
  if length(p_sandi) < 6 then return jsonb_build_object('ok', false, 'error', 'Kata sandi minimal 6 karakter.'); end if;

  if position('@' in ident) > 0 then
    select * into p from akun_pengawas where lower(email) = lower(ident) for update;
    if not found then return jsonb_build_object('ok', false, 'error', generik); end if;
    if p.locked then return jsonb_build_object('ok', false, 'error', 'Akun terkunci. Hubungi Administrator Sistem.'); end if;
    if p.status <> 'ACTIVE' then return jsonb_build_object('ok', false, 'error', generik); end if;
    if amanda.hari_ini_wita() > p.tanggal_akhir_akses then
      return jsonb_build_object('ok', false, 'error', 'Masa akses akun Pengawas/Auditor telah berakhir. Hubungi Administrator Sistem.');
    end if;
    ok := p.kata_sandi_hash = crypt(p_sandi, p.kata_sandi_hash);
    if not ok then
      update akun_pengawas set failed_attempts = failed_attempts + 1, locked = (failed_attempts + 1 >= 10) where id = p.id;
      return jsonb_build_object('ok', false, 'error', generik);
    end if;
    update akun_pengawas set failed_attempts = 0 where id = p.id;
    konteks := amanda.daftar_konteks('auditor', p.id);
    if jsonb_array_length(konteks) = 0 then
      return jsonb_build_object('ok', false, 'error', 'Akun Pengawas belum ditugaskan pada TA. Hubungi Administrator Sistem.');
    end if;
    nama := p.nama_lengkap;
    tiket := encode(gen_random_bytes(24), 'hex');
    insert into tiket_login (tiket, tipe, akun_id) values (encode(digest(tiket, 'sha256'), 'hex'), 'auditor', p.id);
    return jsonb_build_object('ok', true, 'tiket', tiket, 'tipe', 'auditor', 'akun_id', p.id, 'nama', nama, 'konteks', konteks);
  end if;

  select * into a from akun_login where username = ident for update;
  if not found then return jsonb_build_object('ok', false, 'error', generik); end if;
  if a.locked and not a.is_admin then
    return jsonb_build_object('ok', false, 'error', 'Akun terkunci setelah 10 kali percobaan gagal. Hubungi Administrator Sistem.');
  end if;
  if a.status <> 'ACTIVE' then return jsonb_build_object('ok', false, 'error', generik); end if;
  if a.kata_sandi_hash <> crypt(p_sandi, a.kata_sandi_hash) then
    if not a.is_admin then   -- Admin tidak pernah dikunci
      update akun_login set failed_attempts = failed_attempts + 1, locked = (failed_attempts + 1 >= 10) where id = a.id;
    end if;
    return jsonb_build_object('ok', false, 'error', generik);
  end if;
  update akun_login set failed_attempts = 0 where id = a.id;

  konteks := amanda.daftar_konteks('internal', a.id);
  if jsonb_array_length(konteks) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Akun belum memiliki penugasan aktif. Hubungi Administrator Sistem.');
  end if;
  if a.is_admin then nama := 'Administrator Sistem';
  else select btrim(concat_ws(' ', nullif(pe.gelar_depan,''), pe.nama, nullif(pe.gelar_belakang,''))) into nama from personel pe where pe.id = a.personel_id;
  end if;
  tiket := encode(gen_random_bytes(24), 'hex');
  insert into tiket_login (tiket, tipe, akun_id) values (encode(digest(tiket, 'sha256'), 'hex'), 'internal', a.id);
  return jsonb_build_object('ok', true, 'tiket', tiket, 'tipe', 'internal', 'akun_id', a.id, 'auth_user_id', a.auth_user_id, 'nama', nama, 'konteks', konteks);
end $$;

-- Membuka sesi dengan konteks terpilih. p_sesi_id = klaim session_id pada token Supabase yang baru terbit.
create or replace function public.buka_sesi(p_tiket text, p_sesi_id uuid, p_ta text, p_peran text, p_seksi text) returns jsonb
language plpgsql security definer set search_path = public, amanda, extensions as $$
declare
  t tiket_login; k jsonb; cocok boolean; pe personel; ap akun_pengawas; nama text; nip text; s sesi_amanda;
begin
  select * into t from tiket_login where tiket = encode(digest(coalesce(p_tiket,''), 'sha256'), 'hex') for update;
  if not found or t.dipakai or t.kedaluwarsa < now() then
    return jsonb_build_object('ok', false, 'error', 'Tiket masuk tidak berlaku. Silakan masuk kembali.');
  end if;
  k := amanda.daftar_konteks(t.tipe, t.akun_id);
  select exists (
    select 1 from jsonb_array_elements(k) e
    where e->>'peran' = p_peran
      and (e->>'ta_id') is not distinct from p_ta
      and (e->>'seksi_ta_id') is not distinct from nullif(p_seksi, '')
  ) into cocok;
  if not cocok then return jsonb_build_object('ok', false, 'error', 'Konteks tidak sah untuk akun ini.'); end if;
  update tiket_login set dipakai = true where tiket = t.tiket;

  if t.tipe = 'auditor' then
    select * into ap from akun_pengawas where id = t.akun_id;
    nama := ap.nama_lengkap; nip := '—';
    insert into sesi_amanda (sesi_id, tipe, akun_id, ta_id, peran, nama_snapshot, nip_snapshot)
      values (p_sesi_id, 'auditor', t.akun_id, p_ta, 'pengawas', nama, nip) returning * into s;
    return jsonb_build_object('ok', true, 'user_id', t.akun_id, 'actor_type', 'auditor', 'active_ta_id', p_ta, 'active_role', 'pengawas',
      'active_seksi_id', null, 'nama_snapshot', nama, 'nip_snapshot', nip,
      'instansi_asal_snapshot', ap.instansi_asal, 'nomor_surat_tugas_snapshot', ap.nomor_surat_tugas);
  end if;

  if p_peran = 'admin' then
    nama := 'Administrator Sistem'; nip := '—';
    insert into sesi_amanda (sesi_id, tipe, akun_id, peran, nama_snapshot, nip_snapshot)
      values (p_sesi_id, 'internal', t.akun_id, 'admin', nama, nip);
  else
    select pe2.* into pe from akun_login a join personel pe2 on pe2.id = a.personel_id where a.id = t.akun_id;
    nama := btrim(concat_ws(' ', nullif(pe.gelar_depan,''), pe.nama, nullif(pe.gelar_belakang,'')));
    nip := coalesce(nullif(pe.nip,''), pe.nik);
    insert into sesi_amanda (sesi_id, tipe, akun_id, personel_id, ta_id, peran, seksi_ta_id, nama_snapshot, nip_snapshot)
      values (p_sesi_id, 'internal', t.akun_id, pe.id, p_ta, p_peran, case when p_peran = 'pptk' then nullif(p_seksi,'') end, nama, nip);
  end if;
  return jsonb_build_object('ok', true, 'user_id', t.akun_id, 'actor_type', 'internal', 'active_ta_id', p_ta, 'active_role', p_peran,
    'active_seksi_id', case when p_peran = 'pptk' then nullif(p_seksi,'') end, 'nama_snapshot', nama, 'nip_snapshot', nip);
end $$;

-- ============ SESI BERJALAN (dipanggil klien dengan token pengguna) ============
create or replace function public.sesi_saya() returns jsonb
language sql stable security definer set search_path = public, amanda as $$
  select case when s.sesi_id is null then null else jsonb_build_object(
    'user_id', s.akun_id, 'actor_type', s.tipe, 'active_ta_id', s.ta_id, 'active_role', s.peran,
    'active_seksi_id', s.seksi_ta_id, 'nama_snapshot', s.nama_snapshot, 'nip_snapshot', s.nip_snapshot) end
  from (select (amanda.sesi()).*) s
$$;

create or replace function public.ping_sesi() returns boolean
language plpgsql volatile security definer set search_path = public, amanda as $$
declare s sesi_amanda := amanda.sesi();
begin
  if s.sesi_id is null then return false; end if;
  update sesi_amanda set terakhir_aktif = now() where sesi_id = s.sesi_id;
  return true;
end $$;

create or replace function public.akhiri_sesi() returns void
language plpgsql volatile security definer set search_path = public, amanda as $$
declare sid uuid := nullif(auth.jwt()->>'session_id','')::uuid;
begin
  update sesi_amanda set berakhir = now() where sesi_id = sid and berakhir is null;
end $$;

-- Izin eksekusi: login hanya service_role; sesi untuk pengguna terautentikasi
revoke all on function public.verifikasi_login(text, text) from public, anon, authenticated;
revoke all on function public.buka_sesi(text, uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.verifikasi_login(text, text) to service_role;
grant execute on function public.buka_sesi(text, uuid, text, text, text) to service_role;
grant execute on function public.sesi_saya() to authenticated;
grant execute on function public.ping_sesi() to authenticated;
grant execute on function public.akhiri_sesi() to authenticated;
grant usage on schema amanda to authenticated, anon, service_role;
grant execute on function amanda.sesi(), amanda.peran(), amanda.ta(), amanda.seksi(), amanda.akun(), amanda.personel(),
  amanda.hari_ini_wita() to authenticated, anon;

-- ============ BANTUAN EDGE FUNCTION `masuk` (service_role) ============
-- Informasi tiket tanpa menghabiskannya (dipakai sebelum menerbitkan token Supabase).
create or replace function public.tiket_info(p_tiket text) returns jsonb
language plpgsql stable security definer set search_path = public, amanda, extensions as $$
declare t tiket_login;
begin
  select * into t from tiket_login where tiket = encode(digest(coalesce(p_tiket,''), 'sha256'), 'hex');
  if not found or t.dipakai or t.kedaluwarsa < now() then return jsonb_build_object('ok', false); end if;
  if t.tipe = 'internal' then
    return (select jsonb_build_object('ok', true, 'tipe', 'internal', 'akun_id', a.id, 'auth_user_id', a.auth_user_id, 'email', a.username || '@amanda.local')
            from akun_login a where a.id = t.akun_id);
  end if;
  return (select jsonb_build_object('ok', true, 'tipe', 'auditor', 'akun_id', p.id, 'auth_user_id', p.auth_user_id, 'email', lower(p.email))
          from akun_pengawas p where p.id = t.akun_id);
end $$;

create or replace function public.simpan_auth_user(p_tipe text, p_akun_id text, p_auth_user uuid) returns void
language plpgsql volatile security definer set search_path = public, amanda as $$
begin
  if p_tipe = 'internal' then update akun_login set auth_user_id = p_auth_user where id = p_akun_id;
  else update akun_pengawas set auth_user_id = p_auth_user where id = p_akun_id; end if;
end $$;

revoke all on function public.tiket_info(text) from public, anon, authenticated;
revoke all on function public.simpan_auth_user(text, text, uuid) from public, anon, authenticated;
grant execute on function public.tiket_info(text) to service_role;
grant execute on function public.simpan_auth_user(text, text, uuid) to service_role;
