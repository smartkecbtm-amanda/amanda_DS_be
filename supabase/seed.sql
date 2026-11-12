-- Dibangkitkan dari src/data/sampleData.ts. Kata sandi akun uji: amanda123 (hash bcrypt).
begin;
insert into sotk (id, nama_unit, tmt_mulai, tmt_selesai, dasar_hukum, pengganti_dari_id, status_versi) values
  ('sotk-1', 'Sekretariat', '2026-01-01', null, 'SK Bupati No. 1/2026', null, 'Aktif'),
  ('sotk-2', 'Seksi Perencanaan', '2026-01-01', null, 'SK Bupati No. 1/2026', null, 'Aktif'),
  ('sotk-3', 'Seksi Keuangan', '2026-01-01', null, 'SK Bupati No. 1/2026', null, 'Aktif'),
  ('sotk-4', 'Seksi Pengadaan Barang dan Jasa', '2026-01-01', null, 'SK Bupati No. 1/2026', null, 'Aktif'),
  ('sotk-5', 'Seksi Pelayanan Publik', '2026-01-01', null, 'SK Bupati No. 1/2026', null, 'Aktif');
insert into personel (id, gelar_depan, nama, gelar_belakang, nip, nik, pangkat, tmt, no_whatsapp) values
  ('p-1', '', 'Hendra Wijaya', 'S.E., M.Si.', '198501012010011001', '', 'Penata Tk. I / III-d', '2020-01-01', '+6281234567001'),
  ('p-2', 'Dr.', 'Siti Rahmawati', 'M.Si.', '198203152009012003', '', 'Penata / III-c', '2018-07-01', '+6281234567002'),
  ('p-3', '', 'Budi Santoso', 'S.T.', '198807202012011004', '', 'Penata Muda Tk. I / III-b', '2019-03-01', '+6281234567003'),
  ('p-4', '', 'Maya Lestari', 'S.E.', '199002102015042005', '', 'Penata Muda / III-a', '2021-01-01', '+6281234567004'),
  ('p-5', '', 'Rahmat Hidayat', 'S.Sos.', '197505052008011006', '', 'Penata / III-c', '2016-01-01', '+6281234567005'),
  ('p-6', '', 'Dewi Anggraini', 'S.H.', '198911112014032007', '', 'Penata Muda Tk. I / III-b', '2020-07-01', '+6281234567006'),
  ('p-7', '', 'Agus Prasetiyo', 'S.T., M.T.', '198601252011011008', '', 'Penata / III-c', '2017-01-01', '+6281234567007'),
  ('p-8', '', 'Nina Marlina', '', '', '3210014503900001', '—', '2022-01-01', '+6281234567008'),
  ('p-9', '', 'Eko Saputra', 'S.Pd.', '199408122018031009', '', 'Pengatur / II-c', '2018-03-01', '+6281234567009'),
  ('p-10', '', 'Yuni Astuti', '', '', '3210014503900002', '—', '2023-01-01', '+6281234567010');
insert into riwayat_pangkat (id, personel_id, pangkat, gelar_depan, gelar_belakang, tmt_mulai, tmt_selesai) values
  ('ph-1', 'p-1', 'Penata Muda / III-a', '', 'S.E.', '2015-01-01', '2020-01-01'),
  ('ph-2', 'p-1', 'Penata Tk. I / III-d', '', 'S.E., M.Si.', '2020-01-01', null),
  ('ph-3', 'p-2', 'Penata Muda / III-a', 'Dr.', 'M.Si.', '2014-01-01', '2018-07-01'),
  ('ph-4', 'p-2', 'Penata / III-c', 'Dr.', 'M.Si.', '2018-07-01', null),
  ('ph-5', 'p-3', 'Penata Muda Tk. I / III-b', '', 'S.T.', '2019-03-01', null),
  ('ph-6', 'p-4', 'Penata Muda / III-a', '', 'S.E.', '2021-01-01', null),
  ('ph-7', 'p-5', 'Penata / III-c', '', 'S.Sos.', '2016-01-01', null),
  ('ph-8', 'p-6', 'Penata Muda Tk. I / III-b', '', 'S.H.', '2020-07-01', null),
  ('ph-9', 'p-7', 'Penata / III-c', '', 'S.T., M.T.', '2017-01-01', null),
  ('ph-10', 'p-8', '—', '', '', '2022-01-01', null);
insert into akun_login (id, personel_id, username, kata_sandi_hash, status, failed_attempts, locked, is_admin) values
  ('acc-admin', null, 'admin', extensions.crypt('amanda123', extensions.gen_salt('bf')), 'ACTIVE', 0, false, true),
  ('acc-1', 'p-1', '198501012010011001', extensions.crypt('amanda123', extensions.gen_salt('bf')), 'ACTIVE', 0, false, false),
  ('acc-2', 'p-2', '198203152009012003', extensions.crypt('amanda123', extensions.gen_salt('bf')), 'ACTIVE', 0, false, false),
  ('acc-3', 'p-3', '198807202012011004', extensions.crypt('amanda123', extensions.gen_salt('bf')), 'ACTIVE', 0, false, false),
  ('acc-4', 'p-4', '199002102015042005', extensions.crypt('amanda123', extensions.gen_salt('bf')), 'ACTIVE', 0, false, false),
  ('acc-5', 'p-5', '197505052008011006', extensions.crypt('amanda123', extensions.gen_salt('bf')), 'ACTIVE', 0, false, false),
  ('acc-6', 'p-6', '198911112014032007', extensions.crypt('amanda123', extensions.gen_salt('bf')), 'ACTIVE', 0, false, false),
  ('acc-7', 'p-7', '198601252011011008', extensions.crypt('amanda123', extensions.gen_salt('bf')), 'NON-ACTIVE', 0, false, false),
  ('acc-8', 'p-8', '3210014503900001', extensions.crypt('amanda123', extensions.gen_salt('bf')), 'ACTIVE', 0, false, false);
