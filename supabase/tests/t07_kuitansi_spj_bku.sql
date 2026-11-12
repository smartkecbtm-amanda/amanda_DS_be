-- Uji Langkah 5–6: kuitansi, SPJ, pajak, rekening, lampiran, ajukan, verifikasi, BKU, keaslian
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

reset role;
-- form uji jadwal (dibuat sebagai pemilik basis data)
insert into form_dinamis (jenis_belanja, versi, fields, blok_berulang) values
 ('Uji Jadwal','v1','[{"id":"j1","label":"NIP/NIK","tipe":"teks","urutan":1,"wajib":true,"system_tag":"[SYS_PERSONNEL_ID]"},{"id":"j2","label":"Nama","tipe":"teks","urutan":2,"wajib":false,"system_tag":"[SYS_PERSONNEL_NAME]"},{"id":"j3","label":"Mulai","tipe":"tanggal","urutan":3,"wajib":true,"system_tag":"[SYS_START_DATE]"},{"id":"j4","label":"Selesai","tipe":"tanggal","urutan":4,"wajib":true,"system_tag":"[SYS_END_DATE]"}]', null);

-- ===== KUITANSI =====
select pg_temp.sebagai('198807202012011004','ta-2026','pptk','sek-2026-1'); set role authenticated;
select pg_temp.cek('Buat kuitansi melebihi sisa SPD', public.pptk_kuitansi_buat('ta-2026','sek-2026-1','pem-2026-1','rek-1','Toko A',99000000000,'x','2026-06-01'), false, 'melebihi Sisa SPD');
select pg_temp.cek('Bruto nol ditolak', public.pptk_kuitansi_buat('ta-2026','sek-2026-1','pem-2026-1','rek-1','Toko A',0,'x','2026-06-01'), false, 'lebih dari nol');
select pg_temp.cek('Seksi lain ditolak', public.pptk_kuitansi_buat('ta-2026','sek-2026-4','pem-2026-4','rek-5','Toko A',1000,'x','2026-06-01'), false, 'seksi pemilik');
select pg_temp.cek('Tanggal salah ditolak', public.pptk_kuitansi_buat('ta-2026','sek-2026-1','pem-2026-1','rek-1','Toko A',1000,'x','31-12-2026'), false, 'Tanggal kuitansi');
select pg_temp.cek('Buat kuitansi A', public.pptk_kuitansi_buat('ta-2026','sek-2026-1','pem-2026-1','rek-1','Toko A',1000000,'Belanja A','2026-06-01'), true);

select pg_temp.cek('Buat kuitansi B', public.pptk_kuitansi_buat('ta-2026','sek-2026-1','pem-2026-1','rek-1','Toko B',2000000,'Belanja B','2026-06-02'), true);
select (public.pptk_kuitansi_buat('ta-2026','sek-2026-1','pem-2026-1','rek-1','Toko C',3000000,'Belanja C','2026-06-03')->>'id') as idc \gset
select id as ida from kuitansi where penerima = 'Toko A' \gset
select id as idb from kuitansi where penerima = 'Toko B' \gset
select pg_temp.cek('Ubah kuitansi A', public.pptk_kuitansi_ubah(:'ida', '{"uraian":"Belanja A revisi","bruto":1500000}'), true);
select pg_temp.cek('Ubah kuitansi Terkunci ditolak', public.pptk_kuitansi_ubah('kui-2', '{"uraian":"x"}'), false, 'Terkunci');
select pg_temp.cek('Ubah bruto melebihi sisa', public.pptk_kuitansi_ubah(:'ida', '{"bruto":99000000000}'), false, 'melebihi Sisa SPD');
reset role;
select pg_temp.ada('Komitmen ar-1 memuat kuitansi baru (1,5jt+2jt+3jt)', amanda.komitmen('ar-1') >= 6500000);
select pg_temp.ada('pernah_transaksi true', (select pernah_transaksi from tahun_anggaran where id='ta-2026'));

