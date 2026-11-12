-- Uji Langkah 2: RPC master data & akun (Admin), penegakan peran, jejak audit
\pset pager off
create or replace function pg_temp.sebagai(p_user text, p_ta text, p_peran text, p_seksi text) returns void language plpgsql as $$
declare r jsonb; sid uuid := gen_random_uuid(); begin
  r := public.verifikasi_login(p_user,'amanda123');
  r := public.buka_sesi(r->>'tiket', sid, p_ta, p_peran, p_seksi);
  if not (r->>'ok')::boolean then raise exception 'sesi gagal %', r; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',gen_random_uuid(),'session_id',sid)::text, false);
end $$;
create or replace function pg_temp.cek(p_label text, p_hasil jsonb, p_harap_ok boolean, p_pesan text default null) returns void language plpgsql as $$
begin
  if (p_hasil->>'ok')::boolean is distinct from p_harap_ok or (p_pesan is not null and position(p_pesan in coalesce(p_hasil->>'error','')) = 0) then
    raise notice 'GAGAL  % -> %', p_label, p_hasil;
  else raise notice 'lulus  %', p_label; end if;
end $$;

-- non-admin ditolak
select pg_temp.sebagai('198203152009012003','ta-2026','bendahara',null);
set role authenticated;
select pg_temp.cek('Bendahara tidak boleh tambah SOTK', public.adm_sotk_tambah('X', '2026-01-01'), false, 'Hanya Admin');
select pg_temp.cek('Bendahara tidak boleh reset sandi', public.adm_akun_reset_sandi('acc-3','abcdef'), false, 'Hanya Admin');
do $$ begin begin insert into sotk(nama_unit,tmt_mulai) values('Langsung','2026-01-01'); raise notice 'GAGAL  tulis langsung sotk lolos'; exception when insufficient_privilege then raise notice 'lulus  tulis langsung tabel master ditolak'; end; end $$;
reset role;

select pg_temp.sebagai('admin',null,'admin',null);
set role authenticated;
-- SOTK
select pg_temp.cek('SOTK tambah', public.adm_sotk_tambah('Seksi Uji','2026-03-01','SK 1'), true);
do $$ declare r jsonb; id text; begin
  select s.id into id from sotk s where s.nama_unit='Seksi Uji';
  perform pg_temp.cek('SOTK ubah nomenklatur TMT sebelum mulai ditolak', public.adm_sotk_ubah_nomenklatur(id,'Seksi Uji Baru','2026-02-01'), false, 'TMT baru');
  perform pg_temp.cek('SOTK ubah nomenklatur', public.adm_sotk_ubah_nomenklatur(id,'Seksi Uji Baru','2026-07-01'), true);
  raise notice 'versi lama: % | %', (select o.status_versi||' selesai '||o.tmt_selesai from sotk o where o.id=(select s2.id from sotk s2 where s2.nama_unit='Seksi Uji')), (select n.nama_unit||' '||n.status_versi||' dari '||n.pengganti_dari_id from sotk n where n.pengganti_dari_id=(select s2.id from sotk s2 where s2.nama_unit='Seksi Uji'));
end $$;
-- Personel
select pg_temp.cek('Personel tanpa NIP/NIK ditolak', public.adm_personel_tambah('{"nama":"A","pangkat":"II/a","tmt":"2024-01-01","no_whatsapp":"0811"}'), false, 'NIP atau NIK');
select pg_temp.cek('Personel NIP huruf ditolak', public.adm_personel_tambah('{"nama":"A","nip":"12ab","pangkat":"II/a","tmt":"2024-01-01","no_whatsapp":"0811"}'), false, 'angka');
select pg_temp.cek('Personel NIP duplikat ditolak', public.adm_personel_tambah('{"nama":"A","nip":"198203152009012003","pangkat":"II/a","tmt":"2024-01-01","no_whatsapp":"0811"}'), false, 'sudah digunakan');
select pg_temp.cek('Personel NIK sama dengan NIP orang lain ditolak', public.adm_personel_tambah('{"nama":"A","nik":"198203152009012003","pangkat":"II/a","tmt":"2024-01-01","no_whatsapp":"0811"}'), false, 'sudah digunakan');
select pg_temp.cek('Personel baru', public.adm_personel_tambah('{"nama":"Dewi","nip":"199912312024012001","pangkat":"III/a","tmt":"2024-01-01","no_whatsapp":"+62811"}'), true);
do $$ declare pid text; begin
  select id into pid from personel where nama='Dewi';
  raise notice 'riwayat awal: %', (select count(*) from riwayat_pangkat where personel_id=pid);
  perform pg_temp.cek('Perubahan pangkat', public.adm_personel_perubahan_pangkat(pid,'III/b','','S.E.','2026-04-01'), true);
  raise notice 'riwayat: %', (select string_agg(pangkat||' '||tmt_mulai||'..'||coalesce(tmt_selesai::text,'-'), ' ; ' order by tmt_mulai) from riwayat_pangkat where personel_id=pid);
  perform pg_temp.cek('Akun sandi pendek ditolak', public.adm_akun_buat(pid,'abc'), false, 'minimal 6');
  perform pg_temp.cek('Akun dibuat', public.adm_akun_buat(pid,'rahasia1'), true);
  perform pg_temp.cek('Akun ganda ditolak', public.adm_akun_buat(pid,'rahasia1'), false, 'sudah ada');
  perform pg_temp.cek('Edit NIP mengikuti username', public.adm_personel_edit(pid,'{"nip":"199912312024012002"}'), true);
  raise notice 'username: %', (select username from akun_login where personel_id=pid);
