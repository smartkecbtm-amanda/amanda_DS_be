// Pembangkit seed.sql dari data contoh frontend (src/data/sampleData.ts). Jalankan: npx tsx supabase/seed/gen_seed.ts > supabase/seed.sql
import * as d from '@/data/sampleData';

const q = (v: unknown): string => {
  if (v === null || v === undefined) return 'null';
  if (typeof v === 'number') return String(v);
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'object') return `'${JSON.stringify(v).replace(/'/g, "''")}'::jsonb`;
  return `'${String(v).replace(/'/g, "''")}'`;
};
// 'YYYY-MM-DD HH:mm' (WITA) -> timestamptz
const ts = (v: string | null | undefined) => (v ? (v.length <= 10 ? `${q(v + ' 00:00')}::timestamp at time zone 'Asia/Makassar'` : `${q(v)}::timestamp at time zone 'Asia/Makassar'`) : 'null');
const out: string[] = [];
function ins(tabel: string, kolom: string[], baris: unknown[][]) {
  if (!baris.length) return;
  out.push(`insert into ${tabel} (${kolom.join(', ')}) values\n  ${baris.map((r) => `(${r.map((x) => (typeof x === 'string' && x.startsWith('@@') ? x.slice(2) : q(x))).join(', ')})`).join(',\n  ')};`);
}
const raw = (s: string) => '@@' + s;

out.push('-- Dibangkitkan dari src/data/sampleData.ts. Kata sandi akun uji: amanda123 (hash bcrypt).');
out.push('begin;');
// SOTK dua tahap (referensi pengganti_dari)
ins('sotk', ['id','nama_unit','tmt_mulai','tmt_selesai','dasar_hukum','pengganti_dari_id','status_versi'],
  d.masterSOTK.map((s) => [s.id, s.nama_unit, s.tmt_mulai, s.tmt_selesai, s.dasar_hukum, null, s.status_versi]));
for (const s of d.masterSOTK) if (s.pengganti_dari_id) out.push(`update sotk set pengganti_dari_id = ${q(s.pengganti_dari_id)} where id = ${q(s.id)};`);
ins('personel', ['id','gelar_depan','nama','gelar_belakang','nip','nik','pangkat','tmt','no_whatsapp'],
  d.masterPersonel.map((p) => [p.id, p.gelar_depan, p.nama, p.gelar_belakang, p.nip, p.nik, p.pangkat, p.tmt, p.no_whatsapp]));
ins('riwayat_pangkat', ['id','personel_id','pangkat','gelar_depan','gelar_belakang','tmt_mulai','tmt_selesai'],
  d.pangkatHistory.map((h) => [h.id, h.personel_id, h.pangkat, h.gelar_depan, h.gelar_belakang, h.tmt_mulai, h.tmt_selesai]));
ins('akun_login', ['id','personel_id','username','kata_sandi_hash','status','failed_attempts','locked','is_admin'],
  d.akunLogin.map((a) => [a.id, a.personel_id, a.username, raw(`extensions.crypt(${q(a.password)}, extensions.gen_salt('bf'))`), a.status, a.failed_attempts, a.locked, a.personel_id === null && a.username === 'admin']));
ins('akun_pengawas', ['id','nama_lengkap','instansi_asal','nomor_surat_tugas','tanggal_surat_tugas','email','tanggal_akhir_akses','kata_sandi_hash','status','failed_attempts','locked'],
  d.akunPengawas.map((a) => [a.id, a.nama_lengkap, a.instansi_asal, a.nomor_surat_tugas, a.tanggal_surat_tugas, a.email, a.tanggal_akhir_akses, raw(`extensions.crypt(${q(a.password)}, extensions.gen_salt('bf'))`), a.status, a.failed_attempts, a.locked]));
ins('subkegiatan', ['id','kode','nama','rincian','status'], d.masterSubkegiatan.map((s) => [s.id, s.kode, s.nama, s.rincian, s.status]));
ins('rekening_belanja', ['id','kode_rekening','nama','rincian','status'], d.masterRekeningBelanja.map((s) => [s.id, s.kode_rekening, s.nama, s.rincian, s.status]));
ins('jenis_pajak', ['id','kode','nama_jenis_pajak','status'], d.masterJenisPajak.map((s) => [s.id, s.kode, s.nama_jenis_pajak, s.status]));
ins('form_dinamis', ['id','jenis_belanja','versi','fields','blok_berulang','tanggal_dibuat'],
  d.formDinamis.map((f) => [f.id, f.jenis_belanja, f.versi, f.fields, f.blok_berulang, f.tanggal_dibuat]));
ins('konfigurasi', ['kunci','nilai'], [['template_kuitansi', d.templateKuitansi], ['template_verifikasi', d.templateVerifikasi]]);

