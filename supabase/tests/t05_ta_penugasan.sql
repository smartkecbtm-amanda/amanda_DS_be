-- Uji Langkah 3: TA, seksi/pemetaan, penugasan, SK, Pengawas per TA, delegasi
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

select pg_temp.sebagai('198203152009012003','ta-2026','bendahara',null); set role authenticated;
select pg_temp.cek('Bendahara tidak boleh buat TA', public.adm_ta_buat('2030', 1000), false, 'Hanya Admin');
reset role;

select pg_temp.sebagai('admin',null,'admin',null); set role authenticated;
select pg_temp.cek('TA tahun bukan 4 digit', public.adm_ta_buat('26', 1000), false, '4 digit');
select pg_temp.cek('TA pagu nol', public.adm_ta_buat('2029', 0), false, 'lebih dari 0');
select pg_temp.cek('TA duplikat', public.adm_ta_buat('2026', 1000), false, 'sudah ada');
select pg_temp.cek('TA 2029 dibuat + salin struktur 2026', public.adm_ta_buat('2029', 5000000000, 'ta-2026'), true);
select 'salinan 2029' k, (select count(*) from seksi_ta where ta_id='ta-2029') seksi, (select count(*) from pemetaan_subkegiatan_ta where ta_id='ta-2029') pemetaan;
select pg_temp.cek('Aktivasi TA 2029 dengan checklist kurang', public.adm_ta_ubah_status('ta-2029','Aktif Penuh'), false, 'Checklist');
select 'checklist' k, i->>'label' label, i->>'ok' ok from jsonb_array_elements(public.ta_checklist('ta-2029')->'items') i;
select pg_temp.cek('Edit pagu TA Draft', public.adm_ta_edit_pagu('ta-2029', 6000000000), true);
select pg_temp.cek('Edit pagu TA aktif ditolak', public.adm_ta_edit_pagu('ta-2026', 1), false, 'Draft');
select pg_temp.cek('Transisi Draft->Arsip ditolak', public.adm_ta_ubah_status('ta-2029','Arsip Read-Only'), false, 'tidak diizinkan');

-- seksi & pemetaan
select pg_temp.cek('Pemetaan subkegiatan sudah dipetakan', public.adm_pemetaan_tambah('ta-2029', (select id from seksi_ta where ta_id='ta-2029' order by id limit 1), (select subkegiatan_id from pemetaan_subkegiatan_ta where ta_id='ta-2029' limit 1)), false, 'satu seksi');
select pg_temp.cek('Seksi pada TA aktif ditolak', public.adm_seksi_tambah('ta-2026', (select id from sotk where status_versi='Aktif' limit 1)), false, 'Draft');
select pg_temp.cek('Pemetaan pada TA aktif ditolak', public.adm_pemetaan_tambah('ta-2026', 'sek-2026-1', 'sub-1'), false, 'Draft');

-- penugasan: PA, Bendahara, Verifikator, PPTK semua seksi
select pg_temp.cek('Penugasan PA/KPA', public.adm_penugasan_tambah('ta-2029','pa_kpa','p-1',null,'2029-01-01',false), true);
select pg_temp.cek('Penugasan Bendahara p-2', public.adm_penugasan_tambah('ta-2029','bendahara','p-2',null,'2029-01-01',false), true);
select pg_temp.cek('PPTK = Bendahara ditolak', public.adm_penugasan_tambah('ta-2029','pptk','p-2',(select id from seksi_ta where ta_id='ta-2029' order by id limit 1),'2029-01-01',false), false, 'Bendahara tidak boleh merangkap PPTK');
select pg_temp.cek('Penugasan Verifikator', public.adm_penugasan_tambah('ta-2029','verifikator','p-6',null,'2029-01-01',true), true);
select pg_temp.cek('PPTK tanpa seksi ditolak', public.adm_penugasan_tambah('ta-2029','pptk','p-3',null,'2029-01-01',false), false, 'seksi');
do $$ declare s record; per text[] := array['p-3','p-4','p-5','p-7']; i int := 1; begin
  for s in select id from seksi_ta where ta_id='ta-2029' order by id loop
    perform pg_temp.cek('PPTK seksi '||i, public.adm_penugasan_tambah('ta-2029','pptk',per[i],s.id,'2029-01-01',true), true); i := i + 1;
  end loop;
end $$;
select 'checklist lengkap?' k, public.ta_checklist('ta-2029')->>'lengkap';
select pg_temp.cek('Bendahara p-3 (sudah PPTK) ditolak', public.adm_penugasan_ganti((select id from penugasan_ta where ta_id='ta-2029' and peran='bendahara'),'p-3','2029-06-01'), false, 'PPTK');

