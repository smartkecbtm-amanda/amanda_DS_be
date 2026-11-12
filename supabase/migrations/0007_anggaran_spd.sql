-- AMANDA — Langkah 4 (backend): alokasi anggaran, jendela waktu, Sahkan, SPD (efisiensi/kenaikan/final), pergeseran, APBD-P.
-- Port dari aturan Tahap A (anggaran.ts). Rujukan: D01 §2–4; D03 §494; D04 §2.2.
-- Semua tulis lewat RPC. Setiap RPC mengunci baris TA (for update) agar perhitungan sisa SPD tidak balapan.

-- Pada masa APBD-P (sebelum Sahkan ulang), pagu rekening boleh lebih rendah dari SPD lama; SPD disesuaikan saat Sahkan ulang.
alter table alokasi_rekening drop constraint if exists alokasi_rekening_check;

-- ============ PEMBANTU HITUNG ============
create or replace function amanda.realisasi(p_ar text) returns bigint language sql stable security definer set search_path = public, amanda as $$
  select coalesce(sum(k.bruto), 0)::bigint from alokasi_rekening a
  join kuitansi k on k.ta_id = a.ta_id and k.pemetaan_subkegiatan_id = a.pemetaan_subkegiatan_id and k.rekening_id = a.rekening_id
  where a.id = p_ar and exists (select 1 from bku b where b.kuitansi_id = k.id and b.status = 'Aktif') $$;
create or replace function amanda.komitmen(p_ar text) returns bigint language sql stable security definer set search_path = public, amanda as $$
  select coalesce(sum(k.bruto), 0)::bigint from alokasi_rekening a
  join kuitansi k on k.ta_id = a.ta_id and k.pemetaan_subkegiatan_id = a.pemetaan_subkegiatan_id and k.rekening_id = a.rekening_id
  where a.id = p_ar and k.status in ('Aktif','Terkunci') and not exists (select 1 from bku b where b.kuitansi_id = k.id and b.status = 'Aktif') $$;
create or replace function amanda.terpakai(p_ar text) returns bigint language sql stable security definer set search_path = public, amanda as $$
  select amanda.realisasi(p_ar) + amanda.komitmen(p_ar) $$;
create or replace function amanda.sisa_spd_bebas(p_ar text) returns bigint language sql stable security definer set search_path = public, amanda as $$
  select a.spd_aktif - amanda.terpakai(a.id) from alokasi_rekening a where a.id = p_ar $$;

create or replace function amanda.pagu_induk_aktif(p_ta text) returns bigint language sql stable security definer set search_path = public, amanda as $$
  select case when mode_apbd_p and pagu_induk_perubahan is not null then pagu_induk_perubahan else pagu_induk end from tahun_anggaran where id = p_ta $$;
create or replace function amanda.sudah_disahkan(p_ta text) returns boolean language sql stable security definer set search_path = public, amanda as $$
  select exists (select 1 from alokasi_rekening where ta_id = p_ta and disahkan) $$;
create or replace function amanda.selisih_instansi(p_ta text) returns bigint language sql stable security definer set search_path = public, amanda as $$
  select amanda.pagu_induk_aktif(p_ta) - coalesce((select sum(pagu) from alokasi_subkegiatan where ta_id = p_ta), 0) $$;

create or replace function amanda.pemetaan_seimbang(p_pem text) returns boolean language sql stable security definer set search_path = public, amanda as $$
  select exists (select 1 from alokasi_subkegiatan s where s.pemetaan_subkegiatan_id = p_pem)
     and exists (select 1 from alokasi_rekening r where r.pemetaan_subkegiatan_id = p_pem)
     and (select sum(pagu) from alokasi_rekening where pemetaan_subkegiatan_id = p_pem) = (select pagu from alokasi_subkegiatan where pemetaan_subkegiatan_id = p_pem) $$;

create or replace function amanda.status_seksi(p_ta text, p_seksi text) returns text language sql stable security definer set search_path = public, amanda as $$
  select case
    when not exists (select 1 from pemetaan_subkegiatan_ta p where p.ta_id = p_ta and p.seksi_ta_id = p_seksi and
         (exists (select 1 from alokasi_subkegiatan s where s.pemetaan_subkegiatan_id = p.id) or exists (select 1 from alokasi_rekening r where r.pemetaan_subkegiatan_id = p.id)))
      then 'Belum Input'
    when exists (select 1 from pemetaan_subkegiatan_ta p where p.ta_id = p_ta and p.seksi_ta_id = p_seksi)
         and not exists (select 1 from pemetaan_subkegiatan_ta p where p.ta_id = p_ta and p.seksi_ta_id = p_seksi and not amanda.pemetaan_seimbang(p.id))
      then 'Tuntas (100% Seimbang)'
    else 'Draft Belum Seimbang' end $$;

