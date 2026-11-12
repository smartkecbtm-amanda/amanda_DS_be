-- AMANDA — Langkah 5–6 (backend): kuitansi, SPJ, pajak, rekening penerima, lampiran, pengajuan, verifikasi, token & nomor verifikasi, BKU.
-- Port dari repo.ts Tahap A. Rujukan: D01 §6, §11, §13–14; D02 §3–9; D03 §4, §10, §12; D04 §2.3, §6.
-- Setiap RPC mengunci baris TA (for update) agar sisa SPD dan nomor urut tidak balapan.

-- ============ PEMBANTU ============
create or replace function amanda.ta_boleh(p_ta text, p_aksi text) returns boolean language sql stable security definer set search_path = public, amanda as $$
  -- 'buat' = hanya Aktif Penuh; 'aksi' = Aktif Penuh atau Masa Transisi (batal, ajukan, verifikasi, BKU)
  select case p_aksi when 'buat' then status = 'Aktif Penuh' else status in ('Aktif Penuh','Masa Transisi') end from tahun_anggaran where id = p_ta $$;

create or replace function amanda.gerbang_terbuka(p_ta text) returns boolean language sql stable security definer set search_path = public, amanda as $$
  select amanda.sudah_disahkan(p_ta) and not exists (select 1 from seksi_ta x where x.ta_id = p_ta and x.status = 'Aktif' and amanda.status_seksi(p_ta, x.id) <> 'Tuntas (100% Seimbang)') $$;

-- Hak transaksi PPTK: pejabat definitif nonaktif selama delegasi Plh./Plt.; Plh./Plt. aktif boleh.
create or replace function amanda.pptk_boleh_transaksi(p_ta text, p_seksi text) returns boolean
language plpgsql stable security definer set search_path = public, amanda as $$
declare per text := amanda.personel();
begin
  if per is null then return false; end if;
  if exists (select 1 from penugasan_delegasi d where d.ta_id = p_ta and d.status = 'Delegasi Aktif' and d.peran_digantikan = 'pptk' and d.seksi_ta_id = p_seksi and d.personel_pengganti_id = per) then return true; end if;
  if exists (select 1 from penugasan_delegasi d where d.ta_id = p_ta and d.status = 'Delegasi Aktif' and d.peran_digantikan = 'pptk' and d.seksi_ta_id = p_seksi and d.definitive_officer_id = per) then return false; end if;
  return exists (select 1 from penugasan_ta t where t.ta_id = p_ta and t.peran = 'pptk' and t.seksi_ta_id = p_seksi and t.personel_id = per and t.tmt_selesai is null);
end $$;

-- Snapshot penandatangan dari penugasan aktif (Plh./Plt. yang berlaku saat itu).
create or replace function amanda.snapshot_penandatangan(p_ta text, p_seksi text) returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
declare pa penugasan_ta; be penugasan_ta; pp penugasan_ta; d penugasan_delegasi; pn text := '—'; pi text := '—'; bn text := '—'; bi text := '—';
begin
  select * into pa from penugasan_ta where ta_id = p_ta and peran = 'pa_kpa' and tmt_selesai is null order by tmt_mulai desc limit 1;
  select * into be from penugasan_ta where ta_id = p_ta and peran = 'bendahara' and tmt_selesai is null order by tmt_mulai desc limit 1;
  select * into pp from penugasan_ta where ta_id = p_ta and peran = 'pptk' and seksi_ta_id = p_seksi and tmt_selesai is null order by tmt_mulai desc limit 1;
  if pp.id is not null then
    select * into d from penugasan_delegasi where ta_id = p_ta and status = 'Delegasi Aktif' and peran_digantikan = 'pptk' and seksi_ta_id = p_seksi and definitive_officer_id = pp.personel_id limit 1;
    if d.id is not null then pn := 'Plh. ' || d.nama_snapshot; pi := d.nip_snapshot; else pn := pp.nama_snapshot; pi := pp.nip_snapshot; end if;
  end if;
  if be.id is not null then
    select * into d from penugasan_delegasi where ta_id = p_ta and status = 'Delegasi Aktif' and peran_digantikan = 'bendahara' and definitive_officer_id = be.personel_id limit 1;
    if d.id is not null then bn := 'Plh. ' || d.nama_snapshot; bi := d.nip_snapshot; else bn := be.nama_snapshot; bi := be.nip_snapshot; end if;
  end if;
  return jsonb_build_object('pa_kpa_nama', coalesce(pa.nama_snapshot, '—'), 'pa_kpa_nip', coalesce(pa.nip_snapshot, '—'),
    'bendahara_nama', bn, 'bendahara_nip', bi, 'pptk_nama', pn, 'pptk_nip', pi);
end $$;

-- Kunci pemilik: PPTK seksi pemilik kuitansi pada TA sesi
create or replace function amanda.pptk_pemilik(p_ta text, p_seksi text) returns boolean language sql stable security definer set search_path = public, amanda as $$
  select amanda.peran() = 'pptk' and amanda.ta() = p_ta and amanda.seksi() = p_seksi $$;

create or replace function amanda.tanggal_valid(p text) returns boolean language plpgsql immutable as $$
begin
  if p is null or p !~ '^\d{4}-\d{2}-\d{2}$' then return false; end if;
  perform p::date; return true;
exception when others then return false; end $$;

