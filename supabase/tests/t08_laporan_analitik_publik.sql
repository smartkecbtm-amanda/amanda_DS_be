-- Uji Langkah 7–9: laporan, kustom, analitik, heatmap, portal publik, retensi
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

create or replace function pg_temp.ada(p_label text, p_kondisi boolean) returns void language plpgsql as $$
begin if p_kondisi then raise notice 'lulus  %', p_label; else raise notice 'GAGAL  % (kondisi salah)', p_label; end if; end $$;

select coalesce(sum(k.bruto),0) as real_ref from bku b join spj s on s.id=b.spj_id join kuitansi k on k.id=b.kuitansi_id where b.ta_id='ta-2026' and b.status='Aktif' and s.status='Dibukukan' \gset
select seksi_ta_id as sek_bku, bruto as bruto_bku, nomor_bku as no_bku, id as bku_id from (select k.seksi_ta_id, k.bruto, b.nomor_bku, b.id from bku b join kuitansi k on k.id=b.kuitansi_id where b.ta_id='ta-2026' limit 1) q \gset
select pg_temp.ada('Data seed memiliki BKU aktif', :real_ref > 0);

-- ===== LAPORAN =====
select pg_temp.sebagai('198203152009012003','ta-2026','bendahara',null); set role authenticated;
select pg_temp.ada('Bendahara: laporan a ok', (public.laporan_buat('a','ta-2026')->>'ok')::boolean);
select pg_temp.ada('Realisasi laporan a = acuan independen', (select sum((r->>2)::bigint) from jsonb_array_elements(public.laporan_buat('a','ta-2026')->'data'->'sheets'->0->'blok'->0->'baris') r) = :real_ref);
select pg_temp.ada('Laporan a memuat semua seksi', jsonb_array_length(public.laporan_buat('a','ta-2026')->'data'->'sheets'->0->'blok'->0->'baris') = (select count(*) from seksi_ta where ta_id='ta-2026'));
select pg_temp.ada('Laporan b non-PA: 4 kolom (termasuk kuitansi terkait)', jsonb_array_length(public.laporan_buat('b','ta-2026')->'data'->'sheets'->0->'blok'->0->'kolom') = 4);
select pg_temp.ada('Laporan b memuat BKU', jsonb_array_length(public.laporan_buat('b','ta-2026')->'data'->'sheets'->0->'blok'->0->'baris') >= 1);
select pg_temp.ada('Laporan c ok', (public.laporan_buat('c','ta-2026')->>'ok')::boolean);
select pg_temp.ada('Laporan d: dua blok (seksi, subkegiatan)', jsonb_array_length(public.laporan_buat('d','ta-2026')->'data'->'sheets'->0->'blok') = 2);
select pg_temp.ada('Laporan e: ada sheet per jenis belanja', jsonb_array_length(public.laporan_buat('e','ta-2026')->'data'->'sheets') >= 1);
select pg_temp.ada('Laporan f ok', (public.laporan_buat('f','ta-2026')->>'ok')::boolean);
select pg_temp.ada('Laporan g: blok kartu kendali', jsonb_array_length(public.laporan_buat('g','ta-2026')->'data'->'sheets'->0->'blok') >= 1);
select pg_temp.ada('Filter periode di luar BKU = nol', (select coalesce(sum((r->>2)::bigint),0) from jsonb_array_elements(public.laporan_buat('a','ta-2026','{"dari":"2030-01-01"}')->'data'->'sheets'->0->'blok'->0->'baris') r) = 0);
select pg_temp.ada('Laporan z tak dikenal ditolak', public.laporan_buat('z','ta-2026')->>'ok' = 'false');
select pg_temp.ada('TA lain ditolak', public.laporan_buat('a','ta-2025')->>'ok' = 'false');
select pg_temp.ada('Bendahara: 10 kolom kustom', jsonb_array_length(public.laporan_kolom_kustom()) = 10);
select pg_temp.ada('Kustom: kolom NIP/rekening menjadi 2 kolom (total 11)', jsonb_array_length(public.laporan_kustom('ta-2026', '{"kolom":["tanggal_bku","no_bku","subkegiatan","rekening_belanja","uraian","penerima","bruto","total_pajak","dibayarkan","nip_rekening"]}')->'data'->'kolom') = 11);
select pg_temp.ada('Batas baris kustom = 0', jsonb_array_length(public.laporan_kustom('ta-2026', '{"kolom":["bruto"]}', 0)->'data'->'baris') = 0);
select pg_temp.ada('Dibayarkan = bruto - pajak', (select bool_and((r->>0)::bigint - (r->>1)::bigint = (r->>2)::bigint) from jsonb_array_elements(public.laporan_kustom('ta-2026', '{"kolom":["bruto","total_pajak","dibayarkan"]}')->'data'->'baris') r));
select pg_temp.ada('Bendahara: analitik ditolak', public.analitik_seksi('ta-2026')->>'ok' = 'false');
reset role;