insert into akun_pengawas (id, nama_lengkap, instansi_asal, nomor_surat_tugas, tanggal_surat_tugas, email, tanggal_akhir_akses, kata_sandi_hash, status, failed_attempts, locked) values
  ('aud-1', 'Rizal Fauzan, S.E., M.Si.', 'Inspektorat Daerah Kab. Balangan', '003/INSPEKTORAT/2026', '2026-02-01', 'rizal.auditor@balangankab.go.id', '2026-12-31', extensions.crypt('amanda123', extensions.gen_salt('bf')), 'ACTIVE', 0, false),
  ('aud-2', 'Lestari Pujiati, S.Sos., M.Si.', 'BPKP Perwakilan Kalsel', '045/BPKP/KSL/2026', '2026-03-10', 'lestari.auditor@bpkp.go.id', '2026-10-11', extensions.crypt('amanda123', extensions.gen_salt('bf')), 'ACTIVE', 0, false);
insert into subkegiatan (id, kode, nama, rincian, status) values
  ('sub-1', '2.01.2.06.01.01', 'Perencanaan, Penganggaran, dan Evaluasi Kinerja', 'Dukungan manajemen', 'Aktif'),
  ('sub-2', '2.01.2.06.02.01', 'Administrasi Keuangan', 'Dukungan manajemen', 'Aktif'),
  ('sub-3', '2.01.2.06.03.01', 'Penatausahaan dan Pertanggungjawaban', 'Dukungan manajemen', 'Aktif'),
  ('sub-4', '2.02.2.01.01.01', 'Pengadaan Barang dan Jasa', 'Pelayanan publik', 'Aktif'),
  ('sub-5', '2.03.2.04.01.01', 'Pelayanan Administrasi Umum', 'Pelayanan publik', 'Aktif');
insert into rekening_belanja (id, kode_rekening, nama, rincian, status) values
  ('rek-1', '5.1.02.02.6.2.01.01', 'Belanja honorarium', '', 'Aktif'),
  ('rek-2', '5.1.02.02.6.2.01.02', 'Belanja kegiatan', '', 'Aktif'),
  ('rek-3', '5.1.02.01.6.1.01.01', 'Belanja pegawai', '', 'Aktif'),
  ('rek-4', '5.2.12.01.6.1.01.01', 'Belanja perjalanan dinas', '', 'Aktif'),
  ('rek-5', '5.2.02.01.6.1.06.01', 'Belanja barang habis pakai', '', 'Aktif'),
  ('rek-6', '5.2.12.02.6.1.02.01', 'Belanja jasa konsultan', '', 'Aktif');
insert into jenis_pajak (id, kode, nama_jenis_pajak, status) values
  ('pjk-1', 'PPh21', 'Pajak Penghasilan Pasal 21', 'Aktif'),
  ('pjk-2', 'PPh22', 'Pajak Penghasilan Pasal 22', 'Aktif'),
  ('pjk-3', 'PPh23', 'Pajak Penghasilan Pasal 23', 'Aktif'),
  ('pjk-4', 'PPN', 'Pajak Pertambahan Nilai', 'Aktif');
