# Peta fitur AMANDA → RPC backend
Seluruh tulis data lewat RPC (klien tidak dapat menulis langsung ke tabel). Nama RPC sama dengan fungsi di `api.ts`.
Aksi tulis mengembalikan `{ ok, error? }`. Bacaan memakai `select` biasa (dibatasi RLS per peran) atau RPC baca di bawah.

| Fitur / layar | RPC |
|---|---|
| Masuk, konteks, sesi | Edge Function `masuk` → `sesi_saya`, `ping_sesi`, `akhiri_sesi` |
| SOTK | `adm_sotk_tambah`, `adm_sotk_ubah_nomenklatur`, `adm_sotk_koreksi_typo`, `adm_sotk_arsipkan` |
| Personel, pangkat | `adm_personel_tambah`, `adm_personel_edit`, `adm_personel_perubahan_pangkat` |
| Akun, Pengawas | `adm_akun_buat/reset_sandi/dampak/set_status`, `adm_pengawas_tambah/edit/reset_sandi/set_status` |
| Master subkegiatan, rekening, pajak | `adm_subkegiatan_simpan`, `adm_rekening_simpan`, `adm_jenis_pajak_simpan/toggle` |
| Direktori transaksional, rekening bank | `adm_direktori_koreksi/gabung`, `adm_rekening_bank_koreksi/gabung`, `direktori_lookup`, `rekening_bank_cari` |
| Form Dinamis, template | `adm_form_simpan_versi`, `adm_template_simpan` (kunci `template_kuitansi`/`template_verifikasi`), `adm_format_nomor_simpan` |
| TA | `adm_ta_buat/salin_struktur/hapus/edit_pagu/ubah_status`, `ta_checklist`, `adm_ta_ringkasan_hapus`, `adm_ta_hapus_retensi` |
| Seksi, pemetaan, penugasan, SK | `adm_seksi_tambah/hapus`, `adm_pemetaan_tambah/hapus`, `adm_penugasan_tambah/hapus/ganti`, `adm_sk_tambah/lengkapi` |
| Pengawas per TA, delegasi | `adm_pengawas_ta_tambah/hapus`, `adm_delegasi_tetapkan/cabut` |
| Jendela waktu, alokasi, Sahkan | `bend_jendela_atur`, `bend_alokasi_sub_simpan`, `pptk_alokasi_rek_simpan`, `bend_sahkan` |
| SPD, pergeseran | `bend_spd_efisiensi`, `bend_spd_naik`, `bend_spd_final`, `bend_geser` |
| APBD-P | `adm_apbdp_aktifkan`, `adm_apbdp_koreksi` (lalu Sahkan ulang: `bend_sahkan`) |
| Angka anggaran, drill-down | `anggaran_ringkasan`, `drill_seksi`, `drill_subkegiatan`, `drill_rekening` |
| Kuitansi | `pptk_kuitansi_buat/ubah/batalkan` |
| SPJ | `pptk_spj_buat/jawaban/rekening/pajak/lampiran/lampiran_hapus/ajukan/lepas` |
| Verifikasi | `ver_spj_setujui`, `ver_spj_kembalikan`, `spj_cetak_verifikasi`, `pub_cek_keaslian` (anonim) |
| Lampiran | Storage bucket `lampiran-spj` + `pptk_spj_lampiran`, `spj_lampiran_hak` |
| BKU | `bend_bku_catat/koreksi/cabut` |
| Laporan a–g, kustom | `laporan_buat`, `laporan_kolom_kustom`, `laporan_kustom`; unduhan Pengawas: `pengawas_catat_aksi` |
| Analitik PA/KPA | `analitik_seksi`, `heatmap_bulanan` |
| Portal publik (anonim) | `publik_daftar_ta`, `publik_ringkasan` |