ins('tahun_anggaran', ['id','tahun','pagu_induk','status','mode_apbd_p','pagu_induk_perubahan','tanggal_arsip_terakhir','pernah_transaksi'],
  d.tahunAnggaran.map((t) => [t.id, t.tahun, t.pagu_induk, t.status, t.mode_apbd_p, t.pagu_induk_perubahan, t.tanggal_arsip_terakhir, t.pernah_transaksi]));
ins('seksi_ta', ['id','ta_id','sotk_id','nama_snapshot','tmt_mulai','tmt_selesai','status'],
  d.seksiTA.map((s) => [s.id, s.ta_id, s.sotka_id, s.nama_snapshot, s.tmt_mulai, s.tmt_selesai, s.status]));
ins('pemetaan_subkegiatan_ta', ['id','ta_id','seksi_ta_id','subkegiatan_id','kode_snapshot','nama_snapshot'],
  d.pemetaanSubkegiatanTA.map((p) => [p.id, p.ta_id, p.seksi_ta_id, p.subkegiatan_id, p.kode_snapshot, p.nama_snapshot]));
ins('penugasan_ta', ['id','ta_id','peran','personel_id','seksi_ta_id','tmt_mulai','tmt_selesai','provisional','nama_snapshot','nip_snapshot'],
  d.penugasanTA.map((p) => [p.id, p.ta_id, p.peran, p.personel_id, p.seksi_ta_id, p.tmt_mulai, p.tmt_selesai, p.provisional, p.nama_snapshot, p.nip_snapshot]));
ins('penugasan_delegasi', ['id','ta_id','personel_pengganti_id','peran_digantikan','seksi_ta_id','tanggal_mulai','tanggal_berakhir','status','alasan_pencabutan','definitive_officer_id','nama_snapshot','nip_snapshot'],
  d.penugasanDelegasi.map((x) => [x.id, x.ta_id, x.personel_pengganti_id, x.peran_digantikan, x.seksi_ta_id, x.tanggal_mulai, x.tanggal_berakhir, x.status, x.alasan_pencabutan, x.definitive_officer_id, x.nama_snapshot, x.nip_snapshot]));
ins('penugasan_pengawas_ta', ['id','ta_id','pengawas_id','tanggal_mulai','tanggal_akhir'],
  d.penugasanPengawasTA.map((x) => [x.id, x.ta_id, x.pengawas_id, x.tanggal_mulai, x.tanggal_akhir]));
ins('register_sk', ['id','penugasan_id','nomor_sk','tanggal_sk','berkas_key','berkas_nama','berkas_ukuran','provisional'],
  d.registerSK.map((s) => [s.id, s.penugasan_id, s.nomor_sk, s.tanggal_sk, s.provisional ? null : `contoh/${s.berkas ?? 'SK-contoh.pdf'}`, s.berkas, s.berkas_ukuran ?? null, s.provisional]));

ins('versi_alokasi', ['id','ta_id','fase','tanggal_efektif','aktor_id','aktor_nama_snapshot','aktor_peran_snapshot','keterangan'],
  d.versiAlokasiAnggaran.map((v) => [v.id, v.ta_id, v.fase, raw(ts(v.tanggal_efektif)), v.aktor_id, v.aktor_nama_snapshot, v.aktor_peran_snapshot, v.keterangan]));
ins('versi_alokasi_rincian', ['versi_id','pemetaan_subkegiatan_id','rekening_id','pagu'],
  d.versiAlokasiAnggaran.flatMap((v) => v.rincian.map((r) => [v.id, r.pemetaan_subkegiatan_id, r.rekening_id, r.pagu])));
ins('jendela_alokasi', ['ta_id','tutup_at'], d.jendelaAlokasi.map((j) => [j.ta_id, raw(ts(j.tutup_wita))]));
ins('alokasi_subkegiatan', ['id','ta_id','pemetaan_subkegiatan_id','pagu'], d.alokasiSubkegiatan.map((a) => [a.id, a.ta_id, a.pemetaan_subkegiatan_id, a.pagu]));
ins('alokasi_rekening', ['id','ta_id','pemetaan_subkegiatan_id','rekening_id','kode_rekening_snapshot','nama_rekening_snapshot','pagu','disahkan','spd_aktif'],
  d.alokasiRekening.map((a) => [a.id, a.ta_id, a.pemetaan_subkegiatan_id, a.rekening_id, a.kode_rekening_snapshot, a.nama_rekening_snapshot, a.pagu, a.disahkan, a.spd_aktif]));
ins('ledger_spd', ['id','ta_id','alokasi_rekening_id','jenis','perubahan','spd_sesudah','keterangan','waktu','aktor_id','aktor_nama_snapshot','aktor_peran_snapshot','referensi'],
  d.ledgerSPD.map((l) => [l.id, l.ta_id, l.alokasi_rekening_id, l.jenis, l.perubahan, l.spd_sesudah, l.keterangan, raw(ts(l.waktu)), l.aktor_id, l.aktor_nama_snapshot, l.aktor_peran_snapshot, l.referensi]));