insert into form_dinamis (id, jenis_belanja, versi, fields, blok_berulang, tanggal_dibuat) values
  ('fd-1', 'Belanja Perjalanan Dinas', 'v1', '[{"id":"fd1-f1","label":"Uraian","tipe":"teks","urutan":1,"wajib":true,"system_tag":null},{"id":"fd1-f2","label":"Seksi","tipe":"teks","urutan":2,"wajib":true,"system_tag":null},{"id":"fd1-f3","label":"Nomor Surat Perintah Tugas","tipe":"teks","urutan":3,"wajib":true,"system_tag":null},{"id":"fd1-f4","label":"Tanggal Surat Perintah Tugas","tipe":"tanggal","urutan":4,"wajib":true,"system_tag":null},{"id":"fd1-f5","label":"Daerah Tujuan","tipe":"teks","urutan":5,"wajib":true,"system_tag":null},{"id":"fd1-f6","label":"Tanggal Berangkat","tipe":"tanggal","urutan":6,"wajib":true,"system_tag":"[SYS_START_DATE]"},{"id":"fd1-f7","label":"Tanggal Kembali","tipe":"tanggal","urutan":7,"wajib":true,"system_tag":"[SYS_END_DATE]"},{"id":"fd1-f8","label":"Uang Harian Per Hari","tipe":"angka","urutan":8,"wajib":false,"system_tag":null}]'::jsonb, '{"id":"fd1-blok1","nama":"Pelaku","fields":[{"id":"fd1-bf1","label":"NIP/NIK","tipe":"teks","urutan":1,"wajib":true,"system_tag":"[SYS_PERSONNEL_ID]"},{"id":"fd1-bf2","label":"Nama","tipe":"teks","urutan":2,"wajib":true,"system_tag":"[SYS_PERSONNEL_NAME]"},{"id":"fd1-bf3","label":"Golongan Pangkat","tipe":"teks","urutan":3,"wajib":false,"system_tag":null}]}'::jsonb, '2026-01-05'),
  ('fd-2', 'Belanja Barang Habis Pakai', 'v1', '[{"id":"fd2-f1","label":"Uraian","tipe":"teks","urutan":1,"wajib":true,"system_tag":null},{"id":"fd2-f2","label":"Jumlah Item","tipe":"angka","urutan":2,"wajib":false,"system_tag":null}]'::jsonb, null, '2026-01-05'),
  ('fd-3', 'Belanja Jasa Konsultan', 'v1', '[{"id":"fd3-f1","label":"Uraian","tipe":"teks","urutan":1,"wajib":true,"system_tag":null},{"id":"fd3-f2","label":"Nama Konsultan","tipe":"teks","urutan":2,"wajib":true,"system_tag":null},{"id":"fd3-f3","label":"NIP/NIK Konsultan","tipe":"teks","urutan":3,"wajib":false,"system_tag":"[SYS_PERSONNEL_ID]"},{"id":"fd3-f4","label":"Nama Kontak","tipe":"teks","urutan":4,"wajib":false,"system_tag":"[SYS_PERSONNEL_NAME]"}]'::jsonb, null, '2026-01-05');
insert into konfigurasi (kunci, nilai) values
  ('template_kuitansi', '{"nama_instansi":"Pemerintah Daerah Contoh","judul_dokumen":"KWITANSI","tempat_penerima":"Contoh Kota","terima_dari":"BENDAHARA PENGELUARAN PEMERINTAH DAERAH CONTOH","logo_berkas":null,"berkas_doc":null}'::jsonb),
  ('template_verifikasi', '{"nama_instansi":"Pemerintah Daerah Contoh","judul_dokumen":"LEMBAR VERIFIKASI PENCAIRAN BELANJA","subjudul":"Hasil Verifikasi Surat Pertanggungjawaban (SPJ)","label_nomor":"Nomor Verifikasi","label_tanggal":"Tanggal Verifikasi","label_seksi":"Seksi","label_subkegiatan":"Sub Kegiatan","label_rekening":"Kode Rekening Belanja","label_uraian":"Uraian","label_bruto":"Uang Sebanyak","label_penerima":"Diterima Oleh","label_rekening_penerima":"Rekening Penerima","label_pajak":"Informasi Potongan Pajak","label_total_pajak":"Jumlah Potongan","label_dibayarkan":"Jumlah yang Dibayarkan","label_verifikator":"Verifikator","teks_pembuka":"Berkas ini telah diverifikasi sepenuhnya. Seluruh dokumen dan data pendukung dinyatakan valid dan lengkap, sehingga siap diproses untuk pencairan dana berdasarkan rincian berikut:","teks_penutup":"Berkas ini sah selama kode QR menampilkan status Berlaku. Segala bentuk pemalsuan atau manipulasi data dalam berkas ini dapat dikenakan sanksi sesuai ketentuan yang berlaku.","teks_qr":"Keaslian dapat diperiksa dengan memindai kode QR pada lembar ini.","logo_berkas":null,"stempel_berkas":null}'::jsonb);
insert into tahun_anggaran (id, tahun, pagu_induk, status, mode_apbd_p, pagu_induk_perubahan, tanggal_arsip_terakhir, pernah_transaksi) values
  ('ta-2026', '2026', 15000000000, 'Aktif Penuh', false, null, null, true),
  ('ta-2025', '2025', 13500000000, 'Arsip Read-Only', false, null, '2026-01-15', true),
  ('ta-2027', '2027', 12000000000, 'Draft', false, null, null, false),
  ('ta-2024', '2024', 12000000000, 'Masa Transisi', false, null, null, true),
  ('ta-2028', '2028', 10000000000, 'Draft', false, null, null, true);
insert into seksi_ta (id, ta_id, sotk_id, nama_snapshot, tmt_mulai, tmt_selesai, status) values
  ('sek-2026-1', 'ta-2026', 'sotk-1', 'Sekretariat', '2026-01-01', null, 'Aktif'),
  ('sek-2026-2', 'ta-2026', 'sotk-2', 'Seksi Perencanaan', '2026-01-01', null, 'Aktif'),
  ('sek-2026-3', 'ta-2026', 'sotk-3', 'Seksi Keuangan', '2026-01-01', null, 'Aktif'),
  ('sek-2026-4', 'ta-2026', 'sotk-4', 'Seksi Pengadaan Barang dan Jasa', '2026-01-01', null, 'Aktif'),
  ('sek-2025-1', 'ta-2025', 'sotk-1', 'Sekretariat', '2025-01-01', null, 'Aktif'),
  ('sek-2025-2', 'ta-2025', 'sotk-2', 'Seksi Perencanaan (Lama)', '2025-01-01', null, 'Aktif'),
  ('sek-2027-1', 'ta-2027', 'sotk-1', 'Sekretariat', '2027-01-01', null, 'Aktif'),
  ('sek-2027-2', 'ta-2027', 'sotk-3', 'Seksi Keuangan', '2027-01-01', null, 'Aktif'),
  ('sek-2024-1', 'ta-2024', 'sotk-1', 'Sekretariat', '2024-01-01', null, 'Aktif'),
  ('sek-2024-2', 'ta-2024', 'sotk-4', 'Seksi Pengadaan Barang dan Jasa', '2024-01-01', null, 'Aktif');