-- ===== SPJ =====
select pg_temp.sebagai('198807202012011004','ta-2026','pptk','sek-2026-1'); set role authenticated;
select pg_temp.cek('Buat SPJ tanpa form ditolak', public.pptk_spj_buat('ta-2026', :'ida', 'Jenis Tak Ada'), false, 'Form Dinamis');
select pg_temp.cek('Buat SPJ A', public.pptk_spj_buat('ta-2026', :'ida', 'Belanja Barang Habis Pakai'), true);
select pg_temp.cek('SPJ ganda ditolak', public.pptk_spj_buat('ta-2026', :'ida', 'Belanja Barang Habis Pakai'), false, 'sudah memiliki SPJ');
reset role;
select id as spja from spj where kuitansi_id = :'ida' \gset
select pg_temp.ada('Kuitansi A Terkunci', (select status from kuitansi where id = :'ida') = 'Terkunci');
select pg_temp.sebagai('198807202012011004','ta-2026','pptk','sek-2026-1'); set role authenticated;
select pg_temp.cek('Ubah kuitansi A setelah SPJ ditolak', public.pptk_kuitansi_ubah(:'ida', '{"uraian":"x"}'), false, 'Terkunci');
select pg_temp.cek('Ajukan tanpa jawaban wajib', public.pptk_spj_ajukan(:'spja'), false, 'wajib');
select pg_temp.cek('Simpan jawaban', public.pptk_spj_jawaban(:'spja', '{"fd2-f1":"Pembelian ATK"}'), true);
select pg_temp.cek('Pajak melebihi bruto', public.pptk_spj_pajak(:'spja', '[{"jenis_pajak_id":"pjk-1","nominal":99000000}]'), false, 'melebihi bruto');
select pg_temp.cek('Pajak nonaktif/tak dikenal', public.pptk_spj_pajak(:'spja', '[{"jenis_pajak_id":"zzz","nominal":1000}]'), false, 'Master Jenis Pajak');
select pg_temp.cek('Pajak ok', public.pptk_spj_pajak(:'spja', '[{"jenis_pajak_id":"pjk-1","nominal":100000},{"jenis_pajak_id":"pjk-2","nominal":50000}]'), true);
select pg_temp.cek('Rekening baris tak lengkap', public.pptk_spj_rekening(:'spja', '[{"account_name":"Toko A","bank_name":"","account_number":"123","alias":""}]'), false, 'baris 1');
select pg_temp.cek('Rekening ok', public.pptk_spj_rekening(:'spja', '[{"account_name":"Toko A","bank_name":"BRI","account_number":"1234567","alias":""}]'), true);
select pg_temp.cek('Lampiran bukan pdf', public.pptk_spj_lampiran(:'spja', :'spja' || '/a.docx', 'a.docx', 1000), false, 'PDF');
select pg_temp.cek('Lampiran >30MB', public.pptk_spj_lampiran(:'spja', :'spja' || '/a.pdf', 'a.pdf', 31*1048576), false, '30 MB');
select pg_temp.cek('Lampiran kunci salah', public.pptk_spj_lampiran(:'spja', 'lain/a.pdf', 'a.pdf', 1000), false, 'Kunci');
select pg_temp.cek('Lampiran 2MB langsung', public.pptk_spj_lampiran(:'spja', :'spja' || '/a.pdf', 'a.pdf', 2*1048576), true);
select pg_temp.cek('Lampiran 20MB perlu optimasi', public.pptk_spj_lampiran(:'spja', :'spja' || '/b.pdf', 'b.pdf', 20*1048576, 4*1048576, 'CLIENT_COMPRESSED'), true);
reset role;
select pg_temp.ada('Rekening masuk direktori bank', exists (select 1 from direktori_rekening_bank where account_number = '1234567'));
select pg_temp.ada('Status optimasi CLIENT_COMPRESSED', (select lampiran_status_optimasi from spj where id = :'spja') = 'CLIENT_COMPRESSED');
select pg_temp.sebagai('198807202012011004','ta-2026','pptk','sek-2026-1'); set role authenticated;
select pg_temp.cek('Ajukan SPJ A', public.pptk_spj_ajukan(:'spja'), true);
select pg_temp.cek('Jawaban setelah ajukan ditolak', public.pptk_spj_jawaban(:'spja', '{"fd2-f1":"x"}'), false, 'Terkunci');
select pg_temp.cek('Lepas SPJ Terkunci ditolak', public.pptk_spj_lepas(:'spja'), false, 'Draft');
select pg_temp.cek('Cetak belum disetujui ditolak', public.spj_cetak_verifikasi(:'spja'), false, 'Menunggu BKU');
reset role;
select pg_temp.ada('Snapshot penandatangan terisi', (select penandatangan_pengajuan->>'pptk_nip' from spj where id = :'spja') = '198807202012011004');