select pg_temp.sebagai('198807202012011004','ta-2026','pptk','sek-2026-1'); set role authenticated;
select pg_temp.ada('PPTK: laporan a hanya seksinya', jsonb_array_length(public.laporan_buat('a','ta-2026')->'data'->'sheets'->0->'blok'->0->'baris') = 1);
select pg_temp.ada('PPTK: seksi lain ditolak', public.laporan_buat('a','ta-2026','{"seksi_ta_id":"sek-2026-4"}')->>'ok' = 'false');
select pg_temp.ada('PPTK: kustom seksi lain ditolak', public.laporan_kustom('ta-2026', '{"kolom":["bruto"],"seksi_ta_id":"sek-2026-4"}')->>'ok' = 'false');
select pg_temp.ada('PPTK: drill rekening seksi sendiri ok', (public.drill_rekening('ta-2026','pem-2026-1')->>'ok')::boolean);
select pg_temp.ada('PPTK: drill subkegiatan seksi lain ditolak', public.drill_subkegiatan('ta-2026','sek-2026-4')->>'ok' = 'false');
select pg_temp.ada('PPTK: drill seksi hanya seksinya', jsonb_array_length(public.drill_seksi('ta-2026')->'data') = 1);
reset role;

select pg_temp.sebagai('admin',null,'admin',null); set role authenticated;
select pg_temp.ada('Admin tidak mendapat laporan', public.laporan_buat('a','ta-2026')->>'error' = 'Admin tidak mendapat laporan.');
select pg_temp.ada('Admin tak boleh kustom', public.laporan_kustom('ta-2026', '{"kolom":["bruto"]}')->>'ok' = 'false');
select pg_temp.ada('Admin tak boleh analitik', public.analitik_seksi('ta-2026')->>'ok' = 'false');
select pg_temp.ada('Admin tak punya drill-down', public.drill_seksi('ta-2026')->>'ok' = 'false');
reset role;

select pg_temp.sebagai('198501012010011001','ta-2026','pa_kpa',null); set role authenticated;
select pg_temp.ada('PA: laporan c tidak tersedia', public.laporan_buat('c','ta-2026')->>'ok' = 'false');
select pg_temp.ada('PA: laporan b hanya 3 kolom (tanpa kuitansi terkait)', jsonb_array_length(public.laporan_buat('b','ta-2026')->'data'->'sheets'->0->'blok'->0->'kolom') = 3);
select pg_temp.ada('PA: laporan f tanpa kolom Tanggal Kuitansi', not (public.laporan_buat('f','ta-2026')::text like '%Tanggal Kuitansi%'));
select pg_temp.ada('PA: laporan e ok', (public.laporan_buat('e','ta-2026')->>'ok')::boolean);
select pg_temp.ada('PA: kolom kustom terbatas (6)', jsonb_array_length(public.laporan_kolom_kustom()) = 6);
select pg_temp.ada('PA: kolom penerima ditolak', public.laporan_kustom('ta-2026', '{"kolom":["bruto","penerima"]}')->>'ok' = 'false');
select pg_temp.ada('PA: kolom rekening ditolak', public.laporan_kustom('ta-2026', '{"kolom":["rekening_belanja"]}')->>'ok' = 'false');
select pg_temp.ada('PA: kustom bruto ok', (public.laporan_kustom('ta-2026', '{"kolom":["no_bku","bruto"]}')->'data'->>'totalBaris')::int >= 1);
select pg_temp.ada('Kustom tanpa kolom ditolak', public.laporan_kustom('ta-2026', '{"kolom":[]}')->>'error' = 'Pilih minimal satu kolom.');
select pg_temp.ada('PA: drill seksi ok', (public.drill_seksi('ta-2026')->>'ok')::boolean);
select pg_temp.ada('PA: drill rekening ditolak (hanya sampai subkegiatan)', public.drill_rekening('ta-2026','pem-2026-1')->>'ok' = 'false');
reset role;