insert into pemetaan_subkegiatan_ta (id, ta_id, seksi_ta_id, subkegiatan_id, kode_snapshot, nama_snapshot) values
  ('pem-2026-1', 'ta-2026', 'sek-2026-1', 'sub-1', '2.01.2.06.01.01', 'Perencanaan, Penganggaran, dan Evaluasi Kinerja'),
  ('pem-2026-2', 'ta-2026', 'sek-2026-2', 'sub-2', '2.01.2.06.02.01', 'Administrasi Keuangan'),
  ('pem-2026-3', 'ta-2026', 'sek-2026-3', 'sub-3', '2.01.2.06.03.01', 'Penatausahaan dan Pertanggungjawaban'),
  ('pem-2026-4', 'ta-2026', 'sek-2026-4', 'sub-4', '2.02.2.01.01.01', 'Pengadaan Barang dan Jasa'),
  ('pem-2026-5', 'ta-2026', 'sek-2026-4', 'sub-5', '2.03.2.04.01.01', 'Pelayanan Administrasi Umum'),
  ('pem-2025-1', 'ta-2025', 'sek-2025-1', 'sub-1', '2.01.2.06.01.01', 'Perencanaan, Penganggaran, dan Evaluasi Kinerja'),
  ('pem-2025-2', 'ta-2025', 'sek-2025-2', 'sub-2', '2.01.2.06.02.01', 'Administrasi Keuangan'),
  ('pem-2027-1', 'ta-2027', 'sek-2027-1', 'sub-1', '2.01.2.06.01.01', 'Perencanaan, Penganggaran, dan Evaluasi Kinerja'),
  ('pem-2027-2', 'ta-2027', 'sek-2027-2', 'sub-3', '2.01.2.06.03.01', 'Penatausahaan dan Pertanggungjawaban'),
  ('pem-2024-1', 'ta-2024', 'sek-2024-1', 'sub-1', '2.01.2.06.01.01', 'Perencanaan, Penganggaran, dan Evaluasi Kinerja');
insert into penugasan_ta (id, ta_id, peran, personel_id, seksi_ta_id, tmt_mulai, tmt_selesai, provisional, nama_snapshot, nip_snapshot) values
  ('tg-2026-pakpa', 'ta-2026', 'pa_kpa', 'p-1', null, '2026-01-01', null, false, 'Hendra Wijaya, S.E., M.Si.', '198501012010011001'),
  ('tg-2026-bend', 'ta-2026', 'bendahara', 'p-2', null, '2026-01-01', null, false, 'Dr. Siti Rahmawati, M.Si.', '198203152009012003'),
  ('tg-2026-ver', 'ta-2026', 'verifikator', 'p-6', null, '2026-01-01', null, false, 'Dewi Anggraini, S.H.', '198911112014032007'),
  ('tg-2026-pptk-1', 'ta-2026', 'pptk', 'p-3', 'sek-2026-1', '2026-01-01', null, false, 'Budi Santoso, S.T.', '198807202012011004'),
  ('tg-2026-pptk-2', 'ta-2026', 'pptk', 'p-4', 'sek-2026-2', '2026-10-02', null, false, 'Maya Lestari, S.E.', '199002102015042005'),
  ('tg-2026-pptk-3', 'ta-2026', 'pptk', 'p-5', 'sek-2026-3', '2026-01-01', null, false, 'Rahmat Hidayat, S.Sos.', '197505052008011006'),
  ('tg-2026-pptk-4', 'ta-2026', 'pptk', 'p-7', 'sek-2026-4', '2026-01-01', null, false, 'Agus Prasetiyo, S.T., M.T.', '198601252011011008'),
  ('tg-2026-pptk-2-lama', 'ta-2026', 'pptk', 'p-9', 'sek-2026-2', '2026-01-01', '2026-10-01', false, 'Eko Saputra, S.Pd.', '199408122018031009'),
  ('tg-2025-pakpa', 'ta-2025', 'pa_kpa', 'p-1', null, '2025-01-01', null, false, 'Hendra Wijaya, S.E., M.Si.', '198501012010011001'),
  ('tg-2027-pakpa', 'ta-2027', 'pa_kpa', 'p-1', null, '2027-01-01', null, true, 'Hendra Wijaya, S.E., M.Si.', '198501012010011001'),
  ('tg-2027-bend', 'ta-2027', 'bendahara', 'p-2', null, '2027-01-01', null, true, 'Dr. Siti Rahmawati, M.Si.', '198203152009012003'),
  ('tg-2027-ver', 'ta-2027', 'verifikator', 'p-6', null, '2027-01-01', null, true, 'Dewi Anggraini, S.H.', '198911112014032007'),
  ('tg-2027-pptk-1', 'ta-2027', 'pptk', 'p-3', 'sek-2027-1', '2027-01-01', null, true, 'Budi Santoso, S.T.', '198807202012011004'),
  ('tg-2027-pptk-2', 'ta-2027', 'pptk', 'p-5', 'sek-2027-2', '2027-01-01', null, true, 'Rahmat Hidayat, S.Sos.', '197505052008011006'),
  ('tg-2024-pakpa', 'ta-2024', 'pa_kpa', 'p-1', null, '2024-01-01', null, false, 'Hendra Wijaya, S.E., M.Si.', '198501012010011001'),
  ('tg-2024-bend', 'ta-2024', 'bendahara', 'p-2', null, '2024-01-01', null, false, 'Dr. Siti Rahmawati, M.Si.', '198203152009012003'),
  ('tg-2024-pptk-1', 'ta-2024', 'pptk', 'p-3', 'sek-2024-1', '2024-01-01', null, false, 'Budi Santoso, S.T.', '198807202012011004');