ins('kuitansi', ['id','ta_id','seksi_ta_id','pemetaan_subkegiatan_id','rekening_id','penerima','bruto','uraian','tanggal_kuitansi','status','pa_kpa_nama','pa_kpa_nip','bendahara_nama','bendahara_nip','pptk_nama','pptk_nip','versi_alokasi_snapshot_id'],
  d.kuitansi.map((k) => [k.id, k.ta_id, k.seksi_ta_id, k.pemetaan_subkegiatan_id, k.rekening_id, k.penerima, k.bruto, k.uraian, k.tanggal_kuitansi, k.status, k.pa_kpa_nama, k.pa_kpa_nip, k.bendahara_nama, k.bendahara_nip, k.pptk_nama, k.pptk_nip, k.versi_alokasi_snapshot_id]));
ins('spj', ['id','ta_id','kuitansi_id','jenis_belanja','versi_form','jawaban','status','catatan_revisi','dikembalikan','tanggal_pengajuan','penandatangan_pengajuan','lampiran_key','lampiran_nama_asli','lampiran_ukuran_asal','lampiran_ukuran_final','lampiran_status_optimasi'],
  d.spj.map((s) => [s.id, s.ta_id, s.kuitansi_id, s.jenis_belanja, s.versi_form, s.jawaban, s.status, s.catatan_revisi, false, s.tanggal_pengajuan ?? null, s.penandatangan_pengajuan ?? null, s.lampiran_nama_asli ? `contoh/${s.lampiran_nama_asli}` : null, s.lampiran_nama_asli, s.lampiran_ukuran_asal, s.lampiran_ukuran_final, s.lampiran_status_optimasi]));
ins('spj_pajak', ['id','spj_id','jenis_pajak_id','nominal'], d.spj.flatMap((s) => s.entri_pajak.map((p) => [p.id, s.id, p.jenis_pajak_id, p.nominal])));
ins('spj_rekening_penerima', ['id','spj_id','account_name','bank_name','account_number','alias'],
  d.spj.flatMap((s) => s.rekening_penerima.map((r) => [r.id, s.id, r.account_name, r.bank_name, r.account_number, r.alias])));
ins('bku', ['id','ta_id','kuitansi_id','spj_id','nomor_bku','tanggal_bku','status'], d.bku.map((b) => [b.id, b.ta_id, b.kuitansi_id, b.spj_id, b.nomor_bku, b.tanggal_bku, b.status]));
ins('format_nomor_verifikasi', ['ta_id','awalan','pemisah','pola_tahun','digit'], d.formatNomorVerifikasi.map((f) => [f.ta_id, f.awalan, f.pemisah, f.pola_tahun, f.digit]));
ins('urut_verifikasi', ['ta_id','terakhir'], Object.entries(d.verifikasiSeq).map(([k, v]) => [k, v]));
ins('token_verifikasi_spj', ['id','ta_id','spj_id','token','nomor_verifikasi','urut','tanggal_verifikasi','verifikator_nama','verifikator_nip','status'],
  d.tokenVerifikasi.map((t) => [t.id, t.ta_id, t.spj_id, t.token, t.nomor_verifikasi, t.urut, t.tanggal_verifikasi, t.verifikator_nama, t.verifikator_nip, t.status]));
ins('direktori_transaksional', ['id','nip_nik','nama'], d.direktoriTransaksional.map((x) => [x.id, x.nip_nik, x.nama]));
ins('direktori_transaksional_ref', ['direktori_id','spj_id'], d.direktoriTransaksional.flatMap((x) => x.referensi_spj_ids.map((s) => [x.id, s])));
ins('direktori_rekening_bank', ['id','account_name','bank_name','account_number','alias','created_at','updated_at'],
  d.rekeningBankDirektori.map((r) => [r.id, r.account_name, r.bank_name, r.account_number, r.alias, raw(ts(r.created_at)), raw(ts(r.updated_at))]));
ins('audit_event', ['id','ta_id','waktu','aktor_id','aktor_nama_snapshot','aktor_nip_snapshot','aktor_peran_snapshot','entitas','aksi','nilai_sebelum','nilai_sesudah','alasan','otomatis','definitive_officer_id','delegate_officer_id','kuitansi_id','spj_id'],
  d.auditEvents.map((a) => [a.id, a.ta_id, raw(ts(a.waktu)), a.aktor_id, a.aktor_nama_snapshot, a.aktor_nip_snapshot, a.aktor_peran_snapshot, a.entitas, a.aksi, a.nilai_sebelum, a.nilai_sesudah, a.alasan, a.otomatis, a.definitive_officer_id ?? null, a.delegate_officer_id ?? null, a.kuitansi_id ?? null, a.spj_id ?? null]));
out.push('commit;');
console.log(out.join('\n'));