end $$;
-- Akun: status
select pg_temp.cek('Nonaktif tanpa alasan ditolak', public.adm_akun_set_status('acc-3','NON-ACTIVE',''), false, 'Alasan');
select pg_temp.cek('Nonaktif admin aktif terakhir ditolak', public.adm_akun_set_status((select id from akun_login where is_admin),'NON-ACTIVE','uji'), false, null);
select pg_temp.cek('Nonaktif PPTK', public.adm_akun_set_status('acc-3','NON-ACTIVE','Mutasi keluar'), true);
select 'dampak' k, public.adm_akun_dampak('acc-3');
-- Pengawas
select pg_temp.cek('Pengawas email duplikat', public.adm_pengawas_tambah('{"nama_lengkap":"Z","instansi_asal":"I","nomor_surat_tugas":"1","tanggal_surat_tugas":"2026-01-01","email":"rizal.auditor@balangankab.go.id","tanggal_akhir_akses":"2027-01-01"}','abcdef'), false, 'Email sudah');
select pg_temp.cek('Pengawas tanpa nomor surat', public.adm_pengawas_tambah('{"nama_lengkap":"Z","instansi_asal":"I","nomor_surat_tugas":"","tanggal_surat_tugas":"2026-01-01","email":"z@x.id","tanggal_akhir_akses":"2027-01-01"}','abcdef'), false, 'surat tugas');
select pg_temp.cek('Pengawas baru', public.adm_pengawas_tambah('{"nama_lengkap":"Z","instansi_asal":"I","nomor_surat_tugas":"123","tanggal_surat_tugas":"2026-01-01","email":"z@x.id","tanggal_akhir_akses":"2027-01-01"}','abcdef'), true);
select pg_temp.cek('Perpanjang akses tanpa alasan ditolak', public.adm_pengawas_edit((select id from akun_pengawas where email='z@x.id'),'{"tanggal_akhir_akses":"2028-01-01"}',''), false, 'Alasan');
select pg_temp.cek('Perpanjang akses', public.adm_pengawas_edit((select id from akun_pengawas where email='z@x.id'),'{"tanggal_akhir_akses":"2028-01-01"}','Perpanjangan penugasan'), true);
-- Master lain
select pg_temp.cek('Subkegiatan tambah', public.adm_subkegiatan_simpan(null,'1.01','Uji Sub','r'), true);
select pg_temp.cek('Subkegiatan tanpa nama', public.adm_subkegiatan_simpan(null,'1.01','',''), false, 'wajib');
select pg_temp.cek('Rekening tambah', public.adm_rekening_simpan(null,'5.1.02.01.01.0099','Uji Rek'), true);
select pg_temp.cek('Pajak tambah', public.adm_jenis_pajak_simpan(null,'PPN','PPN Uji'), true);
select pg_temp.cek('Pajak toggle', public.adm_jenis_pajak_toggle((select id from jenis_pajak where nama_jenis_pajak='PPN Uji')), true);
-- Form dinamis
select pg_temp.cek('Form tag ID tanpa nama ditolak', public.adm_form_simpan_versi('Uji','[{"label":"Id","system_tag":"[SYS_PERSONNEL_ID]"}]'), false, 'dipasangkan');
select pg_temp.cek('Form tag ganda ditolak', public.adm_form_simpan_versi('Uji','[{"label":"a","system_tag":"[SYS_PERSONNEL_ID]"},{"label":"b","system_tag":"[SYS_PERSONNEL_ID]"},{"label":"c","system_tag":"[SYS_PERSONNEL_NAME]"}]'), false, 'sekali');
select pg_temp.cek('Form v1', public.adm_form_simpan_versi('Uji','[{"label":"a","system_tag":null}]'), true);
select pg_temp.cek('Form v2', public.adm_form_simpan_versi('Uji','[{"label":"a","system_tag":null},{"label":"b"}]'), true);
select 'versi form Uji' k, string_agg(versi, ',' order by versi) from form_dinamis where jenis_belanja='Uji';
-- Template
select pg_temp.cek('Template tanpa judul', public.adm_template_simpan('template_kuitansi','{"nama_instansi":"X","judul_dokumen":""}'), false, 'wajib');
select pg_temp.cek('Template ok', public.adm_template_simpan('template_kuitansi','{"nama_instansi":"Dinas Uji","judul_dokumen":"KUITANSI"}'), true);
select 'template tetap memuat bidang lain' k, count(*) from jsonb_object_keys((select nilai from konfigurasi where kunci='template_kuitansi'));
-- Direktori
select pg_temp.cek('Gabung direktori sama', public.adm_direktori_gabung('dir-1','dir-1'), false, 'berbeda');
-- Audit tercatat
select 'audit admin tercatat' k, count(*) from audit_event where aktor_peran_snapshot='Administrator' and ta_id is null and waktu > now() - interval '1 minute';
select 'audit status akun' k, entitas, nilai_sebelum, nilai_sesudah, alasan from audit_event where aksi='perubahan_status_akun' order by waktu desc limit 1;
reset role;

-- Pengawas mencatat aksi; peran lain tidak
select pg_temp.sebagai('rizal.auditor@balangankab.go.id','ta-2026','pengawas',null); set role authenticated;
select pg_temp.cek('Pengawas catat unduhan', public.pengawas_catat_aksi('Laporan (a)','Unduhan Excel'), true);
select 'audit aksi_pengawas' k, aktor_peran_snapshot, nilai_sesudah from audit_event where aksi='aksi_pengawas' order by waktu desc limit 1;
reset role;
select pg_temp.sebagai('198203152009012003','ta-2026','bendahara',null); set role authenticated;
select 'bendahara unduh -> dicatat?' k, public.pengawas_catat_aksi('Laporan (a)','Unduhan Excel')->>'dicatat';
reset role;