insert into penugasan_delegasi (id, ta_id, personel_pengganti_id, peran_digantikan, seksi_ta_id, tanggal_mulai, tanggal_berakhir, status, alasan_pencabutan, definitive_officer_id, nama_snapshot, nip_snapshot) values
  ('dlg-2', 'ta-2026', 'p-10', 'bendahara', null, '2026-10-21', '2026-11-08', 'Delegasi Aktif', null, 'p-2', 'Yuni Astuti', '3210014503900002'),
  ('dlg-1', 'ta-2026', 'p-8', 'pptk', 'sek-2026-2', '2026-11-05', '2026-11-30', 'Delegasi Aktif', null, 'p-4', 'Nina Marlina', '3210014503900001');
insert into penugasan_pengawas_ta (id, ta_id, pengawas_id, tanggal_mulai, tanggal_akhir) values
  ('tp-1', 'ta-2026', 'aud-1', '2026-02-01', '2026-12-31'),
  ('tp-2', 'ta-2025', 'aud-1', '2025-01-01', '2026-12-31'),
  ('tp-3', 'ta-2026', 'aud-2', '2026-03-10', '2026-10-11');
insert into register_sk (id, penugasan_id, nomor_sk, tanggal_sk, berkas_key, berkas_nama, berkas_ukuran, provisional) values
  ('sk-1', 'tg-2026-pakpa', 'SK-001/2026', '2026-01-02', 'contoh/SK-contoh.pdf', null, null, false),
  ('sk-2', 'tg-2026-bend', 'SK-002/2026', '2026-01-02', 'contoh/SK-contoh.pdf', null, null, false),
  ('sk-3', 'tg-2026-ver', 'SK-003/2026', '2026-01-02', 'contoh/SK-contoh.pdf', null, null, false),
  ('sk-4', 'tg-2026-pptk-2-lama', 'SK-004/2026', '2026-01-02', 'contoh/SK-004-2026.pdf', 'SK-004-2026.pdf', 1200000, false);
insert into versi_alokasi (id, ta_id, fase, tanggal_efektif, aktor_id, aktor_nama_snapshot, aktor_peran_snapshot, keterangan) values
  ('vaa-1', 'ta-2026', 'murni', '2026-01-10 00:00'::timestamp at time zone 'Asia/Makassar', 'p-2', 'Dr. Siti Rahmawati, M.Si.', 'Bendahara Pengeluaran', 'Pengesahan alokasi murni (data contoh)');
insert into versi_alokasi_rincian (versi_id, pemetaan_subkegiatan_id, rekening_id, pagu) values
  ('vaa-1', 'pem-2026-1', null, 3000000000),
  ('vaa-1', 'pem-2026-2', null, 4500000000),
  ('vaa-1', 'pem-2026-3', null, 2500000000),
  ('vaa-1', 'pem-2026-4', null, 3500000000),
  ('vaa-1', 'pem-2026-5', null, 1500000000),
  ('vaa-1', 'pem-2026-1', 'rek-1', 1500000000),
  ('vaa-1', 'pem-2026-1', 'rek-3', 1500000000),
  ('vaa-1', 'pem-2026-2', 'rek-2', 4500000000),
  ('vaa-1', 'pem-2026-3', 'rek-1', 1000000000),
  ('vaa-1', 'pem-2026-3', 'rek-5', 1500000000),
  ('vaa-1', 'pem-2026-4', 'rek-5', 2000000000),
  ('vaa-1', 'pem-2026-4', 'rek-6', 1500000000),
  ('vaa-1', 'pem-2026-5', 'rek-4', 1500000000);
insert into jendela_alokasi (ta_id, tutup_at) values
  ('ta-2026', null),
  ('ta-2027', null);
insert into alokasi_subkegiatan (id, ta_id, pemetaan_subkegiatan_id, pagu) values
  ('as-1', 'ta-2026', 'pem-2026-1', 3000000000),
  ('as-2', 'ta-2026', 'pem-2026-2', 4500000000),
  ('as-3', 'ta-2026', 'pem-2026-3', 2500000000),
  ('as-4', 'ta-2026', 'pem-2026-4', 3500000000),
  ('as-5', 'ta-2026', 'pem-2026-5', 1500000000),
  ('as-2025-1', 'ta-2025', 'pem-2025-1', 6000000000),
  ('as-2025-2', 'ta-2025', 'pem-2025-2', 7500000000),
  ('as-2024-1', 'ta-2024', 'pem-2024-1', 3000000000);