create or replace function amanda.jendela_terbuka(p_ta text) returns boolean language sql stable security definer set search_path = public, amanda as $$
  select coalesce((select tutup_at > now() from jendela_alokasi where ta_id = p_ta), false) $$;

-- Snapshot seluruh alokasi saat ini sebagai versi baru (append-only, ALK-07).
create or replace function amanda.catat_versi(p_ta text, p_ket text, p_fase text default null) returns void
language plpgsql volatile security definer set search_path = public, amanda as $$
declare s sesi_amanda := amanda.sesi(); v text := gen_random_uuid()::text; f text;
begin
  f := coalesce(p_fase, case when (select mode_apbd_p from tahun_anggaran where id = p_ta) then 'perubahan' else 'murni' end);
  insert into versi_alokasi (id, ta_id, fase, aktor_id, aktor_nama_snapshot, aktor_peran_snapshot, keterangan)
  values (v, p_ta, f, coalesce(s.personel_id, s.akun_id, 'system'), coalesce(s.nama_snapshot, 'Sistem'), amanda.label_peran(coalesce(s.peran, 'sistem')), p_ket);
  insert into versi_alokasi_rincian (versi_id, pemetaan_subkegiatan_id, rekening_id, pagu)
    select v, pemetaan_subkegiatan_id, null, pagu from alokasi_subkegiatan where ta_id = p_ta
    union all select v, pemetaan_subkegiatan_id, rekening_id, pagu from alokasi_rekening where ta_id = p_ta;
end $$;

-- Peran bendahara pada TA sesi. Mengembalikan pesan galat atau NULL.
create or replace function amanda.cek_bendahara(p_ta text) returns text language sql stable security definer set search_path = public, amanda as $$
  select case when amanda.peran() is distinct from 'bendahara' then 'Hanya Bendahara Pengeluaran yang dapat melakukan aksi ini.'
              when amanda.ta() is distinct from p_ta then 'TA tidak sesuai dengan sesi aktif.' end $$;