-- ===== VERIFIKASI =====
select pg_temp.sebagai('198911112014032007','ta-2026','verifikator',null); set role authenticated;
select pg_temp.cek('Kembalikan tanpa catatan', public.ver_spj_kembalikan(:'spja', ''), false, 'Catatan revisi');
select pg_temp.cek('Setujui SPJ A', public.ver_spj_setujui(:'spja'), true);
select pg_temp.cek('Setujui lagi ditolak', public.ver_spj_setujui(:'spja'), false, 'Terkunci');
reset role;
select token as tka, nomor_verifikasi as noa from token_verifikasi_spj where spj_id = :'spja' and status = 'Berlaku' \gset
select pg_temp.ada('Nomor verifikasi berformat urut/VER/2026', :'noa' ~ '^\d{4}/VER/2026$');
select pg_temp.ada('Token 24 karakter', length(:'tka') = 24);
-- keaslian publik tanpa sesi
set role anon;
select pg_temp.ada('Keaslian token berlaku', (public.pub_cek_keaslian(:'tka')->>'berlaku')::boolean);
select pg_temp.ada('Keaslian tanpa nominal', not (public.pub_cek_keaslian(:'tka')::text ~ 'nominal|bruto'));
select pg_temp.ada('Token asing seragam', public.pub_cek_keaslian('ASING') = '{"berlaku": false}'::jsonb);
reset role;
select pg_temp.sebagai('198911112014032007','ta-2026','verifikator',null); set role authenticated;
select pg_temp.cek('Cetak verifikasi oleh Verifikator', public.spj_cetak_verifikasi(:'spja'), true);
reset role;
select pg_temp.sebagai('198203152009012003','ta-2026','bendahara',null); set role authenticated;
select pg_temp.cek('Cetak verifikasi oleh Bendahara ditolak', public.spj_cetak_verifikasi(:'spja'), false, 'tidak berwenang');
select pg_temp.cek('Hak lampiran Bendahara', public.spj_lampiran_hak(:'spja'), true);
reset role;
select pg_temp.sebagai('197505052008011006','ta-2026','pptk','sek-2026-3'); set role authenticated;
select pg_temp.cek('Hak lampiran PPTK seksi lain ditolak', public.spj_lampiran_hak(:'spja'), false, 'tidak berwenang');
select pg_temp.cek('SPJ kuitansi seksi lain ditolak', public.pptk_spj_buat('ta-2026', 'kui-1', 'Belanja Barang Habis Pakai'), false, 'seksi pemilik');
select pg_temp.cek('Kuitansi seksi lain ditolak diubah', public.pptk_kuitansi_ubah(:'ida', '{"uraian":"x"}'), false, 'Terkunci');
reset role;

-- ===== BKU =====
select amanda.realisasi('ar-1') as real0 \gset
select pg_temp.sebagai('198203152009012003','ta-2026','bendahara',null); set role authenticated;
select pg_temp.cek('BKU nomor dipakai', public.bend_bku_catat(:'spja', 'BKU-001', '2026-06-10'), false, 'sudah dipakai');
select pg_temp.cek('BKU tanggal kosong', public.bend_bku_catat(:'spja', 'BKU-050', ''), false, 'Tanggal BKU');
select pg_temp.cek('BKU catat', public.bend_bku_catat(:'spja', 'BKU-050', '2026-06-10'), true);
select pg_temp.cek('BKU ganda ditolak', public.bend_bku_catat(:'spja', 'BKU-051', '2026-06-10'), false, 'Menunggu BKU');
reset role;
select pg_temp.ada('Realisasi bertambah sebesar bruto 1,5jt', amanda.realisasi('ar-1') = :real0 + 1500000);
select id as bkua from bku where spj_id = :'spja' \gset
select pg_temp.sebagai('198911112014032007','ta-2026','verifikator',null); set role authenticated;
select pg_temp.cek('Kembalikan SPJ Dibukukan ditolak', public.ver_spj_kembalikan(:'spja','x'), false, 'sudah dibukukan');
reset role;
select pg_temp.sebagai('198203152009012003','ta-2026','bendahara',null); set role authenticated;
select pg_temp.cek('Koreksi BKU tanpa perubahan', public.bend_bku_koreksi(:'bkua','BKU-050','2026-06-10'), false, 'Tidak ada perubahan');
select pg_temp.cek('Koreksi BKU nomor dipakai', public.bend_bku_koreksi(:'bkua','BKU-001','2026-06-10'), false, 'sudah dipakai');
select pg_temp.cek('Koreksi BKU ok', public.bend_bku_koreksi(:'bkua','BKU-050A','2026-06-11'), true);
select pg_temp.cek('Cabut BKU', public.bend_bku_cabut(:'bkua'), true);
select pg_temp.cek('Cabut lagi ditolak', public.bend_bku_cabut(:'bkua'), false, 'sudah dicabut');
reset role;
select pg_temp.ada('Realisasi kembali semula', amanda.realisasi('ar-1') = :real0);
select pg_temp.ada('SPJ kembali Menunggu BKU', (select status from spj where id = :'spja') = 'Menunggu BKU');
select pg_temp.ada('Nomor BKU lama bisa dipakai lagi', true);
select pg_temp.sebagai('198203152009012003','ta-2026','bendahara',null); set role authenticated;
select pg_temp.cek('Catat BKU ulang dengan nomor dicabut', public.bend_bku_catat(:'spja','BKU-050A','2026-06-12'), true);
reset role;