-- ============ KUITANSI (KUI-01, KUI-02) ============
create or replace function public.pptk_kuitansi_buat(p_ta text, p_seksi text, p_pemetaan text, p_rekening text, p_penerima text, p_bruto bigint, p_uraian text, p_tanggal text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare t tahun_anggaran; a alokasi_rekening; sisa bigint; v_id text := gen_random_uuid()::text; snap jsonb; versi text;
begin
  select * into t from tahun_anggaran where id = p_ta for update;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  if t.status <> 'Aktif Penuh' then return amanda.gagal('Kuitansi baru hanya dapat dibuat pada TA Aktif Penuh. Status TA saat ini: ' || t.status || '.'); end if;
  if not amanda.gerbang_terbuka(p_ta) then return amanda.gagal('Gatekeeper tertutup. Seluruh seksi harus Seimbang dan Bendahara harus menekan Sahkan.'); end if;
  if not amanda.pptk_pemilik(p_ta, p_seksi) then return amanda.gagal('Hanya PPTK seksi pemilik yang dapat membuat kuitansi.'); end if;
  if not amanda.pptk_boleh_transaksi(p_ta, p_seksi) then return amanda.gagal('Hak transaksi pejabat definitif nonaktif selama delegasi Plh./Plt. berlaku.'); end if;
  if not exists (select 1 from pemetaan_subkegiatan_ta where id = p_pemetaan and seksi_ta_id = p_seksi and ta_id = p_ta) then return amanda.gagal('Subkegiatan tidak terpetakan untuk seksi ini.'); end if;
  select * into a from alokasi_rekening where pemetaan_subkegiatan_id = p_pemetaan and rekening_id = p_rekening and disahkan;
  if not found then return amanda.gagal('Rekening belanja belum dialokasikan atau belum disahkan.'); end if;
  if p_bruto is null or p_bruto <= 0 then return amanda.gagal('Nominal bruto harus bilangan bulat rupiah lebih dari nol.'); end if;
  if btrim(coalesce(p_penerima, '')) = '' then return amanda.gagal('Nama penerima wajib diisi.'); end if;
  if btrim(coalesce(p_uraian, '')) = '' then return amanda.gagal('Uraian pembayaran wajib diisi.'); end if;
  if not amanda.tanggal_valid(p_tanggal) then return amanda.gagal('Tanggal kuitansi wajib diisi.'); end if;
  sisa := amanda.sisa_spd_bebas(a.id);
  if p_bruto > sisa then return amanda.gagal('Nominal bruto ' || amanda.rupiah(p_bruto) || ' melebihi Sisa SPD Bebas ' || amanda.rupiah(sisa) || '.'); end if;
  snap := amanda.snapshot_penandatangan(p_ta, p_seksi);
  select v.id into versi from versi_alokasi v where v.ta_id = p_ta order by v.tanggal_efektif desc, v.id desc limit 1;
  insert into kuitansi (id, ta_id, seksi_ta_id, pemetaan_subkegiatan_id, rekening_id, penerima, bruto, uraian, tanggal_kuitansi, status,
    pa_kpa_nama, pa_kpa_nip, bendahara_nama, bendahara_nip, pptk_nama, pptk_nip, versi_alokasi_snapshot_id)
  values (v_id, p_ta, p_seksi, p_pemetaan, p_rekening, btrim(p_penerima), p_bruto, btrim(p_uraian), p_tanggal::date, 'Aktif',
    snap->>'pa_kpa_nama', snap->>'pa_kpa_nip', snap->>'bendahara_nama', snap->>'bendahara_nip', snap->>'pptk_nama', snap->>'pptk_nip', versi);
  update tahun_anggaran set pernah_transaksi = true where id = p_ta;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- p_patch: {"penerima":..,"bruto":..,"uraian":..,"tanggal_kuitansi":..} (kunci yang tidak ada = tidak diubah)
create or replace function public.pptk_kuitansi_ubah(p_id text, p_patch jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare k kuitansi; t tahun_anggaran; a alokasi_rekening; sisa bigint; nb bigint;
begin
  select * into k from kuitansi where id = p_id;
  if not found then return amanda.gagal('Kuitansi tidak ditemukan.'); end if;
  select * into t from tahun_anggaran where id = k.ta_id for update;
  select * into k from kuitansi where id = p_id for update;
  if t.status <> 'Aktif Penuh' then return amanda.gagal('Edit kuitansi hanya pada TA Aktif Penuh. Status TA: ' || t.status || '.'); end if;
  if k.status <> 'Aktif' then return amanda.gagal('Kuitansi Terkunci tidak dapat diedit. Lepas SPJ terlebih dahulu.'); end if;
  if not amanda.pptk_pemilik(k.ta_id, k.seksi_ta_id) then return amanda.gagal('Hanya PPTK seksi pemilik yang dapat mengubah kuitansi.'); end if;
  if not amanda.pptk_boleh_transaksi(k.ta_id, k.seksi_ta_id) then return amanda.gagal('Hak transaksi pejabat definitif nonaktif selama delegasi Plh./Plt. berlaku.'); end if;
  if p_patch ? 'bruto' then
    if jsonb_typeof(p_patch->'bruto') <> 'number' or (p_patch->>'bruto')::numeric <= 0 or (p_patch->>'bruto')::numeric <> trunc((p_patch->>'bruto')::numeric) then
      return amanda.gagal('Nominal bruto harus bilangan bulat rupiah lebih dari nol.'); end if;
    nb := (p_patch->>'bruto')::bigint;
    select * into a from alokasi_rekening where pemetaan_subkegiatan_id = k.pemetaan_subkegiatan_id and rekening_id = k.rekening_id and disahkan;
    if not found then return amanda.gagal('Alokasi rekening tidak ditemukan.'); end if;
    sisa := amanda.sisa_spd_bebas(a.id) + k.bruto;
    if nb > sisa then return amanda.gagal('Nominal bruto ' || amanda.rupiah(nb) || ' melebihi Sisa SPD Bebas ' || amanda.rupiah(sisa) || '.'); end if;
  end if;
  if p_patch ? 'penerima' and btrim(coalesce(p_patch->>'penerima', '')) = '' then return amanda.gagal('Nama penerima wajib diisi.'); end if;
  if p_patch ? 'uraian' and btrim(coalesce(p_patch->>'uraian', '')) = '' then return amanda.gagal('Uraian pembayaran wajib diisi.'); end if;
  if p_patch ? 'tanggal_kuitansi' and not amanda.tanggal_valid(p_patch->>'tanggal_kuitansi') then return amanda.gagal('Tanggal kuitansi wajib diisi.'); end if;
  update kuitansi set
    penerima = coalesce(btrim(p_patch->>'penerima'), penerima),
    bruto = coalesce(nb, bruto),
    uraian = coalesce(btrim(p_patch->>'uraian'), uraian),
    tanggal_kuitansi = coalesce((p_patch->>'tanggal_kuitansi')::date, tanggal_kuitansi)
  where id = p_id;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- Pembatalan kuitansi Aktif: hapus tanpa jejak (F-33a), termasuk entri audit terkait.
create or replace function public.pptk_kuitansi_batalkan(p_id text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare k kuitansi; t tahun_anggaran;
begin
  select * into k from kuitansi where id = p_id;
  if not found then return amanda.gagal('Kuitansi tidak ditemukan.'); end if;
  select * into t from tahun_anggaran where id = k.ta_id for update;
  if t.status not in ('Aktif Penuh','Masa Transisi') then return amanda.gagal('Pembatalan tidak diizinkan pada status TA: ' || t.status || '.'); end if;
  select * into k from kuitansi where id = p_id for update;
  if not found then return amanda.gagal('Kuitansi tidak ditemukan.'); end if;
  if k.status <> 'Aktif' then return amanda.gagal('Hanya kuitansi Aktif yang dapat dibatalkan.'); end if;
  if not amanda.pptk_pemilik(k.ta_id, k.seksi_ta_id) then return amanda.gagal('Hanya PPTK seksi pemilik yang dapat membatalkan kuitansi.'); end if;
  delete from audit_event where kuitansi_id = p_id;
  delete from kuitansi where id = p_id;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- ============ FORM DINAMIS: wajib, identitas jadwal, direktori ============
create or replace function amanda.cek_wajib(p_form form_dinamis, p_jawaban jsonb) returns text
language plpgsql immutable as $$
declare f jsonb; v jsonb; row jsonb; bf jsonb; i int := 0; blok jsonb := p_form.blok_berulang;
begin
  for f in select * from jsonb_array_elements(p_form.fields) loop
    if not coalesce((f->>'wajib')::boolean, false) then continue; end if;
    v := p_jawaban -> (f->>'id');
    if v is null or v = '""'::jsonb or v = 'null'::jsonb or v = '[]'::jsonb then return 'Field wajib "' || (f->>'label') || '" harus diisi sebelum SPJ diajukan.'; end if;
  end loop;
  if blok is not null then
    v := p_jawaban -> (blok->>'id');
    if v is null or jsonb_typeof(v) <> 'array' or jsonb_array_length(v) = 0 then return 'Blok berulang "' || (blok->>'nama') || '" minimal harus memiliki satu entri.'; end if;
    for row in select * from jsonb_array_elements(v) loop
      i := i + 1;
      for bf in select * from jsonb_array_elements(blok->'fields') loop
        if not coalesce((bf->>'wajib')::boolean, false) then continue; end if;
        if (row -> (bf->>'id')) is null or (row -> (bf->>'id')) = '""'::jsonb then
          return 'Field wajib "' || (bf->>'label') || '" pada entri ' || i || ' blok "' || (blok->>'nama') || '" harus diisi.'; end if;
      end loop;
    end loop;
  end if;
  return null;
end $$;

create or replace function amanda.tag_field(p_fields jsonb, p_tag text) returns text language sql immutable as $$
  select f->>'id' from jsonb_array_elements(coalesce(p_fields, '[]'::jsonb)) f where f->>'system_tag' = p_tag limit 1 $$;

-- Identitas penugasan (NIP/NIK + rentang tanggal efektif) dari jawaban. Hasil: {"daftar":[{nip,mulai,selesai}],"error":null|text}
create or replace function amanda.identitas_jadwal(p_form form_dinamis, p_jawaban jsonb) returns jsonb
language plpgsql immutable as $$
declare
  daftar jsonb := '[]'; err text; mu text; se text; nip text; mb text; sb text; row jsonb; bf jsonb := p_form.blok_berulang -> 'fields';
  tm text; ts text; tn text; rows jsonb;
begin
  mu := btrim(coalesce(p_jawaban ->> amanda.tag_field(p_form.fields, '[SYS_START_DATE]'), ''));
  se := btrim(coalesce(p_jawaban ->> amanda.tag_field(p_form.fields, '[SYS_END_DATE]'), ''));
  nip := btrim(coalesce(p_jawaban ->> amanda.tag_field(p_form.fields, '[SYS_PERSONNEL_ID]'), ''));
  -- entri utama
  if nip <> '' then
    if mu = '' then err := 'Tanggal mulai tugas wajib diisi untuk NIP/NIK ' || nip || '.';
    elsif not amanda.tanggal_valid(mu) or (se <> '' and not amanda.tanggal_valid(se)) then err := 'Tanggal tugas untuk NIP/NIK ' || nip || ' tidak valid.';
    elsif coalesce(nullif(se, ''), mu) < mu then err := 'Tanggal selesai tugas untuk NIP/NIK ' || nip || ' tidak boleh sebelum tanggal mulai.';
    else daftar := daftar || jsonb_build_object('nip', nip, 'mulai', mu, 'selesai', coalesce(nullif(se, ''), mu)); end if;
  end if;
  if p_form.blok_berulang is not null then
    tn := amanda.tag_field(bf, '[SYS_PERSONNEL_ID]'); tm := amanda.tag_field(bf, '[SYS_START_DATE]'); ts := amanda.tag_field(bf, '[SYS_END_DATE]');
    rows := p_jawaban -> (p_form.blok_berulang ->> 'id');
    if rows is not null and jsonb_typeof(rows) = 'array' then
      for row in select * from jsonb_array_elements(rows) loop
        if jsonb_typeof(row) <> 'object' then continue; end if;
        nip := btrim(coalesce(row ->> tn, ''));
        mb := btrim(coalesce(row ->> tm, '')); sb := btrim(coalesce(row ->> ts, ''));
        if nip = '' then continue; end if;
        if (tm is not null and mb = '') or (ts is not null and sb = '') then
          if err is null then err := 'Tanggal tugas pada blok untuk NIP/NIK ' || nip || ' wajib diisi.'; end if; continue; end if;
        mb := coalesce(nullif(mb, ''), mu); sb := coalesce(nullif(sb, ''), se);
        if mb = '' then if err is null then err := 'Tanggal mulai tugas wajib diisi untuk NIP/NIK ' || nip || '.'; end if; continue; end if;
        if not amanda.tanggal_valid(mb) or (sb <> '' and not amanda.tanggal_valid(sb)) then if err is null then err := 'Tanggal tugas untuk NIP/NIK ' || nip || ' tidak valid.'; end if; continue; end if;
        if coalesce(nullif(sb, ''), mb) < mb then if err is null then err := 'Tanggal selesai tugas untuk NIP/NIK ' || nip || ' tidak boleh sebelum tanggal mulai.'; end if; continue; end if;
        daftar := daftar || jsonb_build_object('nip', nip, 'mulai', mb, 'selesai', coalesce(nullif(sb, ''), mb));
      end loop;
    end if;
  end if;
  return jsonb_build_object('daftar', daftar, 'error', err);
end $$;

-- Catat pasangan NIP/NIK + nama ke Direktori Transaksional dari jawaban (BNT-04)
create or replace function amanda.catat_direktori_dari_jawaban(p_form form_dinamis, p_jawaban jsonb, p_spj text) returns void
language plpgsql volatile security definer set search_path = public, amanda as $$
declare nip text; nama text; row jsonb; bf jsonb := p_form.blok_berulang -> 'fields'; did text;
begin
  nip := btrim(coalesce(p_jawaban ->> amanda.tag_field(p_form.fields, '[SYS_PERSONNEL_ID]'), ''));
  nama := btrim(coalesce(p_jawaban ->> amanda.tag_field(p_form.fields, '[SYS_PERSONNEL_NAME]'), ''));
  if nip <> '' and nama <> '' then
    insert into direktori_transaksional (nip_nik, nama) values (nip, nama) on conflict (nip_nik) do nothing;
    select id into did from direktori_transaksional where nip_nik = nip;
    insert into direktori_transaksional_ref (direktori_id, spj_id) values (did, p_spj) on conflict do nothing;
  end if;
  if p_form.blok_berulang is not null and jsonb_typeof(p_jawaban -> (p_form.blok_berulang ->> 'id')) = 'array' then
    for row in select * from jsonb_array_elements(p_jawaban -> (p_form.blok_berulang ->> 'id')) loop
      if jsonb_typeof(row) <> 'object' then continue; end if;
      nip := btrim(coalesce(row ->> amanda.tag_field(bf, '[SYS_PERSONNEL_ID]'), ''));
      nama := btrim(coalesce(row ->> amanda.tag_field(bf, '[SYS_PERSONNEL_NAME]'), ''));
      if nip <> '' and nama <> '' then
        insert into direktori_transaksional (nip_nik, nama) values (nip, nama) on conflict (nip_nik) do nothing;
        select id into did from direktori_transaksional where nip_nik = nip;
        insert into direktori_transaksional_ref (direktori_id, spj_id) values (did, p_spj) on conflict do nothing;
      end if;
    end loop;
  end if;
end $$;

-- ============ SPJ: BUAT, JAWABAN, REKENING, LAMPIRAN, PAJAK ============
-- Pembantu: muat SPJ + kuitansi, periksa kepemilikan PPTK, kunci TA. Mengembalikan pesan galat atau NULL.
create or replace function amanda.spj_draft_milik_pptk(p_spj text, out s spj, out k kuitansi, out err text) returns record
language plpgsql volatile security definer set search_path = public, amanda as $$
begin
  select * into s from spj where id = p_spj;
  if not found then err := 'SPJ tidak ditemukan.'; return; end if;
  perform 1 from tahun_anggaran where id = s.ta_id for update;
  select * into s from spj where id = p_spj for update;
  select * into k from kuitansi where id = s.kuitansi_id;
  if amanda.peran() is distinct from 'pptk' then err := 'Hanya PPTK yang dapat mengubah SPJ.'; return; end if;
  if k.id is null or not amanda.pptk_pemilik(k.ta_id, k.seksi_ta_id) then err := 'SPJ bukan milik seksi ini.'; return; end if;
  if not amanda.ta_boleh(s.ta_id, 'buat') then err := 'SPJ hanya dapat diubah pada TA Aktif Penuh.'; return; end if;
  if s.status <> 'Draft' then err := 'SPJ yang sudah Terkunci tidak dapat diubah.'; return; end if;
end $$;

create or replace function public.pptk_spj_buat(p_ta text, p_kuitansi text, p_jenis text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare k kuitansi; f form_dinamis; v_id text := gen_random_uuid()::text; t tahun_anggaran;
begin
  select * into t from tahun_anggaran where id = p_ta for update;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  if t.status <> 'Aktif Penuh' then return amanda.gagal('SPJ baru hanya pada TA Aktif Penuh. Status: ' || t.status || '.'); end if;
  if not amanda.gerbang_terbuka(p_ta) then return amanda.gagal('Gatekeeper tertutup. SPJ baru belum dapat dibuat.'); end if;
  select * into k from kuitansi where id = p_kuitansi for update;
  if not found then return amanda.gagal('Kuitansi tidak ditemukan.'); end if;
  if k.ta_id <> p_ta then return amanda.gagal('Kuitansi tidak tergabung dalam TA ini.'); end if;
  if exists (select 1 from spj where kuitansi_id = p_kuitansi) then return amanda.gagal('Kuitansi ini sudah memiliki SPJ. Satu kuitansi hanya berpasangan dengan satu SPJ.'); end if;
  if not amanda.pptk_pemilik(k.ta_id, k.seksi_ta_id) then return amanda.gagal('Hanya PPTK seksi pemilik yang dapat membuat SPJ.'); end if;
  if btrim(coalesce(p_jenis, '')) = '' then return amanda.gagal('Jenis belanja wajib dipilih.'); end if;
  select * into f from form_dinamis where jenis_belanja = p_jenis order by substring(versi from 2)::int desc limit 1;
  if not found then return amanda.gagal('Form Dinamis untuk jenis belanja ini belum dibuat.'); end if;
  insert into spj (id, ta_id, kuitansi_id, jenis_belanja, versi_form, status) values (v_id, p_ta, p_kuitansi, p_jenis, f.versi, 'Draft');
  update kuitansi set status = 'Terkunci' where id = p_kuitansi;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'id', v_id, 'versi_form', f.versi);
end $$;

create or replace function public.pptk_spj_jawaban(p_spj text, p_jawaban jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare r record; f form_dinamis;
begin
  select * into r from amanda.spj_draft_milik_pptk(p_spj);
  if r.err is not null then return amanda.gagal(r.err); end if;
  if p_jawaban is null or jsonb_typeof(p_jawaban) <> 'object' then return amanda.gagal('Data jawaban tidak valid.'); end if;
  update spj set jawaban = p_jawaban where id = p_spj;
  select * into f from form_dinamis where jenis_belanja = (r.s).jenis_belanja and versi = (r.s).versi_form;
  if found then perform amanda.catat_direktori_dari_jawaban(f, p_jawaban, p_spj); end if;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- Rekening penerima: snapshot immutable pada SPJ; entri baru otomatis masuk Direktori Rekening Bank (REK-01/02).
-- p_baris: [{"account_name","bank_name","account_number","alias"}]
create or replace function public.pptk_spj_rekening(p_spj text, p_baris jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare r record; b jsonb; i int := 0; n text; bk text; no text; al text; kosong boolean;
begin
  select * into r from amanda.spj_draft_milik_pptk(p_spj);
  if r.err is not null then return amanda.gagal(r.err); end if;
  if p_baris is null or jsonb_typeof(p_baris) <> 'array' then return amanda.gagal('Data rekening tidak valid.'); end if;
  -- validasi dulu semuanya sebelum menulis
  for b in select * from jsonb_array_elements(p_baris) loop
    i := i + 1;
    n := btrim(coalesce(b->>'account_name', '')); bk := btrim(coalesce(b->>'bank_name', '')); no := btrim(coalesce(b->>'account_number', '')); al := btrim(coalesce(b->>'alias', ''));
    kosong := n = '' and bk = '' and no = '' and al = '';
    if not kosong and (n = '' or bk = '' or no = '') then
      return amanda.gagal('Rekening baris ' || i || ' belum lengkap: nama penerima, nama bank, dan nomor rekening wajib diisi.'); end if;
  end loop;
  delete from spj_rekening_penerima where spj_id = p_spj;
  for b in select * from jsonb_array_elements(p_baris) loop
    n := btrim(coalesce(b->>'account_name', '')); bk := btrim(coalesce(b->>'bank_name', '')); no := btrim(coalesce(b->>'account_number', '')); al := btrim(coalesce(b->>'alias', ''));
    if n = '' and bk = '' and no = '' and al = '' then continue; end if;
    insert into spj_rekening_penerima (spj_id, account_name, bank_name, account_number, alias) values (p_spj, n, bk, no, nullif(al, ''));
    if not exists (select 1 from direktori_rekening_bank d where lower(d.account_name) = lower(n) and lower(d.bank_name) = lower(bk) and lower(d.account_number) = lower(no)) then
      insert into direktori_rekening_bank (account_name, bank_name, account_number, alias) values (n, bk, no, nullif(al, ''));
    end if;
  end loop;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- Lampiran PDF: berkas di Supabase Storage (bucket `lampiran-spj`) diunggah klien lebih dulu; RPC ini mencatat metadatanya.
-- Maksimal 30 MB; <=5 MB langsung (BYPASSED); >5 MB harus dikompresi (client/server) sebelum dicatat final.
create or replace function public.pptk_spj_lampiran(p_spj text, p_key text, p_nama text, p_ukuran_asal bigint, p_ukuran_final bigint default null, p_status_optimasi text default null) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare r record; st text := p_status_optimasi; fin bigint := p_ukuran_final;
begin
  select * into r from amanda.spj_draft_milik_pptk(p_spj);
  if r.err is not null then return amanda.gagal(r.err); end if;
  if lower(regexp_replace(coalesce(p_nama, ''), '^.*\.', '')) <> 'pdf' then return amanda.gagal('Lampiran SPJ harus berformat PDF.'); end if;
  if p_ukuran_asal is null or p_ukuran_asal <= 0 then return amanda.gagal('Ukuran berkas tidak valid.'); end if;
  if p_ukuran_asal > 30 * 1048576 then return amanda.gagal('Ukuran file melebihi batas maksimal 30 MB. Harap sesuaikan setelan scanner Anda.'); end if;
  if btrim(coalesce(p_key, '')) = '' or p_key not like p_spj || '/%' then return amanda.gagal('Kunci berkas tidak valid.'); end if;
  if p_ukuran_asal <= 5 * 1048576 then st := 'BYPASSED'; fin := p_ukuran_asal;
  else
    if st is null or st not in ('CLIENT_COMPRESSED','SERVER_FALLBACK_COMPRESSED') then st := 'SERVER_FALLBACK_COMPRESSED'; end if;
    if fin is not null and fin > p_ukuran_asal then fin := p_ukuran_asal; end if;
  end if;
  update spj set lampiran_key = p_key, lampiran_nama_asli = p_nama, lampiran_ukuran_asal = p_ukuran_asal, lampiran_ukuran_final = fin, lampiran_status_optimasi = st where id = p_spj;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'status_optimasi', st);
end $$;

create or replace function public.pptk_spj_lampiran_hapus(p_spj text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare r record; key text;
begin
  select * into r from amanda.spj_draft_milik_pptk(p_spj);
  if r.err is not null then return amanda.gagal(r.err); end if;
  key := (r.s).lampiran_key;
  update spj set lampiran_key = null, lampiran_nama_asli = null, lampiran_ukuran_asal = null, lampiran_ukuran_final = null, lampiran_status_optimasi = null where id = p_spj;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'hapus_key', key);   -- klien menghapus objek Storage ini
end $$;

-- Hak unduh lampiran (SPJ-08): Bendahara, Verifikator, PA/KPA seluruh seksi; PPTK seksinya. Admin/Pengawas/Publik ditolak.
create or replace function public.spj_lampiran_hak(p_spj text) returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
declare s spj; k kuitansi; pr text := amanda.peran();
begin
  select * into s from spj where id = p_spj;
  if not found then return amanda.gagal('SPJ tidak ditemukan.'); end if;
  select * into k from kuitansi where id = s.kuitansi_id;
  if amanda.ta() is distinct from s.ta_id or not (pr in ('bendahara','verifikator','pa_kpa') or (pr = 'pptk' and amanda.seksi() = k.seksi_ta_id)) then
    return amanda.gagal('Anda tidak berwenang mengunduh lampiran SPJ ini.'); end if;
  if s.lampiran_key is null then return amanda.gagal('SPJ ini belum memiliki lampiran.'); end if;
  return jsonb_build_object('ok', true, 'key', s.lampiran_key, 'nama', s.lampiran_nama_asli);
end $$;

-- Pajak (PJK-01): pengganti seluruh daftar; total <= bruto. p_entri: [{"jenis_pajak_id","nominal"}]
create or replace function public.pptk_spj_pajak(p_spj text, p_entri jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare r record; e jsonb; total numeric := 0; nom numeric;
begin
  select * into r from amanda.spj_draft_milik_pptk(p_spj);
  if r.err is not null then return amanda.gagal(r.err); end if;
  if p_entri is null or jsonb_typeof(p_entri) <> 'array' then return amanda.gagal('Data pajak tidak valid.'); end if;
  for e in select * from jsonb_array_elements(p_entri) loop
    if not exists (select 1 from jenis_pajak where id = e->>'jenis_pajak_id' and status = 'Aktif') then return amanda.gagal('Jenis pajak harus dipilih dari Master Jenis Pajak yang aktif.'); end if;
    if jsonb_typeof(e->'nominal') is distinct from 'number' then return amanda.gagal('Nominal pajak harus bilangan bulat rupiah lebih dari nol.'); end if;
    nom := (e->>'nominal')::numeric;
    if nom <= 0 or nom <> trunc(nom) then return amanda.gagal('Nominal pajak harus bilangan bulat rupiah lebih dari nol.'); end if;
    total := total + nom;
  end loop;
  if total > (r.k).bruto then
    return amanda.gagal('Total Pajak ' || amanda.rupiah(total::bigint) || ' melebihi bruto kuitansi ' || amanda.rupiah((r.k).bruto) || '. Batas Total Pajak adalah bruto kuitansi ' || amanda.rupiah((r.k).bruto) || '; entri tidak tersimpan.'); end if;
  delete from spj_pajak where spj_id = p_spj;
  insert into spj_pajak (spj_id, jenis_pajak_id, nominal) select p_spj, x->>'jenis_pajak_id', (x->>'nominal')::bigint from jsonb_array_elements(p_entri) x;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'total_pajak', total, 'dibayarkan', (r.k).bruto - total);
end $$;

-- ============ SPJ: AJUKAN, LEPAS ============
create or replace function public.pptk_spj_ajukan(p_spj text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare s spj; k kuitansi; f form_dinamis; err text; jd jsonb; item jsonb; bentrok record; irisan_mulai date; irisan_selesai date; seksi text; rentang text;
begin
  select * into s from spj where id = p_spj;
  if not found then return amanda.gagal('SPJ tidak ditemukan.'); end if;
  perform 1 from tahun_anggaran where id = s.ta_id for update;
  select * into s from spj where id = p_spj for update;
  select * into k from kuitansi where id = s.kuitansi_id;
  if amanda.peran() is distinct from 'pptk' then return amanda.gagal('Hanya PPTK yang dapat mengajukan SPJ.'); end if;
  if not amanda.pptk_pemilik(k.ta_id, k.seksi_ta_id) then return amanda.gagal('SPJ bukan milik seksi ini.'); end if;
  if not amanda.ta_boleh(s.ta_id, 'aksi') then return amanda.gagal('Pengajuan SPJ tidak diizinkan pada status TA saat ini.'); end if;
  if s.status <> 'Draft' then return amanda.gagal('Hanya SPJ Draft yang dapat diajukan.'); end if;
  select * into f from form_dinamis where jenis_belanja = s.jenis_belanja and versi = s.versi_form;
  if found then
    err := amanda.cek_wajib(f, s.jawaban);
    if err is not null then return amanda.gagal(err); end if;
    jd := amanda.identitas_jadwal(f, s.jawaban);
    if jd->>'error' is not null then return amanda.gagal(jd->>'error'); end if;
    for item in select * from jsonb_array_elements(jd->'daftar') loop
      select r.spj_id, r.mulai, r.selesai into bentrok from rentang_penugasan_spj r join spj o on o.id = r.spj_id
        where r.ta_id = s.ta_id and r.spj_id <> s.id and o.status <> 'Draft' and r.nip_nik = item->>'nip'
          and (item->>'mulai')::date <= r.selesai and (item->>'selesai')::date >= r.mulai limit 1;
      if found then
        irisan_mulai := greatest((item->>'mulai')::date, bentrok.mulai); irisan_selesai := least((item->>'selesai')::date, bentrok.selesai);
        select sk.nama_snapshot into seksi from spj o2 join kuitansi k2 on k2.id = o2.kuitansi_id join seksi_ta sk on sk.id = k2.seksi_ta_id where o2.id = bentrok.spj_id;
        rentang := case when irisan_mulai = irisan_selesai then irisan_mulai::text else irisan_mulai::text || ' s.d. ' || irisan_selesai::text end;
        -- M-98: hanya identitas, rentang irisan, dan referensi secukupnya; tanpa isi atau nominal pembanding.
        return amanda.gagal('Bentrok jadwal: NIP/NIK ' || (item->>'nip') || ' sudah tercatat pada SPJ ' || bentrok.spj_id || case when seksi is not null then ' (' || seksi || ')' else '' end || ' untuk tanggal ' || rentang || '. SPJ tetap Draft.');
      end if;
    end loop;
    delete from rentang_penugasan_spj where spj_id = s.id;
    insert into rentang_penugasan_spj (ta_id, spj_id, nip_nik, mulai, selesai)
      select s.ta_id, s.id, x->>'nip', (x->>'mulai')::date, (x->>'selesai')::date from jsonb_array_elements(jd->'daftar') x;
    perform amanda.catat_direktori_dari_jawaban(f, s.jawaban, s.id);
  end if;
  update spj set penandatangan_pengajuan = amanda.snapshot_penandatangan(s.ta_id, k.seksi_ta_id), tanggal_pengajuan = amanda.hari_ini_wita(), status = 'Terkunci' where id = s.id;
  perform amanda.catat_audit(s.ta_id, 'SPJ ' || s.jenis_belanja, 'aksi_administratif', null, 'SPJ diajukan ke Verifikator', null, false, s.kuitansi_id, s.id, k.seksi_ta_id);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- Lepas/batalkan SPJ Draft: kuitansi kembali Aktif, SPJ dihapus tanpa jejak (F-33a).
create or replace function public.pptk_spj_lepas(p_spj text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare s spj; k kuitansi; key text;
begin
  select * into s from spj where id = p_spj;
  if not found then return amanda.gagal('SPJ tidak ditemukan.'); end if;
  perform 1 from tahun_anggaran where id = s.ta_id for update;
  select * into s from spj where id = p_spj for update;
  select * into k from kuitansi where id = s.kuitansi_id;
  if not amanda.pptk_pemilik(k.ta_id, k.seksi_ta_id) then return amanda.gagal('Hanya PPTK seksi pemilik yang dapat melepas SPJ.'); end if;
  if not amanda.ta_boleh(s.ta_id, 'aksi') then return amanda.gagal('Pelepasan SPJ tidak diizinkan pada status TA saat ini.'); end if;
  if s.status <> 'Draft' then return amanda.gagal('Hanya SPJ Draft yang dapat dilepas. SPJ Terkunci harus dikembalikan Verifikator terlebih dahulu.'); end if;
  key := s.lampiran_key;
  delete from audit_event where spj_id = p_spj;
  delete from spj where id = p_spj;      -- cascade: pajak, rekening penerima, rentang, token, bku
  update kuitansi set status = 'Aktif' where id = s.kuitansi_id;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'hapus_key', key);
end $$;

-- ============ VERIFIKASI (VER-01..05) ============
create or replace function amanda.verifikasi_mandiri(p_spj spj) returns boolean
language plpgsql stable security definer set search_path = public, amanda as $$
declare per personel; k kuitansi; kunci text[];
begin
  select * into per from personel where id = amanda.personel();
  if per.id is null then return false; end if;
  select * into k from kuitansi where id = p_spj.kuitansi_id;
  kunci := array_remove(array[nullif(btrim(per.nip), ''), nullif(btrim(per.nik), '')], null);
  if k.pptk_nip = any(kunci) then return true; end if;
  if p_spj.penandatangan_pengajuan is not null and (p_spj.penandatangan_pengajuan->>'pptk_nip') = any(kunci) then return true; end if;
  if exists (select 1 from penugasan_ta t where t.ta_id = p_spj.ta_id and t.peran = 'pptk' and t.seksi_ta_id = k.seksi_ta_id and t.personel_id = per.id) then return true; end if;
  if exists (select 1 from penugasan_delegasi d where d.ta_id = p_spj.ta_id and d.peran_digantikan = 'pptk' and d.seksi_ta_id = k.seksi_ta_id and d.personel_pengganti_id = per.id) then return true; end if;
  return false;
end $$;

create or replace function amanda.susun_nomor(p_tahun text, f format_nomor_verifikasi, p_urut int) returns text language sql immutable as $$
  select concat_ws(f.pemisah, lpad(p_urut::text, f.digit, '0'), nullif(btrim(f.awalan), ''),
    case f.pola_tahun when 'YYYY' then p_tahun when 'YY' then right(p_tahun, 2) else null end) $$;

create or replace function amanda.token_acak() returns text language plpgsql volatile security definer set search_path = public, amanda, extensions as $$
declare abc constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; b bytea; t text; i int;
begin
  loop
    b := gen_random_bytes(24); t := '';
    for i in 0..23 loop t := t || substr(abc, (get_byte(b, i) % 32) + 1, 1); end loop;
    exit when not exists (select 1 from token_verifikasi_spj where token = t);
  end loop;
  return t;
end $$;

create or replace function public.ver_spj_kembalikan(p_spj text, p_catatan text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare s spj; k kuitansi;
begin
  select * into s from spj where id = p_spj;
  if not found then return amanda.gagal('SPJ tidak ditemukan.'); end if;
  perform 1 from tahun_anggaran where id = s.ta_id for update;
  select * into s from spj where id = p_spj for update;
  select * into k from kuitansi where id = s.kuitansi_id;
  if amanda.peran() is distinct from 'verifikator' or amanda.ta() is distinct from s.ta_id then return amanda.gagal('Hanya Verifikator yang dapat mengembalikan SPJ.'); end if;
  if not amanda.ta_boleh(s.ta_id, 'aksi') then return amanda.gagal('Pengembalian SPJ tidak diizinkan pada status TA saat ini.'); end if;
  if amanda.verifikasi_mandiri(s) then return amanda.gagal('Anda tidak dapat memverifikasi SPJ yang Anda ajukan atau kelola sendiri.'); end if;
  if s.status = 'Dibukukan' then return amanda.gagal('SPJ sudah dibukukan. Bendahara harus mencabut BKU terlebih dahulu.'); end if;
  if s.status not in ('Terkunci','Menunggu BKU') then return amanda.gagal('Hanya SPJ Terkunci atau Menunggu BKU yang dapat dikembalikan.'); end if;
  if btrim(coalesce(p_catatan, '')) = '' then return amanda.gagal('Catatan revisi wajib diisi.'); end if;
  update spj set status = 'Draft', catatan_revisi = btrim(p_catatan), dikembalikan = true where id = s.id;
  update token_verifikasi_spj set status = 'Tidak berlaku' where spj_id = s.id;        -- VER-03
  delete from rentang_penugasan_spj where spj_id = s.id;                                -- jadwal hanya dihitung untuk SPJ non-Draft
  perform amanda.catat_audit(s.ta_id, 'SPJ ' || s.jenis_belanja, 'verifikasi_kembalikan', null, 'Dikembalikan: ' || btrim(p_catatan), null, false, s.kuitansi_id, s.id, k.seksi_ta_id);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ver_spj_setujui(p_spj text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare s spj; k kuitansi; t tahun_anggaran; f format_nomor_verifikasi; urut int; nomor text; tk text; sesi sesi_amanda := amanda.sesi();
begin
  select * into s from spj where id = p_spj;
  if not found then return amanda.gagal('SPJ tidak ditemukan.'); end if;
  select * into t from tahun_anggaran where id = s.ta_id for update;
  select * into s from spj where id = p_spj for update;
  select * into k from kuitansi where id = s.kuitansi_id;
  if amanda.peran() is distinct from 'verifikator' or amanda.ta() is distinct from s.ta_id then return amanda.gagal('Hanya Verifikator yang dapat menyetujui SPJ.'); end if;
  if not amanda.ta_boleh(s.ta_id, 'aksi') then return amanda.gagal('Persetujuan SPJ tidak diizinkan pada status TA saat ini.'); end if;
  if amanda.verifikasi_mandiri(s) then return amanda.gagal('Anda tidak dapat memverifikasi SPJ yang Anda ajukan atau kelola sendiri.'); end if;
  if s.status <> 'Terkunci' then return amanda.gagal('Hanya SPJ Terkunci yang dapat disetujui.'); end if;
  update token_verifikasi_spj set status = 'Tidak berlaku' where spj_id = s.id;
  select * into f from format_nomor_verifikasi where ta_id = s.ta_id;
  if not found then insert into format_nomor_verifikasi (ta_id) values (s.ta_id) returning * into f; end if;
  insert into urut_verifikasi (ta_id, terakhir) values (s.ta_id, 1) on conflict (ta_id) do update set terakhir = urut_verifikasi.terakhir + 1 returning terakhir into urut;
  nomor := amanda.susun_nomor(t.tahun, f, urut);
  tk := amanda.token_acak();
  insert into token_verifikasi_spj (ta_id, spj_id, token, nomor_verifikasi, urut, tanggal_verifikasi, verifikator_nama, verifikator_nip, status)
  values (s.ta_id, s.id, tk, nomor, urut, amanda.hari_ini_wita(), sesi.nama_snapshot, coalesce(sesi.nip_snapshot, '—'), 'Berlaku');
  update spj set status = 'Menunggu BKU' where id = s.id;
  perform amanda.catat_audit(s.ta_id, 'SPJ ' || s.jenis_belanja, 'verifikasi_setujui', null, 'SPJ disetujui, Menunggu BKU (' || nomor || ')', null, false, s.kuitansi_id, s.id, k.seksi_ta_id);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'nomor', nomor);
end $$;

-- Format nomor verifikasi (TPL-04): hanya Admin; nomor yang sudah terbit tidak berubah.
create or replace function public.adm_format_nomor_simpan(p_ta text, p_awalan text, p_pemisah text, p_pola_tahun text, p_digit int) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare t tahun_anggaran; f format_nomor_verifikasi;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat mengubah format nomor verifikasi.'); end if;
  select * into t from tahun_anggaran where id = p_ta;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  if length(coalesce(p_awalan, '')) > 12 then return amanda.gagal('Awalan paling banyak 12 karakter.'); end if;
  if length(coalesce(p_pemisah, '')) > 2 then return amanda.gagal('Pemisah paling banyak 2 karakter.'); end if;
  if p_pola_tahun not in ('YYYY','YY','TANPA') then return amanda.gagal('Pola tahun tidak dikenal.'); end if;
  if p_digit is null or p_digit < 1 or p_digit > 8 then return amanda.gagal('Jumlah digit urut harus 1 sampai 8.'); end if;
  insert into format_nomor_verifikasi (ta_id, awalan, pemisah, pola_tahun, digit) values (p_ta, btrim(coalesce(p_awalan, '')), coalesce(p_pemisah, ''), p_pola_tahun, p_digit)
    on conflict (ta_id) do update set awalan = excluded.awalan, pemisah = excluded.pemisah, pola_tahun = excluded.pola_tahun, digit = excluded.digit
    returning * into f;
  perform amanda.catat_audit(p_ta, 'Format nomor verifikasi TA ' || t.tahun, 'aksi_administratif', null, 'Contoh: ' || amanda.susun_nomor(t.tahun, f, 1));
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'contoh', amanda.susun_nomor(t.tahun, f, 1));
end $$;

-- Data cetak Hasil Verifikasi SPJ (VER-04): PPTK seksi pemilik dan Verifikator saja.
create or replace function public.spj_cetak_verifikasi(p_spj text) returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
declare s spj; k kuitansi; tk token_verifikasi_spj; t tahun_anggaran; sk seksi_ta; pem pemetaan_subkegiatan_ta; rk rekening_belanja; total bigint; ttd jsonb; pr text := amanda.peran();
begin
  select * into s from spj where id = p_spj;
  if not found then return amanda.gagal('SPJ tidak ditemukan.'); end if;
  select * into k from kuitansi where id = s.kuitansi_id;
  if amanda.ta() is distinct from s.ta_id or not ((pr = 'pptk' and amanda.seksi() = k.seksi_ta_id) or pr = 'verifikator') then
    return amanda.gagal('Anda tidak berwenang mencetak Hasil Verifikasi SPJ ini.'); end if;
  if s.status not in ('Menunggu BKU','Dibukukan') then return amanda.gagal('Hasil Verifikasi hanya dapat dicetak untuk SPJ berstatus Menunggu BKU atau Dibukukan.'); end if;
  select * into tk from token_verifikasi_spj where spj_id = s.id order by urut desc limit 1;
  if not found or tk.status <> 'Berlaku' then return amanda.gagal('Token verifikasi SPJ tidak tersedia.'); end if;
  select * into t from tahun_anggaran where id = s.ta_id;
  select * into sk from seksi_ta where id = k.seksi_ta_id;
  select * into pem from pemetaan_subkegiatan_ta where id = k.pemetaan_subkegiatan_id;
  select * into rk from rekening_belanja where id = k.rekening_id;
  select coalesce(sum(nominal), 0) into total from spj_pajak where spj_id = s.id;
  ttd := coalesce(s.penandatangan_pengajuan, jsonb_build_object('pa_kpa_nama', k.pa_kpa_nama, 'pa_kpa_nip', k.pa_kpa_nip, 'bendahara_nama', k.bendahara_nama,
          'bendahara_nip', k.bendahara_nip, 'pptk_nama', k.pptk_nama, 'pptk_nip', k.pptk_nip));
  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'ta_tahun', t.tahun, 'seksi_nama', sk.nama_snapshot, 'spj_id', s.id, 'jenis_belanja', s.jenis_belanja,
    'nomor_verifikasi', tk.nomor_verifikasi, 'tanggal_verifikasi', tk.tanggal_verifikasi, 'verifikator_nama', tk.verifikator_nama, 'verifikator_nip', tk.verifikator_nip,
    'subkegiatan', pem.kode_snapshot || ' ' || pem.nama_snapshot, 'kode_rekening', rk.kode_rekening || ' ' || rk.nama, 'uraian', k.uraian, 'bruto', k.bruto, 'penerima', k.penerima,
    'rekening_penerima', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'account_name', r.account_name, 'bank_name', r.bank_name, 'account_number', r.account_number, 'alias', r.alias)) from spj_rekening_penerima r where r.spj_id = s.id), '[]'),
    'pajak', coalesce((select jsonb_agg(jsonb_build_object('nama', jp.nama_jenis_pajak, 'nominal', p.nominal)) from spj_pajak p join jenis_pajak jp on jp.id = p.jenis_pajak_id where p.spj_id = s.id), '[]'),
    'total_pajak', total, 'dibayarkan', k.bruto - total, 'token', tk.token) || ttd);
