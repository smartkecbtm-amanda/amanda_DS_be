-- Uji pengerasan: hak eksekusi fungsi, pembatasan laju masuk
create or replace function pg_temp.ada(p_label text, p_kondisi boolean) returns void language plpgsql as $$
begin if p_kondisi then raise notice 'lulus  %', p_label; else raise notice 'GAGAL  % (kondisi salah)', p_label; end if; end $$;

select pg_temp.ada('authenticated tak boleh catat_audit langsung', not has_function_privilege('authenticated', 'amanda.catat_audit(text,text,text,text,text,text,boolean,text,text,text,text,text)', 'execute'));
select pg_temp.ada('authenticated tak boleh catat_versi', not has_function_privilege('authenticated', 'amanda.catat_versi(text,text,text)', 'execute'));
select pg_temp.ada('authenticated tak boleh daftar_konteks', not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='amanda' and p.proname='daftar_konteks' and has_function_privilege('authenticated', p.oid, 'execute')));
select pg_temp.ada('Tak ada fungsi amanda yang bisa dijalankan PUBLIC/anon', not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='amanda' and (has_function_privilege('anon', p.oid, 'execute'))));
select pg_temp.ada('Fungsi amanda yang boleh authenticated hanya helper kebijakan (<=14)', (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='amanda' and has_function_privilege('authenticated', p.oid, 'execute')) <= 14);
select pg_temp.ada('Tak ada fungsi public dengan hak PUBLIC bawaan', not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f' and (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type='EXECUTE'))));
select pg_temp.ada('anon hanya boleh publik_* dan pub_cek_keaslian', (select coalesce(string_agg(p.proname, ','), '') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f' and has_function_privilege('anon', p.oid, 'execute') and p.proname not in ('publik_daftar_ta','publik_ringkasan','pub_cek_keaslian')) = '');
select pg_temp.ada('Fungsi login hanya service_role', not has_function_privilege('authenticated', 'public.verifikasi_login(text,text)', 'execute') and not has_function_privilege('authenticated', 'public.buka_sesi(text,uuid,text,text,text)', 'execute') and has_function_privilege('service_role', 'public.verifikasi_login(text,text)', 'execute'));
select pg_temp.ada('Tabel percobaan_masuk tak terbaca klien', not has_table_privilege('authenticated','public.percobaan_masuk','select') and not has_table_privilege('anon','public.percobaan_masuk','select'));
select pg_temp.ada('cek_laju_masuk tak bisa dipanggil klien', not has_function_privilege('authenticated','public.cek_laju_masuk(text,int,int)','execute') and not has_function_privilege('anon','public.cek_laju_masuk(text,int,int)','execute'));

-- pembatasan laju: batas 3 per 15 menit
select public.cek_laju_masuk('uji:a', 3, 15) as p1 \gset
select public.cek_laju_masuk('uji:a', 3, 15) as p2 \gset
select public.cek_laju_masuk('uji:a', 3, 15) as p3 \gset
select public.cek_laju_masuk('uji:a', 3, 15) as p4 \gset
select pg_temp.ada('3 percobaan pertama diizinkan', :'p1' = 't' and :'p2' = 't' and :'p3' = 't');
select pg_temp.ada('Percobaan ke-4 ditolak', :'p4' = 'f');
select pg_temp.ada('Kunci lain tidak terpengaruh', public.cek_laju_masuk('uji:b', 3, 15));
select pg_temp.ada('Parameter tak valid ditolak', not public.cek_laju_masuk('', 3, 15) and not public.cek_laju_masuk('x', 0, 15));
update percobaan_masuk set waktu = now() - interval '20 minutes' where kunci = 'uji:a';
select pg_temp.ada('Setelah jendela lewat diizinkan lagi', public.cek_laju_masuk('uji:a', 3, 15));
