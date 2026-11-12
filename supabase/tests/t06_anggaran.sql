-- Uji Langkah 4: jendela, alokasi, Sahkan, SPD, pergeseran, APBD-P
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
-- TA 2027 (Draft): alur murni
select pg_temp.sebagai('198203152009012003','ta-2027','bendahara',null); set role authenticated;
select pg_temp.cek('Alokasi sub saat jendela tertutup', public.bend_alokasi_sub_simpan('ta-2027','{"pem-2027-1":7000000000,"pem-2027-2":5000000000}'), false, 'tertutup');
select pg_temp.cek('Jendela format salah', public.bend_jendela_atur('ta-2027','besok'), false, 'Format');
select pg_temp.cek('Jendela di masa lalu', public.bend_jendela_atur('ta-2027','2020-01-01 10:00'), false, 'setelah waktu sekarang');
select pg_temp.cek('Jendela dibuka', public.bend_jendela_atur('ta-2027','2099-01-01 10:00'), true);
select pg_temp.cek('Sub melebihi pagu induk', public.bend_alokasi_sub_simpan('ta-2027','{"pem-2027-1":8000000000,"pem-2027-2":5000000000}'), false, 'melebihi Pagu Induk');
select pg_temp.cek('Pagu negatif', public.bend_alokasi_sub_simpan('ta-2027','{"pem-2027-1":-5}'), false, 'bilangan bulat');
select pg_temp.cek('Pagu pecahan', public.bend_alokasi_sub_simpan('ta-2027','{"pem-2027-1":5.5}'), false, 'bilangan bulat');
select pg_temp.cek('Pemetaan asing', public.bend_alokasi_sub_simpan('ta-2027','{"pem-2026-1":5}'), false, 'tidak terpetakan');
select pg_temp.cek('Alokasi sub benar', public.bend_alokasi_sub_simpan('ta-2027','{"pem-2027-1":7000000000,"pem-2027-2":5000000000}'), true);
select pg_temp.cek('Sahkan sebelum rekening seimbang', public.bend_sahkan('ta-2027'), false, 'Seksi belum seimbang');
reset role;
select pg_temp.sebagai('198807202012011004','ta-2027','pptk','sek-2027-1'); set role authenticated;
select pg_temp.cek('PPTK tidak boleh Sahkan', public.bend_sahkan('ta-2027'), false, 'Hanya Bendahara');
select pg_temp.cek('PPTK tidak boleh atur jendela', public.bend_jendela_atur('ta-2027','2099-01-01 10:00'), false, 'Hanya Bendahara');
select pg_temp.cek('PPTK rekening seksi lain ditolak', public.pptk_alokasi_rek_simpan('ta-2027','pem-2027-2','[{"rekening_id":"rek-1","pagu":5000000000}]'), false, 'seksi pemilik');
select pg_temp.cek('Rekening ganda', public.pptk_alokasi_rek_simpan('ta-2027','pem-2027-1','[{"rekening_id":"rek-1","pagu":1},{"rekening_id":"rek-1","pagu":2}]'), false, 'dua kali');
select pg_temp.cek('Rekening tidak ada', public.pptk_alokasi_rek_simpan('ta-2027','pem-2027-1','[{"rekening_id":"xx","pagu":1}]'), false, 'tidak ditemukan');
select pg_temp.cek('Rekening belum seimbang (draft)', public.pptk_alokasi_rek_simpan('ta-2027','pem-2027-1','[{"rekening_id":"rek-1","pagu":3000000000},{"rekening_id":"rek-3","pagu":3000000000}]'), true);
reset role; select 'status seksi 1 (harap Draft)' k, amanda.status_seksi('ta-2027','sek-2027-1'); set role authenticated;
select pg_temp.cek('Rekening seimbang', public.pptk_alokasi_rek_simpan('ta-2027','pem-2027-1','[{"rekening_id":"rek-1","pagu":3000000000},{"rekening_id":"rek-3","pagu":4000000000}]'), true);
reset role; select 'status seksi 1 (harap Tuntas)' k, amanda.status_seksi('ta-2027','sek-2027-1'); set role authenticated;
select 'PPTK tanpa pagu induk' k, (public.anggaran_ringkasan('ta-2027') ? 'pagu_induk_aktif') ada_pagu_induk;
reset role;
select pg_temp.sebagai('197505052008011006','ta-2027','pptk','sek-2027-2'); set role authenticated;
select pg_temp.cek('PPTK 2 rekening', public.pptk_alokasi_rek_simpan('ta-2027','pem-2027-2','[{"rekening_id":"rek-2","pagu":5000000000}]'), true);
reset role;
select pg_temp.sebagai('198203152009012003','ta-2027','bendahara',null); set role authenticated;
select pg_temp.cek('Sub dikurangi -> selisih tidak nol, sahkan ditolak', public.bend_alokasi_sub_simpan('ta-2027','{"pem-2027-2":4000000000}'), true);
select pg_temp.cek('Sahkan dengan selisih', public.bend_sahkan('ta-2027'), false, 'Selisih');
select pg_temp.cek('Kembalikan pagu sub', public.bend_alokasi_sub_simpan('ta-2027','{"pem-2027-2":5000000000}'), true);
select pg_temp.cek('Sahkan OK', public.bend_sahkan('ta-2027'), true);
select 'ledger terbit' k, count(*) n, sum(perubahan) total from ledger_spd where ta_id='ta-2027' and jenis='terbit';
select 'spd = pagu' k, bool_and(spd_aktif = pagu) from alokasi_rekening where ta_id='ta-2027';
select pg_temp.cek('Sahkan dua kali', public.bend_sahkan('ta-2027'), false, 'sudah disahkan');
select pg_temp.cek('Alokasi sub setelah sahkan', public.bend_alokasi_sub_simpan('ta-2027','{"pem-2027-1":7000000000}'), false, 'sudah disahkan');
select 'versi alokasi 2027' k, count(*) from versi_alokasi where ta_id='ta-2027';
reset role;