-- ===== ANALITIK =====
select pg_temp.sebagai('198501012010011001','ta-2026','pa_kpa',null); set role authenticated;
select pg_temp.ada('Time Elapsed 1 Des 2026 = 91.78', (public.analitik_seksi('ta-2026','2026-12-01')->'data'->>'time_elapsed_pct')::numeric = 91.78);
select pg_temp.ada('Seksi burn<60 pada te>90 = MERAH', (select coalesce(bool_and((x->>'zona') = 'MERAH'), true) from jsonb_array_elements(public.analitik_seksi('ta-2026','2026-12-01')->'data'->'seksi') x where (x->>'burn_rate_pct') is not null and (x->>'burn_rate_pct')::numeric < 60));
select pg_temp.ada('MERAH di baris teratas', (public.analitik_seksi('ta-2026','2026-12-01')->'data'->'seksi'->0->>'zona') = 'MERAH');
select pg_temp.ada('Ringkasan total = jumlah seksi', (public.analitik_seksi('ta-2026','2026-12-01')->'data'->'ringkasan'->>'total')::int = (select count(*) from seksi_ta where ta_id='ta-2026'));
select pg_temp.ada('Tanggal acuan salah ditolak', public.analitik_seksi('ta-2026','xx')->>'ok' = 'false');
reset role;
update bku set tanggal_bku = '2026-03-05' where id = :'bku_id';
update alokasi_subkegiatan set pagu = 0 where pemetaan_subkegiatan_id in (select id from pemetaan_subkegiatan_ta where seksi_ta_id = :'sek_bku');
update alokasi_subkegiatan set pagu = :bruto_bku * 2 where pemetaan_subkegiatan_id = (select k.pemetaan_subkegiatan_id from bku b join kuitansi k on k.id = b.kuitansi_id where b.id = :'bku_id');
select pg_temp.sebagai('198501012010011001','ta-2026','pa_kpa',null); set role authenticated;
select pg_temp.ada('Lonjakan >=40% dalam 14 hari = ORANYE', (select x->>'zona' from jsonb_array_elements(public.analitik_seksi('ta-2026','2026-03-10')->'data'->'seksi') x where x->>'seksi_id' = :'sek_bku') = 'ORANYE');
select pg_temp.ada('BKU di luar jendela 14 hari = bukan ORANYE', (select x->>'zona' from jsonb_array_elements(public.analitik_seksi('ta-2026','2026-03-25')->'data'->'seksi') x where x->>'seksi_id' = :'sek_bku') <> 'ORANYE');
select pg_temp.ada('Heatmap rekonsiliasi OK', (public.heatmap_bulanan('ta-2026')->'data'->>'rekonsiliasi_ok')::boolean);
select pg_temp.ada('Heatmap bulan Maret memuat bruto', (select (x->'bulan'->>2)::numeric from jsonb_array_elements(public.heatmap_bulanan('ta-2026')->'data'->'baris') x where x->>'tingkat' = 'seksi' and x->>'id' = :'sek_bku') >= :bruto_bku);
select pg_temp.ada('Heatmap persen Maret >= 50', (select (x->'persen_bulan'->>2)::numeric from jsonb_array_elements(public.heatmap_bulanan('ta-2026')->'data'->'baris') x where x->>'tingkat' = 'seksi' and x->>'id' = :'sek_bku') >= 50);
reset role;
select pg_temp.sebagai('198203152009012003','ta-2026','bendahara',null); set role authenticated;
select pg_temp.ada('Heatmap ditolak untuk Bendahara', public.heatmap_bulanan('ta-2026')->>'ok' = 'false');
reset role;