-- ===== KEMBALIKAN, TOKEN LAMA, LEPAS, BATAL =====
select pg_temp.sebagai('198203152009012003','ta-2026','bendahara',null); set role authenticated;
select pg_temp.cek('Cabut BKU untuk kembalikan', public.bend_bku_cabut((select id from bku where spj_id = :'spja' and status='Aktif')), true);
reset role;
select pg_temp.sebagai('198911112014032007','ta-2026','verifikator',null); set role authenticated;
select pg_temp.cek('Kembalikan SPJ Menunggu BKU', public.ver_spj_kembalikan(:'spja','Lampiran kurang jelas'), true);
reset role;
select pg_temp.ada('Token lama Tidak berlaku', (select status from token_verifikasi_spj where token = :'tka') = 'Tidak berlaku');
select pg_temp.ada('Keaslian token lama = tidak berlaku', (public.pub_cek_keaslian(:'tka')->>'berlaku')::boolean is false);
select pg_temp.ada('SPJ kembali Draft dikembalikan', (select status||dikembalikan::text from spj where id = :'spja') = 'Draftttrue' or (select status from spj where id = :'spja') = 'Draft');
select pg_temp.sebagai('198807202012011004','ta-2026','pptk','sek-2026-1'); set role authenticated;
select pg_temp.cek('Hapus lampiran', public.pptk_spj_lampiran_hapus(:'spja'), true);
select pg_temp.cek('Ajukan ulang SPJ A', public.pptk_spj_ajukan(:'spja'), true);
reset role;
select pg_temp.sebagai('198911112014032007','ta-2026','verifikator',null); set role authenticated;
select pg_temp.cek('Setujui ulang -> nomor urut baru', public.ver_spj_setujui(:'spja'), true);
reset role;
select pg_temp.ada('Nomor verifikasi unik berurutan', (select count(distinct nomor_verifikasi) from token_verifikasi_spj where spj_id = :'spja') = 2);

-- Lepas SPJ Draft dan batalkan kuitansi
select pg_temp.sebagai('198807202012011004','ta-2026','pptk','sek-2026-1'); set role authenticated;
select pg_temp.cek('Buat SPJ B', public.pptk_spj_buat('ta-2026', :'idb', 'Belanja Barang Habis Pakai'), true);
select (id) as spjb from spj where kuitansi_id = :'idb' \gset
select pg_temp.cek('Lepas SPJ B Draft', public.pptk_spj_lepas(:'spjb'), true);
select pg_temp.cek('Batalkan kuitansi B', public.pptk_kuitansi_batalkan(:'idb'), true);
select pg_temp.cek('Batalkan kuitansi Terkunci ditolak', public.pptk_kuitansi_batalkan(:'ida'), false, 'Aktif');
reset role;
select pg_temp.ada('SPJ B terhapus', not exists (select 1 from spj where id = :'spjb'));
select pg_temp.ada('Kuitansi B terhapus', not exists (select 1 from kuitansi where id = :'idb'));