insert into alokasi_rekening (id, ta_id, pemetaan_subkegiatan_id, rekening_id, kode_rekening_snapshot, nama_rekening_snapshot, pagu, disahkan, spd_aktif) values
  ('ar-2025-1', 'ta-2025', 'pem-2025-1', 'rek-1', '5.1.02.02.6.2.01.01', 'Belanja honorarium', 3000000000, true, 3000000000),
  ('ar-2025-2', 'ta-2025', 'pem-2025-1', 'rek-3', '5.1.02.01.6.1.01.01', 'Belanja pegawai', 3000000000, true, 3000000000),
  ('ar-2025-3', 'ta-2025', 'pem-2025-2', 'rek-2', '5.1.02.02.6.2.01.02', 'Belanja kegiatan', 7500000000, true, 7500000000),
  ('ar-1', 'ta-2026', 'pem-2026-1', 'rek-1', '5.1.02.02.6.2.01.01', 'Belanja honorarium', 1500000000, true, 1500000000),
  ('ar-2', 'ta-2026', 'pem-2026-1', 'rek-3', '5.1.02.01.6.1.01.01', 'Belanja pegawai', 1500000000, true, 1500000000),
  ('ar-3', 'ta-2026', 'pem-2026-2', 'rek-2', '5.1.02.02.6.2.01.02', 'Belanja kegiatan', 4500000000, true, 4500000000),
  ('ar-4', 'ta-2026', 'pem-2026-3', 'rek-1', '5.1.02.02.6.2.01.01', 'Belanja honorarium', 1000000000, true, 1000000000),
  ('ar-5', 'ta-2026', 'pem-2026-3', 'rek-5', '5.2.02.01.6.1.06.01', 'Belanja barang habis pakai', 1500000000, true, 1500000000),
  ('ar-6', 'ta-2026', 'pem-2026-4', 'rek-5', '5.2.02.01.6.1.06.01', 'Belanja barang habis pakai', 2000000000, true, 2000000000),
  ('ar-7', 'ta-2026', 'pem-2026-4', 'rek-6', '5.2.12.02.6.1.02.01', 'Belanja jasa konsultan', 1500000000, true, 1500000000),
  ('ar-8', 'ta-2026', 'pem-2026-5', 'rek-4', '5.2.12.01.6.1.01.01', 'Belanja perjalanan dinas', 1500000000, true, 1500000000),
  ('ar-2024-1', 'ta-2024', 'pem-2024-1', 'rek-1', '5.1.02.02.6.2.01.01', 'Belanja honorarium', 3000000000, true, 3000000000);
insert into ledger_spd (id, ta_id, alokasi_rekening_id, jenis, perubahan, spd_sesudah, keterangan, waktu, aktor_id, aktor_nama_snapshot, aktor_peran_snapshot, referensi) values
  ('ldg-2025-1', 'ta-2025', 'ar-2025-1', 'terbit', 3000000000, 3000000000, 'Pengesahan awal alokasi (data contoh TA 2025)', '2025-01-02 08:00'::timestamp at time zone 'Asia/Makassar', 'p-2', 'Dr. Siti Rahmawati, M.Si.', 'Bendahara Pengeluaran', null),
  ('ldg-2025-2', 'ta-2025', 'ar-2025-2', 'terbit', 3000000000, 3000000000, 'Pengesahan awal alokasi (data contoh TA 2025)', '2025-01-02 08:00'::timestamp at time zone 'Asia/Makassar', 'p-2', 'Dr. Siti Rahmawati, M.Si.', 'Bendahara Pengeluaran', null),
  ('ldg-2025-3', 'ta-2025', 'ar-2025-3', 'terbit', 7500000000, 7500000000, 'Pengesahan awal alokasi (data contoh TA 2025)', '2025-01-02 08:00'::timestamp at time zone 'Asia/Makassar', 'p-2', 'Dr. Siti Rahmawati, M.Si.', 'Bendahara Pengeluaran', null),
  ('ldg-ar-1', 'ta-2026', 'ar-1', 'terbit', 1500000000, 1500000000, 'Pengesahan awal alokasi (data contoh)', '2026-01-02 08:00'::timestamp at time zone 'Asia/Makassar', 'p-2', 'Dr. Siti Rahmawati, M.Si.', 'Bendahara Pengeluaran', null),
  ('ldg-ar-2', 'ta-2026', 'ar-2', 'terbit', 1500000000, 1500000000, 'Pengesahan awal alokasi (data contoh)', '2026-01-02 08:00'::timestamp at time zone 'Asia/Makassar', 'p-2', 'Dr. Siti Rahmawati, M.Si.', 'Bendahara Pengeluaran', null),
  ('ldg-ar-3', 'ta-2026', 'ar-3', 'terbit', 4500000000, 4500000000, 'Pengesahan awal alokasi (data contoh)', '2026-01-02 08:00'::timestamp at time zone 'Asia/Makassar', 'p-2', 'Dr. Siti Rahmawati, M.Si.', 'Bendahara Pengeluaran', null),
  ('ldg-ar-4', 'ta-2026', 'ar-4', 'terbit', 1000000000, 1000000000, 'Pengesahan awal alokasi (data contoh)', '2026-01-02 08:00'::timestamp at time zone 'Asia/Makassar', 'p-2', 'Dr. Siti Rahmawati, M.Si.', 'Bendahara Pengeluaran', null),
  ('ldg-ar-5', 'ta-2026', 'ar-5', 'terbit', 1500000000, 1500000000, 'Pengesahan awal alokasi (data contoh)', '2026-01-02 08:00'::timestamp at time zone 'Asia/Makassar', 'p-2', 'Dr. Siti Rahmawati, M.Si.', 'Bendahara Pengeluaran', null),
  ('ldg-ar-6', 'ta-2026', 'ar-6', 'terbit', 2000000000, 2000000000, 'Pengesahan awal alokasi (data contoh)', '2026-01-02 08:00'::timestamp at time zone 'Asia/Makassar', 'p-2', 'Dr. Siti Rahmawati, M.Si.', 'Bendahara Pengeluaran', null),
  ('ldg-ar-7', 'ta-2026', 'ar-7', 'terbit', 1500000000, 1500000000, 'Pengesahan awal alokasi (data contoh)', '2026-01-02 08:00'::timestamp at time zone 'Asia/Makassar', 'p-2', 'Dr. Siti Rahmawati, M.Si.', 'Bendahara Pengeluaran', null),
  ('ldg-ar-8', 'ta-2026', 'ar-8', 'terbit', 1500000000, 1500000000, 'Pengesahan awal alokasi (data contoh)', '2026-01-02 08:00'::timestamp at time zone 'Asia/Makassar', 'p-2', 'Dr. Siti Rahmawati, M.Si.', 'Bendahara Pengeluaran', null);