-- ============ JENDELA WAKTU (ALK-04) ============
create or replace function public.bend_jendela_atur(p_ta text, p_tutup text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare t tahun_anggaran; w timestamptz;
begin
  if amanda.peran() is distinct from 'bendahara' then return amanda.gagal('Hanya Bendahara Pengeluaran yang mengatur jendela waktu.'); end if;
  select * into t from tahun_anggaran where id = p_ta for update;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  if amanda.ta() is distinct from p_ta then return amanda.gagal('TA tidak sesuai dengan sesi aktif.'); end if;
  if p_tutup is null or p_tutup !~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$' then return amanda.gagal('Format waktu tutup harus tanggal dan jam WITA.'); end if;
  begin w := p_tutup::timestamp at time zone 'Asia/Makassar'; exception when others then return amanda.gagal('Format waktu tutup harus tanggal dan jam WITA.'); end;
  if w <= now() then return amanda.gagal('Waktu penutupan harus setelah waktu sekarang.'); end if;
  insert into jendela_alokasi (ta_id, tutup_at) values (p_ta, w) on conflict (ta_id) do update set tutup_at = excluded.tutup_at;
  perform amanda.catat_audit(p_ta, 'Jendela alokasi TA ' || t.tahun, 'aksi_administratif', null, 'Ditutup ' || p_tutup || ' WITA');
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- ============ ALOKASI SUBKEGIATAN (ALK-01) ============
-- p_pagu: objek JSON {"<pemetaan_id>": <pagu>, ...}
create or replace function public.bend_alokasi_sub_simpan(p_ta text, p_pagu jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare t tahun_anggaran; e text; kv record; pg numeric; terpakai bigint; total bigint; induk bigint;
begin
  e := amanda.cek_bendahara(p_ta);
  if e is not null then return amanda.gagal('Hanya Bendahara Pengeluaran yang dapat mengalokasikan pagu subkegiatan.'); end if;
  select * into t from tahun_anggaran where id = p_ta for update;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  if t.status in ('Arsip Read-Only','Masa Transisi') then return amanda.gagal('Alokasi hanya dapat diubah pada TA yang belum disahkan.'); end if;
  if not amanda.jendela_terbuka(p_ta) then return amanda.gagal('Jendela input alokasi tertutup. Bendahara perlu membuka kembali jendela waktu.'); end if;
  if amanda.sudah_disahkan(p_ta) then return amanda.gagal('Alokasi TA ini sudah disahkan dan tidak dapat diubah di Langkah 4.'); end if;
  if p_pagu is null or jsonb_typeof(p_pagu) <> 'object' then return amanda.gagal('Data pagu tidak valid.'); end if;
  for kv in select key, value from jsonb_each(p_pagu) loop
    if jsonb_typeof(kv.value) <> 'number' then return amanda.gagal('Pagu harus bilangan bulat rupiah tanpa sen, dan tidak boleh negatif.'); end if;
    pg := (kv.value #>> '{}')::numeric;
    if pg < 0 or pg <> trunc(pg) then return amanda.gagal('Pagu harus bilangan bulat rupiah tanpa sen, dan tidak boleh negatif.'); end if;
    if not exists (select 1 from pemetaan_subkegiatan_ta where id = kv.key and ta_id = p_ta) then return amanda.gagal('Subkegiatan tidak terpetakan pada TA ini.'); end if;
    select coalesce(sum(amanda.terpakai(a.id)), 0) into terpakai from alokasi_rekening a where a.pemetaan_subkegiatan_id = kv.key;
    if pg < terpakai then return amanda.gagal('Pagu subkegiatan tidak boleh di bawah realisasi BKU dan komitmen kuitansi aktif (' || amanda.rupiah(terpakai) || ').'); end if;
  end loop;
  select coalesce(sum(case when p_pagu ? p.id then (p_pagu->>p.id)::bigint else coalesce(s.pagu, 0) end), 0) into total
    from pemetaan_subkegiatan_ta p left join alokasi_subkegiatan s on s.pemetaan_subkegiatan_id = p.id where p.ta_id = p_ta;
  induk := amanda.pagu_induk_aktif(p_ta);
  if total > induk then
    return amanda.gagal('Total pagu subkegiatan ' || amanda.rupiah(total) || ' melebihi Pagu Induk ' || amanda.rupiah(induk) || ' (selisih -' || amanda.rupiah(total - induk) || '). Kurangi pagu subkegiatan sebelum menyimpan.');
  end if;
  for kv in select key, value from jsonb_each(p_pagu) loop
    insert into alokasi_subkegiatan (ta_id, pemetaan_subkegiatan_id, pagu) values (p_ta, kv.key, (kv.value #>> '{}')::bigint)
      on conflict (pemetaan_subkegiatan_id) do update set pagu = excluded.pagu;
  end loop;
  perform amanda.catat_versi(p_ta, 'Penyimpanan alokasi pagu subkegiatan');
  perform amanda.catat_audit(p_ta, 'Alokasi subkegiatan TA ' || t.tahun, 'aksi_administratif', null, 'Selisih ' || amanda.rupiah(amanda.selisih_instansi(p_ta)));
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'selisih', amanda.selisih_instansi(p_ta));
end $$;

-- ============ ALOKASI REKENING OLEH PPTK (ALK-03) ============
-- p_baris: [{"rekening_id": "...", "pagu": 123}, ...]
create or replace function public.pptk_alokasi_rek_simpan(p_ta text, p_pemetaan text, p_baris jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare t tahun_anggaran; pem pemetaan_subkegiatan_ta; b jsonb; pg numeric; rid text; ids text[] := '{}'; x alokasi_rekening; baru jsonb; terpakai bigint; rk rekening_belanja; kode text;
begin
  select * into t from tahun_anggaran where id = p_ta for update;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  select * into pem from pemetaan_subkegiatan_ta where id = p_pemetaan and ta_id = p_ta;
  if not found then return amanda.gagal('Subkegiatan tidak ditemukan pada TA ini.'); end if;
  if amanda.peran() is distinct from 'pptk' or amanda.ta() is distinct from p_ta or amanda.seksi() is distinct from pem.seksi_ta_id then
    return amanda.gagal('Hanya PPTK seksi pemilik subkegiatan ini yang dapat mengisi rekening belanja.'); end if;
  if not amanda.jendela_terbuka(p_ta) then return amanda.gagal('Jendela input alokasi tertutup. Hubungi Bendahara untuk membukanya kembali.'); end if;
  if exists (select 1 from alokasi_rekening where pemetaan_subkegiatan_id = p_pemetaan and disahkan) then return amanda.gagal('Alokasi subkegiatan ini sudah disahkan.'); end if;
  if p_baris is null or jsonb_typeof(p_baris) <> 'array' then return amanda.gagal('Data rekening tidak valid.'); end if;
  for b in select * from jsonb_array_elements(p_baris) loop
    rid := b->>'rekening_id';
    if jsonb_typeof(b->'pagu') is distinct from 'number' then return amanda.gagal('Pagu rekening harus bilangan bulat rupiah tanpa sen, dan tidak boleh negatif.'); end if;
    pg := (b->>'pagu')::numeric;
    if pg < 0 or pg <> trunc(pg) then return amanda.gagal('Pagu rekening harus bilangan bulat rupiah tanpa sen, dan tidak boleh negatif.'); end if;
    if rid = any(ids) then return amanda.gagal('Rekening yang sama tidak boleh muncul dua kali pada subkegiatan ini.'); end if;
    ids := ids || rid;
    if not exists (select 1 from rekening_belanja where id = rid and status = 'Aktif') then return amanda.gagal('Rekening belanja tidak ditemukan atau nonaktif.'); end if;
  end loop;
  for x in select * from alokasi_rekening where pemetaan_subkegiatan_id = p_pemetaan loop
    terpakai := amanda.terpakai(x.id);
    select value into baru from jsonb_array_elements(p_baris) value where value->>'rekening_id' = x.rekening_id;
    if baru is null and terpakai > 0 then return amanda.gagal('Rekening ' || x.kode_rekening_snapshot || ' tidak dapat dihapus karena sudah ada realisasi atau komitmen.'); end if;
    if baru is not null and (baru->>'pagu')::bigint < terpakai then
      return amanda.gagal('Pagu ' || x.kode_rekening_snapshot || ' tidak boleh di bawah realisasi BKU dan komitmen kuitansi aktif (' || amanda.rupiah(terpakai) || ').'); end if;
  end loop;
  -- hapus yang tidak ada lagi (tanpa terpakai), perbarui yang ada, tambah yang baru; id dan spd_aktif lama dipertahankan
  delete from alokasi_rekening where pemetaan_subkegiatan_id = p_pemetaan and not (rekening_id = any(ids));
  for b in select * from jsonb_array_elements(p_baris) loop
    select * into rk from rekening_belanja where id = b->>'rekening_id';
    insert into alokasi_rekening (ta_id, pemetaan_subkegiatan_id, rekening_id, kode_rekening_snapshot, nama_rekening_snapshot, pagu, disahkan, spd_aktif)
    values (p_ta, p_pemetaan, rk.id, rk.kode_rekening, rk.nama, (b->>'pagu')::bigint, false, 0)
    on conflict (ta_id, pemetaan_subkegiatan_id, rekening_id) do update set pagu = excluded.pagu, disahkan = false;
  end loop;
  perform amanda.catat_versi(p_ta, 'Penyimpanan rekening belanja ' || pem.kode_snapshot);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- ============ SAHKAN (ALK-05, ALK-06, SPD-04) ============
create or replace function public.bend_sahkan(p_ta text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare t tahun_anggaran; e text; sel bigint; belum text; r alokasi_rekening; tp bigint; s sesi_amanda := amanda.sesi(); sebelum bigint;
begin
  e := amanda.cek_bendahara(p_ta);
  if e is not null then return amanda.gagal('Hanya Bendahara Pengeluaran yang dapat menekan Sahkan.'); end if;
  select * into t from tahun_anggaran where id = p_ta for update;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  if amanda.sudah_disahkan(p_ta) then return amanda.gagal('Alokasi TA ini sudah disahkan.'); end if;
  sel := amanda.selisih_instansi(p_ta);
  if sel <> 0 then return amanda.gagal('Selisih alokasi subkegiatan ' || amanda.rupiah(sel) || '. Sahkan hanya bisa bila selisih tepat Rp 0.'); end if;
  select string_agg(x.nama_snapshot, ', ' order by x.nama_snapshot) into belum from seksi_ta x
    where x.ta_id = p_ta and x.status = 'Aktif' and amanda.status_seksi(p_ta, x.id) <> 'Tuntas (100% Seimbang)';
  if belum is not null then return amanda.gagal('Seksi belum seimbang: ' || belum || '.'); end if;
  for r in select * from alokasi_rekening where ta_id = p_ta loop
    tp := amanda.terpakai(r.id);
    if r.pagu < tp then return amanda.gagal('Pagu ' || r.kode_rekening_snapshot || ' di bawah realisasi dan komitmen (' || amanda.rupiah(tp) || '). SPD tidak boleh diturunkan di bawah nilai itu.'); end if;
  end loop;
  for r in select * from alokasi_rekening where ta_id = p_ta order by id loop
    sebelum := r.spd_aktif;
    update alokasi_rekening set disahkan = true, spd_aktif = pagu where id = r.id;
    insert into ledger_spd (ta_id, alokasi_rekening_id, jenis, perubahan, spd_sesudah, keterangan, aktor_id, aktor_nama_snapshot, aktor_peran_snapshot)
    values (p_ta, r.id, case when t.mode_apbd_p then 'penyesuaian_apbdp' else 'terbit' end, r.pagu - sebelum, r.pagu,
            case when t.mode_apbd_p then 'SPD disesuaikan ke pagu APBD-P saat Sahkan ulang' else 'SPD terbit 100% pagu saat Sahkan' end,
            coalesce(s.personel_id, s.akun_id), s.nama_snapshot, amanda.label_peran(s.peran));
  end loop;
  perform amanda.catat_versi(p_ta, case when t.mode_apbd_p then 'Sahkan ulang pagu APBD-P dan penyesuaian SPD' else 'Pengesahan alokasi dan terbitnya SPD' end);
  perform amanda.catat_audit(p_ta, 'TA ' || t.tahun, 'sahkan', null, case when t.mode_apbd_p then 'SPD disesuaikan ke pagu APBD-P' else 'SPD terbit 100% pagu disahkan' end);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- ============ EFISIENSI / KENAIKAN / SPD FINAL (SPD-02, SPD-03) ============
create or replace function amanda.ubah_spd(p_ar text, p_nilai bigint, p_jenis text, p_ket text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare a alokasi_rekening; s sesi_amanda := amanda.sesi(); delta bigint; sisa bigint; ket text := btrim(coalesce(p_ket, '')); lid text := gen_random_uuid()::text; baru bigint;
begin
  if amanda.peran() is distinct from 'bendahara' then return amanda.gagal('Hanya Bendahara Pengeluaran yang dapat mengubah SPD.'); end if;
  perform 1 from tahun_anggaran where id = (select ta_id from alokasi_rekening where id = p_ar) for update;
  select * into a from alokasi_rekening where id = p_ar;
  if not found then return amanda.gagal('Rekening belanja tidak ditemukan.'); end if;
  if amanda.ta() is distinct from a.ta_id then return amanda.gagal('TA tidak sesuai dengan sesi aktif.'); end if;
  if not a.disahkan then return amanda.gagal('SPD belum terbit atau sedang menunggu Sahkan ulang. Alokasi harus disahkan terlebih dahulu.'); end if;
  if p_nilai is null or p_nilai <= 0 then return amanda.gagal('Nilai harus bilangan bulat rupiah lebih dari nol.'); end if;
  if p_jenis = 'efisiensi' then
    delta := -p_nilai; sisa := amanda.sisa_spd_bebas(a.id);
    if p_nilai > sisa then return amanda.gagal('Efisiensi ' || amanda.rupiah(p_nilai) || ' melebihi Sisa SPD Bebas ' || amanda.rupiah(sisa) || '.'); end if;
  else
    delta := p_nilai;
    if ket = '' then return amanda.gagal('Kenaikan SPD wajib disertai alasan tertulis.'); end if;
    if a.spd_aktif + p_nilai > a.pagu then return amanda.gagal('Kenaikan melebihi pagu rekening. Batas maksimal ' || amanda.rupiah(a.pagu - a.spd_aktif) || '.'); end if;
  end if;
  baru := a.spd_aktif + delta;
  update alokasi_rekening set spd_aktif = baru where id = a.id;
  insert into ledger_spd (id, ta_id, alokasi_rekening_id, jenis, perubahan, spd_sesudah, keterangan, aktor_id, aktor_nama_snapshot, aktor_peran_snapshot, referensi)
  values (lid, a.ta_id, a.id, p_jenis, delta, baru, ket, coalesce(s.personel_id, s.akun_id), s.nama_snapshot, amanda.label_peran(s.peran), lid);
  perform amanda.catat_audit(a.ta_id, 'SPD ' || a.kode_rekening_snapshot || ' ' || a.nama_rekening_snapshot,
    case when p_jenis = 'efisiensi' then 'efisiensi_spd' else 'kenaikan_spd' end, amanda.rupiah(a.spd_aktif), amanda.rupiah(baru), nullif(ket, ''));
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'spd_aktif', baru);
end $$;

create or replace function public.bend_spd_efisiensi(p_ar text, p_nilai bigint, p_ket text default '') returns jsonb
language sql volatile security definer set search_path = public, amanda as $$ select amanda.ubah_spd(p_ar, p_nilai, 'efisiensi', p_ket) $$;
create or replace function public.bend_spd_naik(p_ar text, p_nilai bigint, p_alasan text) returns jsonb
language sql volatile security definer set search_path = public, amanda as $$ select amanda.ubah_spd(p_ar, p_nilai, 'kenaikan', p_alasan) $$;

create or replace function public.bend_spd_final(p_ar text, p_final bigint, p_ket text default '') returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare a alokasi_rekening; sel bigint;
begin
  select * into a from alokasi_rekening where id = p_ar;
  if not found then return amanda.gagal('Rekening tidak ditemukan.'); end if;
  if p_final is null or p_final < 0 then return amanda.gagal('SPD final harus bilangan bulat rupiah tanpa sen, dan tidak boleh negatif.'); end if;
  sel := p_final - a.spd_aktif;
  if sel = 0 then return amanda.gagal('SPD final sama dengan SPD aktif. Tidak ada perubahan.'); end if;
  return case when sel < 0 then amanda.ubah_spd(p_ar, -sel, 'efisiensi', p_ket) else amanda.ubah_spd(p_ar, sel, 'kenaikan', p_ket) end;
end $$;

-- ============ PERGESERAN (SPD-04) ============
create or replace function public.bend_geser(p_ta text, p_sumber text, p_tujuan text, p_nilai bigint, p_alasan text default '') returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare t tahun_anggaran; e text; so alokasi_rekening; tu alokasi_rekening; ass alokasi_subkegiatan; ast alokasi_subkegiatan; sisa bigint; nomor text; urut int;
        antar boolean; ket text := btrim(coalesce(p_alasan, '')); s sesi_amanda := amanda.sesi(); rec record;
begin
  e := amanda.cek_bendahara(p_ta);
  if e is not null then return amanda.gagal('Hanya Bendahara Pengeluaran yang dapat menggeser anggaran.'); end if;
  select * into t from tahun_anggaran where id = p_ta for update;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  if t.status <> 'Aktif Penuh' then return amanda.gagal('Pergeseran hanya dapat dilakukan pada TA Aktif Penuh.'); end if;
  if p_nilai is null or p_nilai <= 0 then return amanda.gagal('Nilai pergeseran harus bilangan bulat rupiah lebih dari nol.'); end if;
  if p_sumber = p_tujuan then return amanda.gagal('Rekening sumber dan tujuan tidak boleh sama.'); end if;
  select * into so from alokasi_rekening where id = p_sumber and ta_id = p_ta;
  select * into tu from alokasi_rekening where id = p_tujuan and ta_id = p_ta;
  if so.id is null or tu.id is null then return amanda.gagal('Rekening sumber atau tujuan tidak ditemukan pada TA ini.'); end if;
  if not so.disahkan or not tu.disahkan then return amanda.gagal('Pergeseran hanya dapat dilakukan ke rekening yang alokasinya sudah disahkan.'); end if;
  sisa := amanda.sisa_spd_bebas(so.id);
  if p_nilai > sisa then return amanda.gagal('Nilai melebihi Sisa SPD Bebas rekening sumber (' || amanda.rupiah(sisa) || ').'); end if;
  select * into ass from alokasi_subkegiatan where pemetaan_subkegiatan_id = so.pemetaan_subkegiatan_id;
  select * into ast from alokasi_subkegiatan where pemetaan_subkegiatan_id = tu.pemetaan_subkegiatan_id;
  if ass.id is null or ast.id is null then return amanda.gagal('Pagu subkegiatan belum dialokasikan pada TA ini.'); end if;
  antar := so.pemetaan_subkegiatan_id <> tu.pemetaan_subkegiatan_id;
  if antar and ass.pagu < p_nilai then return amanda.gagal('Pagu subkegiatan sumber tidak cukup untuk nilai pergeseran ini.'); end if;

  insert into urut_pergeseran (ta_id, terakhir) values (p_ta, 1) on conflict (ta_id) do update set terakhir = urut_pergeseran.terakhir + 1 returning terakhir into urut;
  nomor := 'Pergeseran/' || lpad(urut::text, 3, '0') || '/' || t.tahun;
  update alokasi_rekening set pagu = pagu - p_nilai, spd_aktif = spd_aktif - p_nilai where id = so.id;
  update alokasi_rekening set pagu = pagu + p_nilai, spd_aktif = spd_aktif + p_nilai where id = tu.id;
  if antar then
    update alokasi_subkegiatan set pagu = pagu - p_nilai where id = ass.id;
    update alokasi_subkegiatan set pagu = pagu + p_nilai where id = ast.id;
  end if;
  for rec in select id, case when id = so.id then -p_nilai else p_nilai end as d, spd_aktif from alokasi_rekening where id in (so.id, tu.id) order by (id = so.id) desc loop
    insert into ledger_spd (ta_id, alokasi_rekening_id, jenis, perubahan, spd_sesudah, keterangan, aktor_id, aktor_nama_snapshot, aktor_peran_snapshot, referensi)
    values (p_ta, rec.id, 'pergeseran', rec.d, rec.spd_aktif, ket, coalesce(s.personel_id, s.akun_id), s.nama_snapshot, amanda.label_peran(s.peran), nomor);
  end loop;
  perform amanda.catat_versi(p_ta, nomor || ': ' || so.kode_rekening_snapshot || ' (-) ke ' || tu.kode_rekening_snapshot || ' (+) ' || amanda.rupiah(p_nilai), 'pergeseran');
  perform amanda.catat_audit(p_ta, nomor || ' • ' || amanda.rupiah(p_nilai), 'pergeseran_spd', 'Sumber (-) ' || so.kode_rekening_snapshot, 'Tujuan (+) ' || tu.kode_rekening_snapshot, nullif(ket, ''));
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'nomor', nomor);
end $$;

-- ============ APBD-P (TA-09) ============
create or replace function public.adm_apbdp_aktifkan(p_ta text, p_pagu bigint) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare t tahun_anggaran;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengaktifkan APBD-P.'); end if;
  select * into t from tahun_anggaran where id = p_ta for update;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  if t.status <> 'Aktif Penuh' then return amanda.gagal('APBD-P hanya dapat diaktifkan pada TA Aktif Penuh.'); end if;
  if t.mode_apbd_p then return amanda.gagal('APBD-P pada TA ini sudah aktif.'); end if;
  if not amanda.sudah_disahkan(p_ta) then return amanda.gagal('Alokasi murni belum disahkan. APBD-P diaktifkan setelah Sahkan murni.'); end if;
  if p_pagu is null or p_pagu <= 0 then return amanda.gagal('Pagu Induk perubahan harus bilangan bulat rupiah lebih dari nol.'); end if;
  update tahun_anggaran set mode_apbd_p = true, pagu_induk_perubahan = p_pagu where id = p_ta;
  update alokasi_rekening set disahkan = false where ta_id = p_ta;
  update jendela_alokasi set tutup_at = null where ta_id = p_ta;
  perform amanda.catat_audit(p_ta, 'TA ' || t.tahun, 'alokasi_apbd_p', 'Pagu Induk ' || amanda.rupiah(t.pagu_induk), 'Pagu Induk APBD-P ' || amanda.rupiah(p_pagu));
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- Koreksi pagu APBD-P oleh Admin hanya selama belum disahkan ulang (keputusan pemilik).
create or replace function public.adm_apbdp_koreksi(p_ta text, p_pagu bigint) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare t tahun_anggaran;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengoreksi Pagu Induk APBD-P.'); end if;
  select * into t from tahun_anggaran where id = p_ta for update;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  if not t.mode_apbd_p then return amanda.gagal('APBD-P belum aktif pada TA ini.'); end if;
  if amanda.sudah_disahkan(p_ta) then return amanda.gagal('APBD-P sudah disahkan ulang. Pagu Induk perubahan tidak dapat dikoreksi lagi.'); end if;
  if p_pagu is null or p_pagu <= 0 then return amanda.gagal('Pagu Induk perubahan harus bilangan bulat rupiah lebih dari nol.'); end if;
  if p_pagu = t.pagu_induk_perubahan then return amanda.gagal('Nilai sama dengan Pagu Induk perubahan saat ini.'); end if;
  update tahun_anggaran set pagu_induk_perubahan = p_pagu where id = p_ta;
  perform amanda.catat_audit(p_ta, 'TA ' || t.tahun, 'alokasi_apbd_p', 'Pagu Induk APBD-P ' || amanda.rupiah(t.pagu_induk_perubahan),
    'Pagu Induk APBD-P ' || amanda.rupiah(p_pagu) || ' (koreksi sebelum Sahkan ulang)');
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- ============ RINGKASAN UNTUK TAMPILAN ============
-- Angka dihitung di server. Admin tidak melihat angka transaksi; PPTK hanya seksinya dan tanpa Pagu Induk;
-- PA/KPA hanya sampai tingkat subkegiatan (tanpa rekening).
create or replace function public.anggaran_ringkasan(p_ta text) returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
declare pr text := amanda.peran(); sk text := amanda.seksi(); t tahun_anggaran; res jsonb; belum jsonb;
begin
  if pr is null then return amanda.gagal('Sesi tidak valid.'); end if;
  if pr = 'admin' then return amanda.gagal('Admin tidak memiliki akses ke angka transaksi.'); end if;
  if amanda.ta() is distinct from p_ta then return amanda.gagal('TA tidak sesuai dengan sesi aktif.'); end if;
  select * into t from tahun_anggaran where id = p_ta;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'nama', x.nama_snapshot, 'status', amanda.status_seksi(p_ta, x.id)) order by x.nama_snapshot), '[]')
    into belum from seksi_ta x where x.ta_id = p_ta and x.status = 'Aktif' and (pr <> 'pptk' or x.id = sk);
  res := jsonb_build_object('ok', true, 'fase', case when t.mode_apbd_p then 'perubahan' else 'murni' end,
    'disahkan', amanda.sudah_disahkan(p_ta), 'jendela_tutup', (select tutup_at from jendela_alokasi where ta_id = p_ta),
    'jendela_terbuka', amanda.jendela_terbuka(p_ta), 'seksi', belum);
  if pr <> 'pptk' then
    res := res || jsonb_build_object('pagu_induk_aktif', amanda.pagu_induk_aktif(p_ta), 'selisih', amanda.selisih_instansi(p_ta),
      'gerbang_terbuka', amanda.sudah_disahkan(p_ta) and not exists (select 1 from seksi_ta x where x.ta_id = p_ta and x.status = 'Aktif' and amanda.status_seksi(p_ta, x.id) <> 'Tuntas (100% Seimbang)'));
  end if;
  res := res || jsonb_build_object('subkegiatan', coalesce((
    select jsonb_agg(jsonb_build_object('pemetaan_id', p.id, 'seksi_ta_id', p.seksi_ta_id, 'kode', p.kode_snapshot, 'nama', p.nama_snapshot,
        'pagu', s.pagu, 'seimbang', amanda.pemetaan_seimbang(p.id),
        'total_rekening', (select coalesce(sum(pagu), 0) from alokasi_rekening where pemetaan_subkegiatan_id = p.id),
        'terpakai', (select coalesce(sum(amanda.terpakai(a.id)), 0) from alokasi_rekening a where a.pemetaan_subkegiatan_id = p.id)) order by p.kode_snapshot)
    from pemetaan_subkegiatan_ta p left join alokasi_subkegiatan s on s.pemetaan_subkegiatan_id = p.id
    where p.ta_id = p_ta and (pr <> 'pptk' or p.seksi_ta_id = sk)), '[]'));
  if pr in ('bendahara','pptk','verifikator','pengawas') then
    res := res || jsonb_build_object('rekening', coalesce((
      select jsonb_agg(jsonb_build_object('id', a.id, 'pemetaan_id', a.pemetaan_subkegiatan_id, 'rekening_id', a.rekening_id, 'kode', a.kode_rekening_snapshot,
          'nama', a.nama_rekening_snapshot, 'pagu', a.pagu, 'disahkan', a.disahkan, 'spd_aktif', a.spd_aktif, 'komitmen', amanda.komitmen(a.id),
          'realisasi', amanda.realisasi(a.id), 'sisa_spd_bebas', amanda.sisa_spd_bebas(a.id)) order by a.kode_rekening_snapshot)
      from alokasi_rekening a join pemetaan_subkegiatan_ta p on p.id = a.pemetaan_subkegiatan_id
      where a.ta_id = p_ta and (pr <> 'pptk' or p.seksi_ta_id = sk)), '[]'));
  end if;
  return res;
end $$;

-- ============ IZIN EKSEKUSI ============
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and (p.proname ~ '^(bend|pptk)_' or p.proname in ('adm_apbdp_aktifkan','adm_apbdp_koreksi','anggaran_ringkasan'))
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
grant execute on all functions in schema amanda to authenticated;