end $$;

-- Halaman keaslian publik (VER-05): respons seragam untuk token tidak dikenal / tidak berlaku; tanpa nominal.
create or replace function public.pub_cek_keaslian(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
declare tk token_verifikasi_spj; t tahun_anggaran; sk text;
begin
  select * into tk from token_verifikasi_spj where token = btrim(coalesce(p_token, ''));
  if not found or tk.status <> 'Berlaku' then return jsonb_build_object('berlaku', false); end if;
  select * into t from tahun_anggaran where id = tk.ta_id;
  select s.nama_snapshot into sk from spj p join kuitansi k on k.id = p.kuitansi_id join seksi_ta s on s.id = k.seksi_ta_id where p.id = tk.spj_id;
  if t.id is null or sk is null then return jsonb_build_object('berlaku', false); end if;
  return jsonb_build_object('berlaku', true, 'ta', 'TA ' || t.tahun, 'seksi', sk, 'tanggal', tk.tanggal_verifikasi, 'nomor', tk.nomor_verifikasi);
end $$;

-- ============ BKU (BKU-01..05) ============
create or replace function public.bend_bku_catat(p_spj text, p_nomor text, p_tanggal text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare s spj; k kuitansi; nomor text := btrim(coalesce(p_nomor, ''));
begin
  select * into s from spj where id = p_spj;
  if not found then return amanda.gagal('SPJ tidak ditemukan.'); end if;
  perform 1 from tahun_anggaran where id = s.ta_id for update;
  select * into s from spj where id = p_spj for update;
  select * into k from kuitansi where id = s.kuitansi_id;
  if amanda.peran() is distinct from 'bendahara' or amanda.ta() is distinct from s.ta_id then return amanda.gagal('Hanya Bendahara Pengeluaran yang dapat mencatat BKU.'); end if;
  if not amanda.ta_boleh(s.ta_id, 'aksi') then return amanda.gagal('Pencatatan BKU tidak diizinkan pada status TA saat ini.'); end if;
  if s.status <> 'Menunggu BKU' then return amanda.gagal('BKU hanya dapat dicatat untuk SPJ berstatus Menunggu BKU.'); end if;
  if exists (select 1 from bku where kuitansi_id = s.kuitansi_id and status = 'Aktif') then return amanda.gagal('Kuitansi ini sudah memiliki BKU. Satu kuitansi hanya boleh memiliki satu BKU.'); end if;
  if nomor = '' then return amanda.gagal('No. BKU wajib diisi.'); end if;
  if not amanda.tanggal_valid(p_tanggal) then return amanda.gagal('Tanggal BKU wajib diisi.'); end if;
  if exists (select 1 from bku where ta_id = s.ta_id and status = 'Aktif' and lower(btrim(nomor_bku)) = lower(nomor)) then return amanda.gagal('No. BKU ' || nomor || ' sudah dipakai di TA ini.'); end if;
  insert into bku (ta_id, kuitansi_id, spj_id, nomor_bku, tanggal_bku, status) values (s.ta_id, s.kuitansi_id, s.id, nomor, p_tanggal::date, 'Aktif');
  update spj set status = 'Dibukukan' where id = s.id;
  perform amanda.catat_audit(s.ta_id, 'BKU ' || nomor, 'pencatatan_bku', null, 'No. BKU ' || nomor || ', Tanggal ' || p_tanggal, null, false, s.kuitansi_id, s.id, k.seksi_ta_id);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.bend_bku_koreksi(p_bku text, p_nomor text, p_tanggal text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare b bku; k kuitansi; nomor text := btrim(coalesce(p_nomor, '')); lama text;
begin
  select * into b from bku where id = p_bku;
  if not found then return amanda.gagal('BKU tidak ditemukan.'); end if;
  perform 1 from tahun_anggaran where id = b.ta_id for update;
  select * into b from bku where id = p_bku for update;
  select * into k from kuitansi where id = b.kuitansi_id;
  if amanda.peran() is distinct from 'bendahara' or amanda.ta() is distinct from b.ta_id then return amanda.gagal('Hanya Bendahara Pengeluaran yang dapat mengoreksi BKU.'); end if;
  if not amanda.ta_boleh(b.ta_id, 'aksi') then return amanda.gagal('Koreksi BKU tidak diizinkan pada status TA saat ini.'); end if;
  if b.status <> 'Aktif' then return amanda.gagal('Hanya BKU aktif yang dapat dikoreksi.'); end if;
  if nomor = '' then return amanda.gagal('No. BKU wajib diisi.'); end if;
  if not amanda.tanggal_valid(p_tanggal) then return amanda.gagal('Tanggal BKU wajib diisi.'); end if;
  if nomor = b.nomor_bku and p_tanggal::date = b.tanggal_bku then return amanda.gagal('Tidak ada perubahan untuk disimpan.'); end if;
  if exists (select 1 from bku x where x.ta_id = b.ta_id and x.status = 'Aktif' and x.id <> b.id and lower(btrim(x.nomor_bku)) = lower(nomor)) then return amanda.gagal('No. BKU ' || nomor || ' sudah dipakai di TA ini.'); end if;
  lama := 'No. BKU ' || b.nomor_bku || ', Tanggal ' || b.tanggal_bku;
  update bku set nomor_bku = nomor, tanggal_bku = p_tanggal::date where id = b.id;
  perform amanda.catat_audit(b.ta_id, 'BKU ' || nomor, 'koreksi_bku', lama, 'No. BKU ' || nomor || ', Tanggal ' || p_tanggal, null, false, b.kuitansi_id, b.spj_id, k.seksi_ta_id);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- Pencabutan BKU (tanpa alasan tertulis): SPJ kembali Menunggu BKU; realisasi kembali menjadi komitmen.
create or replace function public.bend_bku_cabut(p_bku text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare b bku; k kuitansi;
begin
  select * into b from bku where id = p_bku;
  if not found then return amanda.gagal('BKU tidak ditemukan.'); end if;
  perform 1 from tahun_anggaran where id = b.ta_id for update;
  select * into b from bku where id = p_bku for update;
  select * into k from kuitansi where id = b.kuitansi_id;
  if amanda.peran() is distinct from 'bendahara' or amanda.ta() is distinct from b.ta_id then return amanda.gagal('Hanya Bendahara Pengeluaran yang dapat mencabut BKU.'); end if;
  if not amanda.ta_boleh(b.ta_id, 'aksi') then return amanda.gagal('Pencabutan BKU tidak diizinkan pada status TA saat ini.'); end if;
  if b.status <> 'Aktif' then return amanda.gagal('BKU sudah dicabut.'); end if;
  update bku set status = 'Dicabut' where id = b.id;
  update spj set status = 'Menunggu BKU' where id = b.spj_id and status = 'Dibukukan';
  perform amanda.catat_audit(b.ta_id, 'BKU ' || b.nomor_bku, 'pencabutan_bku', 'No. BKU ' || b.nomor_bku || ', Tanggal ' || b.tanggal_bku, 'Dicabut', null, false, b.kuitansi_id, b.spj_id, k.seksi_ta_id);
  perform amanda.sentuh();
  return jsonb_build_object('ok', true);
end $$;

-- ============ DIREKTORI (BNT-04, REK-01) ============
create or replace function public.direktori_lookup(p_nip_nik text) returns jsonb
language sql stable security definer set search_path = public, amanda as $$
  select case when amanda.peran() in ('pptk','bendahara','verifikator') then
    coalesce((select jsonb_build_object('ok', true, 'nama', nama) from direktori_transaksional where nip_nik = btrim(p_nip_nik)), jsonb_build_object('ok', true, 'nama', null))
    else amanda.gagal('Tidak berwenang.') end $$;

create or replace function public.rekening_bank_cari(p_q text default '') returns jsonb
language sql stable security definer set search_path = public, amanda as $$
  select case when amanda.peran() in ('pptk') then
    coalesce((select jsonb_agg(jsonb_build_object('id', id, 'account_name', account_name, 'bank_name', bank_name, 'account_number', account_number, 'alias', alias) order by account_name)
      from (select * from direktori_rekening_bank d where btrim(coalesce(p_q, '')) = '' or d.account_name ilike '%' || btrim(p_q) || '%' or coalesce(d.alias, '') ilike '%' || btrim(p_q) || '%' or d.account_number ilike '%' || btrim(p_q) || '%' limit 50) q), '[]')
    else '[]'::jsonb end $$;

-- ============ IZIN EKSEKUSI ============
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and (p.proname ~ '^(pptk_(kuitansi|spj)|ver_spj|bend_bku)_' or p.proname in ('adm_format_nomor_simpan','spj_cetak_verifikasi','spj_lampiran_hak','direktori_lookup','rekening_bank_cari','pub_cek_keaslian'))
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
grant execute on function public.pub_cek_keaslian(text) to anon, authenticated;
grant execute on all functions in schema amanda to authenticated;