-- SPD pada TA 2026 (Aktif Penuh)
select pg_temp.sebagai('198203152009012003','ta-2026','bendahara',null); set role authenticated;
select 'ringkasan 2026' k, jsonb_array_length(public.anggaran_ringkasan('ta-2026')->'rekening') n_rek, (public.anggaran_ringkasan('ta-2026')->>'gerbang_terbuka') gerbang;
reset role; select 'ar-1' k, spd_aktif, amanda.komitmen('ar-1') komit, amanda.realisasi('ar-1') real, amanda.sisa_spd_bebas('ar-1') sisa from alokasi_rekening where id='ar-1'; set role authenticated;
select pg_temp.cek('Efisiensi melebihi sisa', public.bend_spd_efisiensi('ar-1', 99000000000, 'x'), false, 'melebihi Sisa SPD Bebas');
select pg_temp.cek('Efisiensi nol', public.bend_spd_efisiensi('ar-1', 0, 'x'), false, 'lebih dari nol');
select pg_temp.cek('Efisiensi 100 juta', public.bend_spd_efisiensi('ar-1', 100000000, 'hemat'), true);
select pg_temp.cek('Kenaikan tanpa alasan', public.bend_spd_naik('ar-1', 50000000, ' '), false, 'alasan');
select pg_temp.cek('Kenaikan melebihi pagu', public.bend_spd_naik('ar-1', 200000000, 'perlu'), false, 'melebihi pagu');
select pg_temp.cek('Kenaikan 50 juta', public.bend_spd_naik('ar-1', 50000000, 'kebutuhan mendesak'), true);
select 'spd ar-1 (harap 1450000000)' k, spd_aktif from alokasi_rekening where id='ar-1';
select pg_temp.cek('SPD final sama', public.bend_spd_final('ar-1', 1450000000, ''), false, 'Tidak ada perubahan');
select pg_temp.cek('SPD final naik tanpa alasan', public.bend_spd_final('ar-1', 1460000000, ''), false, 'alasan');
select pg_temp.cek('SPD final turun', public.bend_spd_final('ar-1', 1400000000, 'final'), true);
-- pergeseran
select pg_temp.cek('Geser sumber=tujuan', public.bend_geser('ta-2026','ar-1','ar-1',10,''), false, 'tidak boleh sama');
select pg_temp.cek('Geser melebihi sisa', public.bend_geser('ta-2026','ar-1','ar-2',90000000000,''), false, 'Sisa SPD Bebas');
select pg_temp.cek('Geser antar rekening satu sub', public.bend_geser('ta-2026','ar-1','ar-2',100000000,'penyesuaian'), true);
select pg_temp.cek('Geser antar subkegiatan', public.bend_geser('ta-2026','ar-2','ar-3',50000000,'lintas'), true);
select 'nomor pergeseran' k, referensi, count(*) from ledger_spd where ta_id='ta-2026' and jenis='pergeseran' group by referensi order by 2;
select 'pagu sub konsisten' k, (select pagu from alokasi_subkegiatan where id='as-1') pagu_sub1, (select sum(pagu) from alokasi_rekening where pemetaan_subkegiatan_id='pem-2026-1') rek1;
select 'total ledger = spd' k, bool_and(l.s = a.spd_aktif) from alokasi_rekening a join (select alokasi_rekening_id, sum(perubahan) s from ledger_spd group by 1) l on l.alokasi_rekening_id = a.id where a.ta_id='ta-2026';
select pg_temp.cek('Geser pada TA bukan aktif', public.bend_geser('ta-2027','x','y',1,''), false, 'Hanya Bendahara');
reset role;
-- ledger append-only
select 'ledger append-only' k;
do $$ begin begin delete from ledger_spd where ta_id='ta-2026'; raise notice 'GAGAL ledger dapat dihapus'; exception when others then raise notice 'lulus  ledger ditolak: %', sqlerrm; end; end $$;