insert into kuitansi (id, ta_id, seksi_ta_id, pemetaan_subkegiatan_id, rekening_id, penerima, bruto, uraian, tanggal_kuitansi, status, pa_kpa_nama, pa_kpa_nip, bendahara_nama, bendahara_nip, pptk_nama, pptk_nip, versi_alokasi_snapshot_id) values
  ('kui-1', 'ta-2026', 'sek-2026-1', 'pem-2026-1', 'rek-1', 'Andi Saputra', 5000000, 'Honorarium kegiatan rapat koordinasi', '2026-04-15', 'Aktif', 'Hendra Wijaya, S.E., M.Si.', '198501012010011001', 'Dr. Siti Rahmawati, M.Si.', '198203152009012003', 'Budi Santoso, S.T.', '198807202012011004', 'vaa-1'),
  ('kui-2', 'ta-2026', 'sek-2026-4', 'pem-2026-4', 'rek-5', 'Toko Sumber Makmur', 12500000, 'Pembelian ATK habis pakai triwulan I', '2026-03-20', 'Terkunci', 'Hendra Wijaya, S.E., M.Si.', '198501012010011001', 'Dr. Siti Rahmawati, M.Si.', '198203152009012003', 'Agus Prasetiyo, S.T., M.T.', '198601252011011008', 'vaa-1'),
  ('kui-3', 'ta-2026', 'sek-2026-4', 'pem-2026-4', 'rek-5', 'CV Maju Jaya', 8750000, 'Pengadaan kertas fotokopi', '2026-05-02', 'Terkunci', 'Hendra Wijaya, S.E., M.Si.', '198501012010011001', 'Dr. Siti Rahmawati, M.Si.', '198203152009012003', 'Agus Prasetiyo, S.T., M.T.', '198601252011011008', 'vaa-1'),
  ('kui-4', 'ta-2026', 'sek-2026-4', 'pem-2026-4', 'rek-6', 'PT Konsultan Sejahtera', 15000000, 'Jasa konsultan perencanaan', '2026-02-28', 'Terkunci', 'Hendra Wijaya, S.E., M.Si.', '198501012010011001', 'Dr. Siti Rahmawati, M.Si.', '198203152009012003', 'Agus Prasetiyo, S.T., M.T.', '198601252011011008', 'vaa-1'),
  ('kui-mt-1', 'ta-2024', 'sek-2024-1', 'pem-2024-1', 'rek-1', 'Budi Hartono', 3000000, 'Honorarium rapat koordinasi TA 2024', '2024-06-10', 'Aktif', 'Hendra Wijaya, S.E., M.Si.', '198501012010011001', 'Dr. Siti Rahmawati, M.Si.', '198203152009012003', 'Budi Santoso, S.T.', '198807202012011004', null);
insert into spj (id, ta_id, kuitansi_id, jenis_belanja, versi_form, jawaban, status, catatan_revisi, dikembalikan, tanggal_pengajuan, penandatangan_pengajuan, lampiran_key, lampiran_nama_asli, lampiran_ukuran_asal, lampiran_ukuran_final, lampiran_status_optimasi) values
  ('spj-2', 'ta-2026', 'kui-2', 'Belanja Barang Habis Pakai', 'v1', '{"uraian":"Pembelian ATK habis pakai triwulan I"}'::jsonb, 'Draft', null, false, null, null, 'contoh/bukti-atk.pdf', 'bukti-atk.pdf', 3200000, 3200000, 'BYPASSED'),
  ('spj-3', 'ta-2026', 'kui-3', 'Belanja Barang Habis Pakai', 'v1', '{"uraian":"Pengadaan kertas fotokopi"}'::jsonb, 'Menunggu BKU', null, false, null, null, 'contoh/bukti-kertas.pdf', 'bukti-kertas.pdf', 8100000, 6400000, 'CLIENT_COMPRESSED'),
  ('spj-4', 'ta-2026', 'kui-4', 'Belanja Jasa Konsultan', 'v1', '{"uraian":"Jasa konsultan perencanaan"}'::jsonb, 'Dibukukan', null, false, null, null, 'contoh/bukti-konsultan.pdf', 'bukti-konsultan.pdf', 12500000, 7800000, 'CLIENT_COMPRESSED');