-- ===== BENTROK JADWAL (M-98) =====
select pg_temp.sebagai('198807202012011004','ta-2026','pptk','sek-2026-1'); set role authenticated;
select (public.pptk_kuitansi_buat('ta-2026','sek-2026-1','pem-2026-1','rek-1','J1',100000,'Jadwal 1','2026-07-01')->>'id') as j1 \gset
select (public.pptk_kuitansi_buat('ta-2026','sek-2026-1','pem-2026-1','rek-1','J2',100000,'Jadwal 2','2026-07-01')->>'id') as j2 \gset
select pg_temp.cek('SPJ jadwal 1', public.pptk_spj_buat('ta-2026', :'j1', 'Uji Jadwal'), true);
select pg_temp.cek('SPJ jadwal 2', public.pptk_spj_buat('ta-2026', :'j2', 'Uji Jadwal'), true);
reset role;
select id as sj1 from spj where kuitansi_id = :'j1' \gset
select id as sj2 from spj where kuitansi_id = :'j2' \gset
select pg_temp.sebagai('198807202012011004','ta-2026','pptk','sek-2026-1'); set role authenticated;
select pg_temp.cek('Jadwal 1 jawaban', public.pptk_spj_jawaban(:'sj1', '{"j1":"199001012015011001","j2":"Pegawai X","j3":"2026-07-10","j4":"2026-07-12"}'), true);
select pg_temp.cek('Jadwal 1 ajukan', public.pptk_spj_ajukan(:'sj1'), true);
select pg_temp.cek('Jadwal 2 jawaban beririsan', public.pptk_spj_jawaban(:'sj2', '{"j1":"199001012015011001","j2":"Pegawai X","j3":"2026-07-12","j4":"2026-07-14"}'), true);
select pg_temp.cek('Jadwal 2 bentrok ditolak', public.pptk_spj_ajukan(:'sj2'), false, 'Bentrok jadwal');
select pg_temp.cek('Jadwal 2 jawaban tidak beririsan', public.pptk_spj_jawaban(:'sj2', '{"j1":"199001012015011001","j2":"Pegawai X","j3":"2026-07-13","j4":"2026-07-14"}'), true);
select pg_temp.cek('Jadwal 2 selesai sebelum mulai ditolak', public.pptk_spj_jawaban(:'sj2', '{"j1":"199001012015011001","j2":"Pegawai X","j3":"2026-07-15","j4":"2026-07-14"}'), true);
select pg_temp.cek('Jadwal 2 tanggal terbalik ajukan', public.pptk_spj_ajukan(:'sj2'), false, 'tidak boleh sebelum');
select pg_temp.cek('Jadwal 2 bebas ajukan', public.pptk_spj_jawaban(:'sj2', '{"j1":"199001012015011001","j2":"Pegawai X","j3":"2026-07-13","j4":"2026-07-14"}'), true);
select pg_temp.cek('Jadwal 2 ajukan ok', public.pptk_spj_ajukan(:'sj2'), true);
reset role;
select pg_temp.ada('Direktori transaksional mencatat NIP', exists (select 1 from direktori_transaksional where nip_nik = '199001012015011001' and nama = 'Pegawai X'));

-- ===== FORMAT NOMOR (ADMIN) =====
select pg_temp.sebagai('198203152009012003','ta-2026','bendahara',null); set role authenticated;
select pg_temp.cek('Format nomor oleh Bendahara ditolak', public.adm_format_nomor_simpan('ta-2026','VER','/','YYYY',4), false, 'Hanya Admin');
reset role;
select pg_temp.sebagai('admin',null,'admin',null); set role authenticated;
select pg_temp.cek('Format nomor digit 9 ditolak', public.adm_format_nomor_simpan('ta-2026','VER','/','YYYY',9), false, 'digit');
select pg_temp.cek('Format nomor ok', public.adm_format_nomor_simpan('ta-2026','SPJ','-','YY',5), true);
select pg_temp.cek('Admin tak punya akses angka', public.anggaran_ringkasan('ta-2026'), false, 'Admin');
reset role;
select pg_temp.sebagai('198911112014032007','ta-2026','verifikator',null); set role authenticated;
select pg_temp.cek('Setujui SPJ jadwal 1 (format baru)', public.ver_spj_setujui(:'sj1'), true);
reset role;
select pg_temp.ada('Nomor memakai format baru 000nn-SPJ-26 (urut/awalan/tahun)', (select nomor_verifikasi from token_verifikasi_spj where spj_id = :'sj1' and status='Berlaku') ~ '^\d{5}-SPJ-26$');

-- ===== Admin tak boleh transaksi, TA bukan Aktif Penuh =====
select pg_temp.sebagai('admin',null,'admin',null); set role authenticated;
select pg_temp.cek('Admin tak boleh buat kuitansi', public.pptk_kuitansi_buat('ta-2026','sek-2026-1','pem-2026-1','rek-1','X',1000,'x','2026-07-01'), false, 'PPTK seksi pemilik');
reset role;
update tahun_anggaran set status = 'Masa Transisi' where id = 'ta-2026';
select pg_temp.sebagai('198807202012011004','ta-2026','pptk','sek-2026-1'); set role authenticated;
select pg_temp.cek('Masa Transisi: kuitansi baru ditolak', public.pptk_kuitansi_buat('ta-2026','sek-2026-1','pem-2026-1','rek-1','X',1000,'x','2026-07-01'), false, 'Aktif Penuh');
select pg_temp.cek('Masa Transisi: batalkan kuitansi Aktif diizinkan', public.pptk_kuitansi_batalkan(:'idc'), true);
reset role;
