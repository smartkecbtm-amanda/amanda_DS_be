-- AMANDA — Pengerasan keamanan (jalankan TERAKHIR; bila menambah migrasi di kemudian hari, jalankan ulang bagian GRANT ini).
-- 1) Hak eksekusi fungsi bantu `amanda.*` dicabut dari PUBLIC/anon/authenticated, lalu hanya fungsi yang dipakai kebijakan RLS/Storage yang diberi.
--    Fungsi tulis (catat_audit, catat_versi, daftar_konteks, dst.) hanya dapat dipanggil dari RPC `public.*` (SECURITY DEFINER), tidak langsung.
-- 2) Pembatasan laju percobaan masuk (dipakai Edge Function `masuk`) untuk mempersulit penyalahgunaan penguncian akun.

revoke execute on all functions in schema amanda from public, anon, authenticated;
alter default privileges in schema amanda revoke execute on functions from public, anon, authenticated;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'amanda' and p.proname in ('sesi','peran','ta','seksi','akun','personel','di_ta','seksi_kuitansi','kuitansi_punya_spj_terajukan','hari_ini_wita',
                                                         'lampiran_boleh_baca','lampiran_boleh_tulis','objek_yatim','sk_boleh_tulis')
  loop execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;

-- ============ PEMBATASAN LAJU MASUK ============
create table if not exists percobaan_masuk (
  id bigint generated always as identity primary key,
  kunci text not null,
  waktu timestamptz not null default now()
);
create index if not exists percobaan_masuk_kunci_waktu on percobaan_masuk (kunci, waktu);
alter table percobaan_masuk enable row level security;
alter table percobaan_masuk force row level security;
revoke all on percobaan_masuk from public, anon, authenticated;

-- True bila percobaan DIIZINKAN (jumlah percobaan dalam jendela < batas); setiap panggilan dicatat. Hanya service_role.
create or replace function public.cek_laju_masuk(p_kunci text, p_batas int, p_menit int) returns boolean
language plpgsql volatile security definer set search_path = public, amanda as $$
declare n int;
begin
  if coalesce(p_kunci, '') = '' or p_batas < 1 or p_menit < 1 then return false; end if;
  delete from percobaan_masuk where waktu < now() - interval '1 day';
  select count(*) into n from percobaan_masuk where kunci = p_kunci and waktu > now() - make_interval(mins => p_menit);
  if n >= p_batas then return false; end if;
  insert into percobaan_masuk (kunci) values (p_kunci);
  return true;
end $$;
revoke all on function public.cek_laju_masuk(text, int, int) from public, anon, authenticated;
grant execute on function public.cek_laju_masuk(text, int, int) to service_role;

-- Fungsi sesi di schema public: hanya pengguna masuk (authenticated), bukan anon/PUBLIC.
revoke all on function public.sesi_saya() from public, anon;
revoke all on function public.ping_sesi() from public, anon;
revoke all on function public.akhiri_sesi() from public, anon;
grant execute on function public.sesi_saya(), public.ping_sesi(), public.akhiri_sesi() to authenticated;
