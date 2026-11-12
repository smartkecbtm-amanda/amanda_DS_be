\pset pager off
create or replace function pg_temp.sebagai(p_user text, p_ta text, p_peran text, p_seksi text) returns void language plpgsql as $$
declare r jsonb; sid uuid := gen_random_uuid(); begin
  r := public.verifikasi_login(p_user,'amanda123');
  r := public.buka_sesi(r->>'tiket', sid, p_ta, p_peran, p_seksi);
  if not (r->>'ok')::boolean then raise exception 'sesi gagal %', r; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',gen_random_uuid(),'session_id',sid)::text, false);
end $$;
create or replace function pg_temp.ringkas(p_label text) returns void language plpgsql as $$
declare t text; n bigint; hasil text := ''; begin
  foreach t in array array['personel','akun_login','tahun_anggaran','seksi_ta','pemetaan_subkegiatan_ta','penugasan_ta','alokasi_subkegiatan','alokasi_rekening','ledger_spd','kuitansi','spj','bku','token_verifikasi_spj','audit_event','register_sk','subkegiatan','form_dinamis','konfigurasi']
  loop
    begin execute format('select count(*) from %I', t) into n; hasil := hasil || t || '=' || n || ' ';
    exception when insufficient_privilege then hasil := hasil || t || '=DITOLAK '; end;
  end loop;
  raise notice '% -> %', p_label, hasil;
end $$;
set role authenticated;
reset role; select pg_temp.sebagai('198203152009012003','ta-2026','bendahara',null); set role authenticated; select pg_temp.ringkas('BENDAHARA 2026'); 
reset role; select pg_temp.sebagai('198807202012011004','ta-2026','pptk','sek-2026-1'); set role authenticated; select pg_temp.ringkas('PPTK Sekretariat 2026');
reset role; select pg_temp.sebagai('3210014503900001','ta-2026','pptk','sek-2026-2'); set role authenticated; select pg_temp.ringkas('Plh PPTK Perencanaan 2026');
reset role; select pg_temp.sebagai('198911112014032007','ta-2026','verifikator',null); set role authenticated; select pg_temp.ringkas('VERIFIKATOR 2026');
reset role; select pg_temp.sebagai('198501012010011001','ta-2026','pa_kpa',null); set role authenticated; select pg_temp.ringkas('PA/KPA 2026');
reset role; select pg_temp.sebagai('rizal.auditor@balangankab.go.id','ta-2026','pengawas',null); set role authenticated; select pg_temp.ringkas('PENGAWAS 2026');
select 'pengawas: pagu induk' k, tahun, pagu_induk from v_tahun_anggaran;
reset role; select pg_temp.sebagai('198807202012011004','ta-2026','pptk','sek-2026-1'); set role authenticated;
select 'pptk: pagu induk' k, tahun, pagu_induk from v_tahun_anggaran;
select 'pptk: kuitansi' k, id, seksi_ta_id from kuitansi order by id;
reset role; select pg_temp.sebagai('198911112014032007','ta-2026','verifikator',null); set role authenticated;
select 'verifikator: spj' k, id, status from spj order by id;
select 'verifikator: kuitansi' k, id from kuitansi order by id;
reset role; select pg_temp.sebagai('198501012010011001','ta-2026','pa_kpa',null); set role authenticated;
do $$ begin delete from kuitansi; raise notice 'GAGAL  PA dapat menghapus kuitansi'; exception when insufficient_privilege then raise notice 'lulus  PA tidak dapat menulis kuitansi'; end $$;
do $$ begin insert into audit_event(aktor_id,aktor_nama_snapshot,aktor_peran_snapshot,entitas,aksi) values('x','x','x','x','sahkan'); raise notice 'GAGAL  PA dapat menulis audit langsung'; exception when insufficient_privilege then raise notice 'lulus  PA tidak dapat menulis audit langsung'; end $$;
-- sesi lain TA: Bendahara 2026 tidak melihat TA 2025
reset role; select pg_temp.sebagai('198203152009012003','ta-2026','bendahara',null); set role authenticated;
select 'bendahara: TA lain terlihat?' k, tahun from v_tahun_anggaran;
select 'bendahara: alokasi TA2025?' k, count(*) from alokasi_rekening where ta_id = 'ta-2025';