-- SK
do $$ declare g text; begin
  select id into g from penugasan_ta where ta_id='ta-2029' and peran='pa_kpa';
  perform pg_temp.cek('SK final tanpa berkas ditolak', public.adm_sk_tambah(g,'SK/1','2029-01-02',null,null,null,false), false, 'berkas');
  perform pg_temp.cek('SK format .doc ditolak', public.adm_sk_tambah(g,'SK/1','2029-01-02','k/a.doc','a.doc',1000,false), false, 'PDF, JPG, atau PNG');
  perform pg_temp.cek('SK > 5 MB ditolak', public.adm_sk_tambah(g,'SK/1','2029-01-02','k/a.pdf','a.pdf',6000000,false), false, '5 MB');
  perform pg_temp.cek('SK final lengkap', public.adm_sk_tambah(g,'SK/1','2029-01-02','k/a.pdf','a.pdf',1000,false), true);
  perform pg_temp.cek('SK provisional tanpa isi', public.adm_sk_tambah((select id from penugasan_ta where ta_id='ta-2029' and peran='bendahara'),'',null,null,null,null,true), true);
  perform pg_temp.cek('Lengkapi SK final tanpa nomor ditolak', public.adm_sk_lengkapi((select id from register_sk where provisional limit 1),'',null,false,'tetap'), false, 'nomor');
  perform pg_temp.cek('Lengkapi SK final', public.adm_sk_lengkapi((select id from register_sk where provisional and penugasan_id in (select id from penugasan_ta where ta_id='ta-2029') limit 1),'SK/2','2029-02-02',false,'ganti','k/b.pdf','b.pdf',2000), true);
end $$;
-- Pengawas per TA
select pg_temp.cek('Pengawas TA tambah', public.adm_pengawas_ta_tambah('ta-2029','aud-1','2029-01-01','2029-12-31'), true);
select pg_temp.cek('Pengawas TA duplikat', public.adm_pengawas_ta_tambah('ta-2029','aud-1','2029-01-01','2029-12-31'), false, 'sudah ditugaskan');
select pg_temp.cek('Pengawas TA akhir < mulai', public.adm_pengawas_ta_tambah('ta-2029','aud-2','2029-12-31','2029-01-01'), false, 'mendahului');
-- Delegasi
select pg_temp.cek('Plh. Bendahara = PPTK ditolak', public.adm_delegasi_tetapkan('ta-2026','p-3','bendahara',null,current_date,current_date+5,'p-2'), false, 'PPTK pada TA ini');
select pg_temp.cek('Delegasi pengganti sama dgn definitif', public.adm_delegasi_tetapkan('ta-2026','p-2','bendahara',null,current_date,current_date+5,'p-2'), false, 'sama');
select pg_temp.cek('Delegasi definitif tidak menjabat', public.adm_delegasi_tetapkan('ta-2026','p-8','bendahara',null,current_date,current_date+5,'p-5'), false, 'tidak memiliki penugasan');
select pg_temp.cek('Delegasi PPTK tanpa seksi', public.adm_delegasi_tetapkan('ta-2026','p-8','pptk',null,current_date,current_date+5,'p-3'), false, 'seksi');
select pg_temp.cek('Plh. PA/KPA', public.adm_delegasi_tetapkan('ta-2026','p-8','pa_kpa',null,current_date,current_date+5,'p-1'), true);
select pg_temp.cek('Cabut tanpa alasan', public.adm_delegasi_cabut((select id from penugasan_delegasi where peran_digantikan='pa_kpa'), ''), false, 'Alasan');
select pg_temp.cek('Cabut dini', public.adm_delegasi_cabut((select id from penugasan_delegasi where peran_digantikan='pa_kpa'), 'Pejabat kembali'), true);
select pg_temp.cek('Cabut dua kali', public.adm_delegasi_cabut((select id from penugasan_delegasi where peran_digantikan='pa_kpa'), 'x'), false, 'sudah berakhir');
reset role;
-- pengakhiran otomatis (dipanggil sistem)
update penugasan_delegasi set tanggal_mulai = current_date - 10, tanggal_berakhir = current_date - 1, status='Delegasi Aktif' where id = (select id from penugasan_delegasi where ta_id='ta-2026' order by id limit 1);
select 'delegasi diakhiri otomatis' k, public.akhiri_delegasi_jatuh_tempo();
select 'audit otomatis' k, aktor_nama_snapshot, otomatis, aksi from audit_event where aksi='delegasi_berakhir_otomatis' order by waktu desc limit 1;
-- Aktivasi TA 2029 saat 2026 masih Aktif Penuh ditolak; arsipkan 2026 lalu aktifkan 2028
select pg_temp.sebagai('admin',null,'admin',null); set role authenticated;
select pg_temp.cek('Aktivasi TA kedua ditolak', public.adm_ta_ubah_status('ta-2029','Aktif Penuh'), false, 'Hanya satu TA');
select pg_temp.cek('2026 -> Masa Transisi', public.adm_ta_ubah_status('ta-2026','Masa Transisi'), true);
select pg_temp.cek('2028 -> Aktif Penuh', public.adm_ta_ubah_status('ta-2029','Aktif Penuh'), true);
select pg_temp.cek('2026 -> Arsip', public.adm_ta_ubah_status('ta-2026','Arsip Read-Only'), true);
select '2026 arsip tanggal' k, tanggal_arsip_terakhir is not null from tahun_anggaran where id='ta-2026';
select pg_temp.cek('Hapus TA aktif ditolak', public.adm_ta_hapus('ta-2029'), false, 'Draft');
select pg_temp.cek('Hapus TA Draft yang pernah bertransaksi ditolak', public.adm_ta_hapus('ta-2028'), false, 'retensi');
select pg_temp.cek('Hapus TA Draft 2027 (pernah transaksi? tidak)', public.adm_ta_hapus('ta-2027'), true);
select 'sisa data 2027' k, (select count(*) from seksi_ta where ta_id='ta-2027') seksi, (select count(*) from audit_event where ta_id='ta-2027') audit_ta;
select 'audit penghapusan' k, entitas, nilai_sesudah from audit_event where nilai_sesudah='TA Draft dihapus';
reset role;