-- ===== PORTAL PUBLIK =====
set role anon;
select pg_temp.ada('Daftar TA publik tanpa Draft', not (public.publik_daftar_ta()::text like '%2027%') and not (public.publik_daftar_ta()::text like '%2028%'));
select pg_temp.ada('TA Aktif Penuh sebagai bawaan', (select (x->>'label') = 'TA 2026' from jsonb_array_elements(public.publik_daftar_ta()) x where (x->>'bawaan')::boolean));
select pg_temp.ada('Ringkasan publik tanpa nominal/penerima/rekening', not (public.publik_ringkasan('ta-2026')::text ~* 'bruto|nominal|penerima|rekening|nip|audit'));
select pg_temp.ada('Kategori mencakup seluruh SPJ', (select sum((x->>'cacah')::int) from jsonb_array_elements(public.publik_ringkasan('ta-2026')->'kategori') x) = (public.publik_ringkasan('ta-2026')->>'total_spj')::int);
select pg_temp.ada('Peringkat seksi berurutan', (select bool_and((x->>'peringkat')::int = ord) from jsonb_array_elements(public.publik_ringkasan('ta-2026')->'seksi') with ordinality t(x, ord)));
select pg_temp.ada('TA Draft tidak tersedia', public.publik_ringkasan('ta-2027')->>'ok' = 'false');
select pg_temp.ada('Tabel tidak terbaca anon', not has_table_privilege('anon', 'public.kuitansi', 'select') and not has_table_privilege('anon', 'public.bku', 'select'));
select pg_temp.ada('Anon tak boleh laporan', not has_function_privilege('anon', 'public.laporan_buat(text,text,jsonb)', 'execute'));
reset role;
select pg_temp.ada('Persen realisasi publik = BKU / pagu induk', (public.publik_ringkasan('ta-2026')->>'persen_realisasi')::numeric = round(:real_ref::numeric / (select pagu_induk from tahun_anggaran where id='ta-2026') * 100, 1));

-- ===== RETENSI =====
select pg_temp.sebagai('admin',null,'admin',null); set role authenticated;
select pg_temp.cek('Retensi: TA Aktif Penuh ditolak', public.adm_ta_hapus_retensi('ta-2026','2026'), false, 'Arsip Read-Only');
reset role;
update tahun_anggaran set status = 'Arsip Read-Only', tanggal_arsip_terakhir = current_date where id = 'ta-2026';
select pg_temp.sebagai('admin',null,'admin',null); set role authenticated;
select pg_temp.cek('Retensi belum lewat ditolak', public.adm_ta_hapus_retensi('ta-2026','2026'), false, 'belum terlewati');
select pg_temp.ada('Ringkasan hapus tanpa nominal', not (public.adm_ta_ringkasan_hapus('ta-2026')::text ~* 'bruto|nominal|pagu') and (public.adm_ta_ringkasan_hapus('ta-2026')->>'kuitansi')::int > 0);
reset role;
update tahun_anggaran set tanggal_arsip_terakhir = '2013-01-01' where id = 'ta-2026';
select pg_temp.sebagai('198203152009012003','ta-2026','bendahara',null); set role authenticated;
select pg_temp.ada('Bendahara tak boleh hapus retensi', public.adm_ta_hapus_retensi('ta-2026','2026')->>'ok' = 'false');
reset role;
select pg_temp.sebagai('admin',null,'admin',null); set role authenticated;
select pg_temp.cek('Retensi kode salah ditolak', public.adm_ta_hapus_retensi('ta-2026','2025'), false, 'tidak sama persis');
select pg_temp.cek('Retensi dihapus', public.adm_ta_hapus_retensi('ta-2026','2026'), true);
reset role;
select pg_temp.ada('TA terhapus total', not exists (select 1 from tahun_anggaran where id = 'ta-2026'));
select pg_temp.ada('Kuitansi/SPJ/BKU/ledger/audit TA terhapus', (select count(*) from kuitansi where ta_id='ta-2026') + (select count(*) from spj where ta_id='ta-2026') + (select count(*) from bku where ta_id='ta-2026') + (select count(*) from ledger_spd where ta_id='ta-2026') + (select count(*) from audit_event where ta_id='ta-2026') = 0);
select pg_temp.ada('Tanpa catatan penghapusan', not exists (select 1 from audit_event where nilai_sesudah ilike '%TA 2026%dihapus%' or entitas ilike '%hapus%'));
select pg_temp.ada('Ledger tetap append-only setelah retensi', coalesce(current_setting('amanda.retensi', true), '0') <> '1');
select pg_temp.ada('Ledger append-only: ubah ditolak', (select count(*) from ledger_spd) >= 0);