-- APBD-P pada TA 2026
select pg_temp.sebagai('admin',null,'admin',null); set role authenticated;
select pg_temp.cek('Koreksi sebelum APBD-P aktif', public.adm_apbdp_koreksi('ta-2026', 1), false, 'belum aktif');
select pg_temp.cek('APBD-P pada TA draft', public.adm_apbdp_aktifkan('ta-2028', 1), false, 'Aktif Penuh');
select pg_temp.cek('APBD-P pagu nol', public.adm_apbdp_aktifkan('ta-2026', 0), false, 'lebih dari nol');
select pg_temp.cek('APBD-P aktif', public.adm_apbdp_aktifkan('ta-2026', 15500000000), true);
select pg_temp.cek('APBD-P dua kali', public.adm_apbdp_aktifkan('ta-2026', 15500000000), false, 'sudah aktif');
select pg_temp.cek('Koreksi pagu P sebelum sahkan', public.adm_apbdp_koreksi('ta-2026', 15600000000), true);
select pg_temp.cek('Koreksi nilai sama', public.adm_apbdp_koreksi('ta-2026', 15600000000), false, 'sama');
select pg_temp.cek('Admin tak lihat angka', public.anggaran_ringkasan('ta-2026'), false, 'Admin');
reset role;
select pg_temp.sebagai('198203152009012003','ta-2026','bendahara',null); set role authenticated;
select pg_temp.cek('SPD ubah saat menunggu sahkan ulang', public.bend_spd_efisiensi('ar-1', 1, 'x'), false, 'Sahkan ulang');
select pg_temp.cek('Buka jendela APBD-P', public.bend_jendela_atur('ta-2026','2099-01-01 10:00'), true);
select pg_temp.cek('Sub P (kurang dari pagu induk P) ', public.bend_alokasi_sub_simpan('ta-2026','{"pem-2026-1":3500000000}'), true);
select pg_temp.cek('Sub P total melebihi induk P', public.bend_alokasi_sub_simpan('ta-2026','{"pem-2026-1":9000000000}'), false, 'melebihi Pagu Induk');
reset role;
select pg_temp.sebagai('198807202012011004','ta-2026','pptk','sek-2026-1'); set role authenticated;
select pg_temp.cek('PPTK sesuaikan rekening P', public.pptk_alokasi_rek_simpan('ta-2026','pem-2026-1','[{"rekening_id":"rek-1","pagu":1750000000},{"rekening_id":"rek-3","pagu":1750000000}]'), true);
reset role;
select 'status sesudah P' k, amanda.status_seksi('ta-2026','sek-2026-1');