insert into spj_pajak (id, spj_id, jenis_pajak_id, nominal) values
  ('pj-1', 'spj-3', 'pjk-3', 437500),
  ('pj-2', 'spj-4', 'pjk-2', 750000),
  ('pj-3', 'spj-4', 'pjk-4', 1500000);
insert into spj_rekening_penerima (id, spj_id, account_name, bank_name, account_number, alias) values
  ('rp-1', 'spj-3', 'Nina Marlina', 'Bank Mandiri', '1420012345678', 'Plh. PPTK Perencanaan'),
  ('rp-2', 'spj-4', 'Ahmad Narasumber, S.E.', 'Bank BRI', '001201123456789', 'Narasumber');
insert into bku (id, ta_id, kuitansi_id, spj_id, nomor_bku, tanggal_bku, status) values
  ('bku-1', 'ta-2026', 'kui-4', 'spj-4', 'BKU-001', '2026-03-05', 'Aktif');
insert into format_nomor_verifikasi (ta_id, awalan, pemisah, pola_tahun, digit) values
  ('ta-2026', 'VER', '/', 'YYYY', 4);
insert into urut_verifikasi (ta_id, terakhir) values
  ('ta-2026', 2);
insert into token_verifikasi_spj (id, ta_id, spj_id, token, nomor_verifikasi, urut, tanggal_verifikasi, verifikator_nama, verifikator_nip, status) values
  ('tv-1', 'ta-2026', 'spj-4', 'K7QW3M9XD2HFTP4R8ZNB6VYC', '0001/VER/2026', 1, '2026-03-03', 'Dewi Anggraini, S.H.', '198911112014032007', 'Berlaku'),
  ('tv-2', 'ta-2026', 'spj-3', 'M4TD8ZQ2WJ6XHN9PB3RKVC5Y', '0002/VER/2026', 2, '2026-05-10', 'Dewi Anggraini, S.H.', '198911112014032007', 'Berlaku');
insert into direktori_transaksional (id, nip_nik, nama) values
  ('dir-1', '198807202012011004', 'Budi Santoso, S.T.'),
  ('dir-2', '3210014503900001', 'Nina Marlina'),
  ('dir-3', '6701234590123456', 'Ahmad Narasumber, S.E.');
insert into direktori_transaksional_ref (direktori_id, spj_id) values
  ('dir-1', 'spj-4'),
  ('dir-2', 'spj-3'),
  ('dir-3', 'spj-4');
insert into direktori_rekening_bank (id, account_name, bank_name, account_number, alias, created_at, updated_at) values
  ('rbk-1', 'Budi Santoso, S.T.', 'BPD Kalsel', '0012345678', 'Sekretariat', '2026-02-10 09:00'::timestamp at time zone 'Asia/Makassar', '2026-02-10 09:00'::timestamp at time zone 'Asia/Makassar'),
  ('rbk-2', 'Nina Marlina', 'Bank Mandiri', '1420012345678', 'Plh. PPTK Perencanaan', '2026-02-12 10:15'::timestamp at time zone 'Asia/Makassar', '2026-02-12 10:15'::timestamp at time zone 'Asia/Makassar'),
  ('rbk-3', 'Ahmad Narasumber, S.E.', 'Bank BRI', '001201123456789', 'Narasumber', '2026-02-20 13:40'::timestamp at time zone 'Asia/Makassar', '2026-02-20 13:40'::timestamp at time zone 'Asia/Makassar'),
  ('rbk-4', 'CV Mitra Karya', 'Bank BNI', '0123456789', 'Rekanan ATK', '2026-02-25 08:05'::timestamp at time zone 'Asia/Makassar', '2026-02-25 08:05'::timestamp at time zone 'Asia/Makassar');
insert into audit_event (id, ta_id, waktu, aktor_id, aktor_nama_snapshot, aktor_nip_snapshot, aktor_peran_snapshot, entitas, aksi, nilai_sebelum, nilai_sesudah, alasan, otomatis, definitive_officer_id, delegate_officer_id, kuitansi_id, spj_id) values
  ('ae-1', 'ta-2026', '2026-01-10 09:15'::timestamp at time zone 'Asia/Makassar', 'p-2', 'Dr. Siti Rahmawati, M.Si.', '198203152009012003', 'Bendahara Pengeluaran', 'TA 2026', 'sahkan', null, 'SPD terbit 100% pagu disahkan', null, false, null, null, null, null),
  ('ae-2', 'ta-2026', '2026-03-05 14:30'::timestamp at time zone 'Asia/Makassar', 'p-2', 'Dr. Siti Rahmawati, M.Si.', '198203152009012003', 'Bendahara Pengeluaran', 'BKU BKU-001', 'pencatatan_bku', null, 'No. BKU BKU-001, Tanggal 2026-03-05', null, false, null, null, 'kui-4', 'spj-4');
commit;
