-- AMANDA — Langkah 7–9 (backend): laporan a–g dan kustom, drill-down, analitik/heatmap PA/KPA, portal publik anonim, retensi TA 12 tahun.
-- Port dari laporan.ts, drilldown.ts, analitik.ts, publik.ts, realisasi.ts. Basis laporan: BKU aktif pada SPJ Dibukukan (D01 §9 poin 3).
-- Cakupan peran ditegakkan di server: PPTK hanya seksinya; Pengawas hanya TA tugasnya (sesi terikat TA); Admin tidak mendapat angka transaksi.

-- ============ PEMBANTU ============
create or replace function amanda.persen2(p_bagian numeric, p_penyebut numeric) returns numeric language sql immutable as $$
  select case when p_penyebut > 0 then round(p_bagian / p_penyebut * 100, 2) end $$;
create or replace function amanda.persen1(p_bagian numeric, p_penyebut numeric) returns numeric language sql immutable as $$
  select case when p_penyebut > 0 then round(p_bagian / p_penyebut * 100, 1) end $$;

create or replace function amanda.pagu_sub(p_pem text) returns bigint language sql stable security definer set search_path = public, amanda as $$
  select coalesce((select pagu from alokasi_subkegiatan where pemetaan_subkegiatan_id = p_pem), 0) $$;
create or replace function amanda.pagu_seksi(p_ta text, p_seksi text) returns bigint language sql stable security definer set search_path = public, amanda as $$
  select coalesce(sum(s.pagu), 0)::bigint from pemetaan_subkegiatan_ta p join alokasi_subkegiatan s on s.pemetaan_subkegiatan_id = p.id where p.ta_id = p_ta and p.seksi_ta_id = p_seksi $$;

-- BKU aktif dari SPJ Dibukukan, dalam cakupan seksi dan periode tanggal BKU.
create or replace function amanda.baris_realisasi(p_ta text, p_seksi text[], p_dari text default null, p_sampai text default null)
returns table (bku_id text, nomor_bku text, tanggal_bku date, kuitansi_id text, spj_id text, seksi_id text, pemetaan_id text, rekening_id text, bruto bigint,
               uraian text, penerima text, tanggal_kuitansi date, status_kuitansi text, status_spj text, jenis_belanja text, versi_form text, jawaban jsonb)
language sql stable security definer set search_path = public, amanda as $$
  select b.id, b.nomor_bku, b.tanggal_bku, k.id, s.id, k.seksi_ta_id, k.pemetaan_subkegiatan_id, k.rekening_id, k.bruto,
         k.uraian, k.penerima, k.tanggal_kuitansi, k.status, s.status, s.jenis_belanja, s.versi_form, s.jawaban
  from bku b join spj s on s.id = b.spj_id join kuitansi k on k.id = b.kuitansi_id
  where b.ta_id = p_ta and b.status = 'Aktif' and s.status = 'Dibukukan' and k.seksi_ta_id = any(p_seksi)
    and (coalesce(p_dari, '') = '' or b.tanggal_bku >= p_dari::date) and (coalesce(p_sampai, '') = '' or b.tanggal_bku <= p_sampai::date)
  order by b.tanggal_bku, b.nomor_bku, b.id $$;

-- Cakupan seksi menurut peran. Mengembalikan {"seksi":[...]} atau {"error":"..."}.
create or replace function amanda.cakupan_seksi(p_ta text, p_seksi text) returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
declare pr text := amanda.peran(); semua text[]; lingkup text[];
begin
  if pr is null then return jsonb_build_object('error', 'Sesi tidak valid.'); end if;
  if not exists (select 1 from tahun_anggaran where id = p_ta) then return jsonb_build_object('error', 'TA tidak ditemukan.'); end if;
  if pr not in ('bendahara','verifikator','pa_kpa','pptk','pengawas') then return jsonb_build_object('error', 'Peran Anda tidak memiliki akses laporan.'); end if;
  if amanda.ta() is distinct from p_ta then
    return jsonb_build_object('error', case when pr = 'pengawas' then 'TA ini tidak termasuk penugasan Anda.' else 'TA tidak sesuai dengan sesi aktif.' end); end if;
  select array_agg(id order by nama_snapshot, id) into semua from seksi_ta where ta_id = p_ta;
  semua := coalesce(semua, '{}');
  lingkup := semua;
  if pr = 'pptk' then
    if amanda.seksi() is null or not (amanda.seksi() = any(semua)) then return jsonb_build_object('error', 'Seksi PPTK tidak valid.'); end if;
    lingkup := array[amanda.seksi()];
  end if;
  if coalesce(p_seksi, '') <> '' then
    if not (p_seksi = any(lingkup)) then return jsonb_build_object('error', 'Seksi di luar cakupan Anda.'); end if;
    lingkup := array[p_seksi];
  end if;
  return jsonb_build_object('seksi', to_jsonb(lingkup));
end $$;

create or replace function amanda.laporan_boleh(p_peran text) returns text[] language sql immutable as $$
  select case when p_peran = 'pa_kpa' then array['a','b','d','e','f','g']
              when p_peran in ('bendahara','verifikator','pptk','pengawas') then array['a','b','c','d','e','f','g']
              else '{}'::text[] end $$;

create or replace function amanda.ket_filter(p_f jsonb) returns text language plpgsql immutable as $$
declare b text[] := '{}';
begin
  if coalesce(p_f->>'dari', '') <> '' or coalesce(p_f->>'sampai', '') <> '' then
    b := b || ('Periode tanggal BKU ' || coalesce(nullif(p_f->>'dari', ''), '…') || ' s.d. ' || coalesce(nullif(p_f->>'sampai', ''), '…')); end if;
  if jsonb_typeof(p_f->'jenis_belanja') = 'array' and jsonb_array_length(p_f->'jenis_belanja') > 0 then
    b := b || ('Jenis belanja: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(p_f->'jenis_belanja') x)); end if;
  if jsonb_typeof(p_f->'jenis_pajak') = 'array' and jsonb_array_length(p_f->'jenis_pajak') > 0 then
    b := b || ('Jenis pajak: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(p_f->'jenis_pajak') x)); end if;
  return array_to_string(b, ' • ');
end $$;

create or replace function amanda.kol(p_nama text, p_tipe text default null) returns jsonb language sql immutable as $$
  select case when p_tipe is null then jsonb_build_object('nama', p_nama) else jsonb_build_object('nama', p_nama, 'tipe', p_tipe) end $$;

-- Kolom Form Dinamis: label berulang diberi penanda urut ("Nama Maskapai 1", "Nama Maskapai 2")
create or replace function amanda.kolom_form(p_fields jsonb, p_blok jsonb) returns jsonb language plpgsql immutable as $$
declare d jsonb := '[]'; x jsonb; jml jsonb := '{}'; ke jsonb := '{}'; lbl text; n int; res jsonb := '[]'; kk text;
begin
  for x in select e from jsonb_array_elements(coalesce(p_fields, '[]')) e order by coalesce((e->>'urutan')::int, 0) loop
    d := d || jsonb_build_array(jsonb_build_object('f', x, 'blok', false)); end loop;
  if p_blok is not null and jsonb_typeof(p_blok) = 'object' then
    for x in select e from jsonb_array_elements(coalesce(p_blok->'fields', '[]')) e order by coalesce((e->>'urutan')::int, 0) loop
      d := d || jsonb_build_array(jsonb_build_object('f', x, 'blok', true)); end loop;
  end if;
  for x in select e from jsonb_array_elements(d) e loop
    lbl := x->'f'->>'label'; jml := jsonb_set(jml, array[lbl], to_jsonb(coalesce((jml->>lbl)::int, 0) + 1), true);
  end loop;
  for x in select e from jsonb_array_elements(d) e loop
    lbl := x->'f'->>'label'; n := coalesce((ke->>lbl)::int, 0) + 1; ke := jsonb_set(ke, array[lbl], to_jsonb(n), true);
    kk := case when (jml->>lbl)::int > 1 then lbl || ' ' || n else lbl end;
    res := res || jsonb_build_array(jsonb_build_object('key', kk, 'id', x->'f'->>'id', 'blok', (x->>'blok')::boolean, 'tipe', x->'f'->>'tipe'));
  end loop;
  return res;
end $$;

create or replace function amanda.nilai_sel(p_tipe text, p_v jsonb) returns jsonb language plpgsql immutable as $$
declare t text;
begin
  if p_v is null or jsonb_typeof(p_v) <> 'string' then return null; end if;
  t := p_v #>> '{}';
  if t = '' then return null; end if;
  if p_tipe = 'angka' and t ~ '^-?\d+(\.\d+)?$' and length(t) < 15 then return to_jsonb(t::numeric); end if;
  return to_jsonb(t);
end $$;

create or replace function amanda.nip_pelaku(p_fields jsonb, p_blok jsonb, p_jawaban jsonb) returns text language plpgsql immutable as $$
declare h text[] := '{}'; f jsonb; e jsonb; v jsonb;
begin
  for f in select x from jsonb_array_elements(coalesce(p_fields, '[]')) x where x->>'system_tag' = '[SYS_PERSONNEL_ID]' loop
    v := p_jawaban -> (f->>'id');
    if v is not null and jsonb_typeof(v) = 'string' and (v #>> '{}') <> '' then h := h || (v #>> '{}'); end if;
  end loop;
  if p_blok is not null and jsonb_typeof(p_blok) = 'object' and jsonb_typeof(p_jawaban -> (p_blok->>'id')) = 'array' then
    for f in select x from jsonb_array_elements(coalesce(p_blok->'fields', '[]')) x where x->>'system_tag' = '[SYS_PERSONNEL_ID]' loop
      for e in select x from jsonb_array_elements(p_jawaban -> (p_blok->>'id')) x loop
        v := e -> (f->>'id');
        if v is not null and jsonb_typeof(v) = 'string' and (v #>> '{}') <> '' then h := h || (v #>> '{}'); end if;
      end loop;
    end loop;
  end if;
  return array_to_string(h, '; ');
end $$;

-- ============ LAPORAN BAKU (LAP-01..06) ============
create or replace function public.laporan_buat(p_id text, p_ta text, p_filter jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
declare
  pr text := amanda.peran(); f jsonb := coalesce(p_filter, '{}'); sc jsonb; seksi text[]; ta tahun_anggaran; pa boolean := (amanda.peran() = 'pa_kpa');
  dasar jsonb; judul text; baris jsonb; kolom jsonb; sheets jsonb := '[]'; r record; sid text; pagu bigint; v_real bigint; ket text; kf jsonb; k jsonb;
  b2 jsonb; jenis text; v_versi text; kolomnama text[]; bar jsonb; entri jsonb; e jsonb; fm form_dinamis; kfr jsonb; ent jsonb; cell jsonb; vv jsonb; rn int; names text[]; grp jsonb;
  v_nama text; sisa bigint; kum bigint; sub jsonb; blk jsonb := '[]'; pemid text; rekid text; al alokasi_rekening; totreal bigint; tampil jsonb; sampai text; pj jsonb; gkeys text[]; gk text; gi int;
begin
  if not (p_id = any(amanda.laporan_boleh(pr))) then
    return amanda.gagal(case when pr = 'admin' then 'Admin tidak mendapat laporan.' else 'Laporan ini tidak tersedia untuk peran Anda.' end); end if;
  sc := amanda.cakupan_seksi(p_ta, f->>'seksi_ta_id');
  if sc ? 'error' then return amanda.gagal(sc->>'error'); end if;
  select coalesce(array_agg(x), '{}') into seksi from jsonb_array_elements_text(sc->'seksi') x;
  select * into ta from tahun_anggaran where id = p_ta;
  ket := concat_ws(' • ', nullif('TA ' || ta.tahun, ''), nullif(amanda.ket_filter(f), ''));
  judul := case p_id when 'a' then 'Rekap realisasi per seksi' when 'b' then 'Buku Kas (BKU)' when 'c' then 'Daftar kuitansi dan SPJ'
    when 'd' then 'Realisasi per seksi dan subkegiatan' when 'e' then 'Rekap isian SPJ per jenis belanja' when 'f' then 'Rekap pajak per jenis pajak'
    else 'Rincian Kartu Kendali Kegiatan' end;
  dasar := jsonb_build_object('id', p_id, 'judul', judul, 'keterangan', ket);

  if p_id = 'a' then
    select coalesce(jsonb_agg(jsonb_build_array(s.nama_snapshot, amanda.pagu_seksi(p_ta, s.id),
        (select coalesce(sum(bruto), 0) from amanda.baris_realisasi(p_ta, array[s.id], f->>'dari', f->>'sampai')),
        amanda.persen2((select coalesce(sum(bruto), 0) from amanda.baris_realisasi(p_ta, array[s.id], f->>'dari', f->>'sampai')), amanda.pagu_seksi(p_ta, s.id)),
        amanda.status_seksi(p_ta, s.id)) order by s.nama_snapshot, s.id), '[]') into baris
      from seksi_ta s where s.id = any(seksi);
    return jsonb_build_object('ok', true, 'data', dasar || jsonb_build_object('judulDiSheet', true, 'sheets', jsonb_build_array(jsonb_build_object('nama', 'Rekap Realisasi', 'blok', jsonb_build_array(jsonb_build_object(
      'kolom', jsonb_build_array(amanda.kol('Seksi'), amanda.kol('Pagu','rupiah'), amanda.kol('Realisasi BKU','rupiah'), amanda.kol('Realisasi (%)','persen'), amanda.kol('Status')), 'baris', baris))))));
  end if;

  if p_id = 'b' then
    kolom := jsonb_build_array(amanda.kol('No. BKU'), amanda.kol('Tanggal BKU'), amanda.kol('Nominal','rupiah'));
    if not pa then kolom := kolom || jsonb_build_array(amanda.kol('Kuitansi Terkait')); end if;
    select coalesce(jsonb_agg(case when pa then jsonb_build_array(x.nomor_bku, x.tanggal_bku::text, x.bruto)
        else jsonb_build_array(x.nomor_bku, x.tanggal_bku::text, x.bruto, x.uraian || ' (' || x.penerima || ')') end order by x.tanggal_bku, x.nomor_bku, x.bku_id), '[]') into baris
      from amanda.baris_realisasi(p_ta, seksi, f->>'dari', f->>'sampai') x;
    return jsonb_build_object('ok', true, 'data', dasar || jsonb_build_object('judulDiSheet', true, 'sheets', jsonb_build_array(jsonb_build_object('nama', 'Buku Kas', 'blok', jsonb_build_array(jsonb_build_object('kolom', kolom, 'baris', baris))))));
  end if;

  if p_id = 'c' then
    select coalesce(jsonb_agg(jsonb_build_array(x.kuitansi_id, x.tanggal_kuitansi::text, (select nama_snapshot from seksi_ta where id = x.seksi_id), x.status_kuitansi, x.status_spj) order by x.tanggal_bku, x.nomor_bku, x.bku_id), '[]') into baris
      from amanda.baris_realisasi(p_ta, seksi, f->>'dari', f->>'sampai') x;
    return jsonb_build_object('ok', true, 'data', dasar || jsonb_build_object('judulDiSheet', true, 'sheets', jsonb_build_array(jsonb_build_object('nama', 'Kuitansi dan SPJ', 'blok', jsonb_build_array(jsonb_build_object(
      'kolom', jsonb_build_array(amanda.kol('Nomor Kuitansi'), amanda.kol('Tanggal Kuitansi'), amanda.kol('Seksi'), amanda.kol('Status Kuitansi'), amanda.kol('Status SPJ')), 'baris', baris))))));
  end if;

  if p_id = 'd' then
    select coalesce(jsonb_agg(jsonb_build_array(s.nama_snapshot, amanda.pagu_seksi(p_ta, s.id),
        (select coalesce(sum(bruto), 0) from amanda.baris_realisasi(p_ta, array[s.id], f->>'dari', f->>'sampai')),
        amanda.persen2((select coalesce(sum(bruto), 0) from amanda.baris_realisasi(p_ta, array[s.id], f->>'dari', f->>'sampai')), amanda.pagu_seksi(p_ta, s.id))) order by s.nama_snapshot, s.id), '[]') into baris
      from seksi_ta s where s.id = any(seksi);
    b2 := '[]';
    for r in select s.id as sid, s.nama_snapshot as sn, p.id as pid, p.kode_snapshot, p.nama_snapshot as pn from seksi_ta s join pemetaan_subkegiatan_ta p on p.seksi_ta_id = s.id and p.ta_id = p_ta
             where s.id = any(seksi) order by s.nama_snapshot, s.id, p.kode_snapshot loop
      pagu := amanda.pagu_sub(r.pid);
      select coalesce(sum(x.bruto), 0) into v_real from amanda.baris_realisasi(p_ta, seksi, f->>'dari', f->>'sampai') x where x.pemetaan_id = r.pid;
      b2 := b2 || jsonb_build_array(jsonb_build_array(r.sn, r.kode_snapshot, r.pn, pagu, v_real, amanda.persen2(v_real, pagu)));
    end loop;
    return jsonb_build_object('ok', true, 'data', dasar || jsonb_build_object('judulDiSheet', true, 'sheets', jsonb_build_array(jsonb_build_object('nama', 'Realisasi', 'blok', jsonb_build_array(
      jsonb_build_object('judul', jsonb_build_array('Per seksi'), 'kolom', jsonb_build_array(amanda.kol('Seksi'), amanda.kol('Pagu','rupiah'), amanda.kol('Realisasi BKU','rupiah'), amanda.kol('Realisasi (%)','persen')), 'baris', baris),
      jsonb_build_object('judul', jsonb_build_array('Per subkegiatan'), 'kolom', jsonb_build_array(amanda.kol('Seksi'), amanda.kol('Kode Subkegiatan'), amanda.kol('Subkegiatan'), amanda.kol('Pagu','rupiah'), amanda.kol('Realisasi BKU','rupiah'), amanda.kol('Realisasi (%)','persen')), 'baris', b2))))));
  end if;

  if p_id = 'e' then
    for jenis in select x.jenis_belanja from amanda.baris_realisasi(p_ta, seksi, f->>'dari', f->>'sampai') x
                 group by x.jenis_belanja order by min(x.tanggal_bku), min(x.nomor_bku), x.jenis_belanja loop
      if jsonb_typeof(f->'jenis_belanja') = 'array' and jsonb_array_length(f->'jenis_belanja') > 0 and not (f->'jenis_belanja') ? jenis then continue; end if;
      kolomnama := '{}';
      for v_versi in select y.versi_form from (select distinct x.versi_form, coalesce(nullif(regexp_replace(x.versi_form, '\D', '', 'g'), '')::int, 0) as nv
                   from amanda.baris_realisasi(p_ta, seksi, f->>'dari', f->>'sampai') x where x.jenis_belanja = jenis) y order by y.nv desc loop
        select * into fm from form_dinamis where jenis_belanja = jenis and form_dinamis.versi = v_versi;
        if fm.id is null then continue; end if;
        for k in select e2 from jsonb_array_elements(amanda.kolom_form(fm.fields, fm.blok_berulang)) e2 loop
          if not ((k->>'key') = any(kolomnama)) then kolomnama := kolomnama || (k->>'key'); end if;
        end loop;
      end loop;
      baris := '[]';
      for r in select x.* from amanda.baris_realisasi(p_ta, seksi, f->>'dari', f->>'sampai') x where x.jenis_belanja = jenis order by x.tanggal_bku, x.nomor_bku, x.bku_id loop
        select * into fm from form_dinamis where jenis_belanja = jenis and form_dinamis.versi = r.versi_form;
        if fm.id is null then continue; end if;
        kfr := amanda.kolom_form(fm.fields, fm.blok_berulang);
        if fm.blok_berulang is not null and jsonb_typeof(r.jawaban -> (fm.blok_berulang->>'id')) = 'array' and jsonb_array_length(r.jawaban -> (fm.blok_berulang->>'id')) > 0
          then entri := r.jawaban -> (fm.blok_berulang->>'id'); else entri := '[{}]'; end if;
        for ent in select x from jsonb_array_elements(entri) x loop
          bar := '[]';
          foreach v_nama in array kolomnama loop
            select x into k from jsonb_array_elements(kfr) x where x->>'key' = v_nama limit 1;
            if k is null then bar := bar || jsonb_build_array(null::jsonb);
            else
              vv := case when (k->>'blok')::boolean then ent -> (k->>'id') else r.jawaban -> (k->>'id') end;
              cell := amanda.nilai_sel(k->>'tipe', vv);
              bar := bar || jsonb_build_array(cell);
            end if;
          end loop;
          baris := baris || jsonb_build_array(bar);
        end loop;
      end loop;
      sheets := sheets || jsonb_build_array(jsonb_build_object('nama', jenis, 'blok', jsonb_build_array(jsonb_build_object(
        'judul', jsonb_build_array('Jenis Belanja: ' || jenis), 'kolom', (select coalesce(jsonb_agg(amanda.kol(n)), '[]') from unnest(kolomnama) with ordinality t(n, o)), 'baris', baris))));
    end loop;
    return jsonb_build_object('ok', true, 'data', dasar || jsonb_build_object('judulDiSheet', true, 'sheets', sheets));
  end if;

  if p_id = 'f' then
    kolom := jsonb_build_array(amanda.kol('Jenis Pajak'), amanda.kol('Nominal Pajak','rupiah'), amanda.kol('Seksi'), amanda.kol('Jenis Belanja'), amanda.kol('Kode Subkegiatan'), amanda.kol('Kode Rekening Belanja'), amanda.kol('No. BKU'));
    if not pa then kolom := kolom || jsonb_build_array(amanda.kol('Tanggal Kuitansi')); end if;
    names := '{}'; grp := '{}';
    for r in select x.* from amanda.baris_realisasi(p_ta, seksi, f->>'dari', f->>'sampai') x order by x.tanggal_bku, x.nomor_bku, x.bku_id loop
      for pj in select jsonb_build_object('jp', e.jenis_pajak_id, 'nom', e.nominal) from spj_pajak e where e.spj_id = r.spj_id order by e.ctid loop
        if jsonb_typeof(f->'jenis_pajak') = 'array' and jsonb_array_length(f->'jenis_pajak') > 0 and not (f->'jenis_pajak') ? (pj->>'jp') then continue; end if;
        v_nama := coalesce((select nama_jenis_pajak from jenis_pajak where id = pj->>'jp'), '—');
        bar := jsonb_build_array(v_nama, pj->'nom', (select nama_snapshot from seksi_ta where id = r.seksi_id), r.jenis_belanja,
          coalesce((select kode_snapshot from pemetaan_subkegiatan_ta where id = r.pemetaan_id), '—'), coalesce((select kode_rekening from rekening_belanja where id = r.rekening_id), '—'), r.nomor_bku);
        if not pa then bar := bar || jsonb_build_array(r.tanggal_kuitansi::text); end if;
        if not (v_nama = any(names)) then names := names || v_nama; end if;
        grp := jsonb_set(grp, array[v_nama], coalesce(grp -> v_nama, '[]') || jsonb_build_array(bar), true);
      end loop;
    end loop;
    foreach v_nama in array names loop
      sheets := sheets || jsonb_build_array(jsonb_build_object('nama', v_nama, 'blok', jsonb_build_array(jsonb_build_object('kolom', kolom, 'baris', grp -> v_nama))));
    end loop;
    return jsonb_build_object('ok', true, 'data', dasar || jsonb_build_object('judulDiSheet', false, 'sheets', sheets));
  end if;

  -- (g) Rincian Kartu Kendali Kegiatan: sisa anggaran dihitung dari awal TA (tanpa filter periode)
  gkeys := '{}'; grp := '{}';
  for r in select x.* from amanda.baris_realisasi(p_ta, seksi, null, null) x order by x.tanggal_bku, x.nomor_bku, x.bku_id loop
    if coalesce(f->>'pemetaan_id', '') <> '' and r.pemetaan_id <> f->>'pemetaan_id' then continue; end if;
    gk := r.pemetaan_id || '|' || r.rekening_id;
    if not (gk = any(gkeys)) then gkeys := gkeys || gk; end if;
    grp := jsonb_set(grp, array[gk], coalesce(grp -> gk, '[]') || jsonb_build_array(jsonb_build_object('tgl', r.tanggal_bku::text, 'no', r.nomor_bku, 'uraian', r.uraian, 'bruto', r.bruto)), true);
  end loop;
  foreach gk in array gkeys loop
    pemid := split_part(gk, '|', 1); rekid := split_part(gk, '|', 2);
    select * into al from alokasi_rekening where ta_id = p_ta and pemetaan_subkegiatan_id = pemid and rekening_id = rekid;
    pagu := coalesce(al.pagu, 0); kum := 0; tampil := '[]'; totreal := 0; sisa := pagu; gi := 0;
    for e in select x from jsonb_array_elements(grp -> gk) x loop
      kum := kum + (e->>'bruto')::bigint;
      if (coalesce(f->>'dari', '') = '' or (e->>'tgl') >= f->>'dari') and (coalesce(f->>'sampai', '') = '' or (e->>'tgl') <= f->>'sampai') then
        gi := gi + 1; totreal := totreal + (e->>'bruto')::bigint; sisa := pagu - kum;
        tampil := tampil || jsonb_build_array(jsonb_build_array(gi, e->>'tgl', e->>'no', e->>'uraian', (e->>'bruto')::bigint, pagu - kum));
      end if;
    end loop;
    continue when jsonb_array_length(tampil) = 0;
    blk := blk || jsonb_build_array(jsonb_build_object(
      'judul', jsonb_build_array(
        btrim('Subkegiatan: ' || coalesce((select kode_snapshot || ' ' || nama_snapshot from pemetaan_subkegiatan_ta where id = pemid), '')),
        btrim('Rekening Belanja: ' || coalesce((select kode_rekening || ' ' || nama from rekening_belanja where id = rekid), '')),
        'Pagu akhir: ' || amanda.rupiah(pagu)),
      'kolom', jsonb_build_array(amanda.kol('No'), amanda.kol('Tanggal'), amanda.kol('No. Bukti'), amanda.kol('Uraian'), amanda.kol('Realisasi','rupiah'), amanda.kol('Sisa Anggaran','rupiah')),
      'baris', tampil, 'total', jsonb_build_array('', '', '', 'TOTAL', totreal, sisa)));
  end loop;
  sampai := coalesce(nullif(f->>'sampai', ''), amanda.hari_ini_wita()::text);
  return jsonb_build_object('ok', true, 'data', jsonb_build_object('id', 'g', 'judul', judul,
    'keterangan', 'per ' || sampai || case when amanda.ket_filter(f) <> '' then ' • ' || amanda.ket_filter(f) else '' end,
    'judulDiSheet', true, 'sheets', jsonb_build_array(jsonb_build_object('nama', 'Kartu Kendali', 'blok', blk))));
end $$;

-- ============ LAPORAN KUSTOM (LAP-07) ============
create or replace function amanda.kolom_kustom() returns jsonb language sql immutable as $$
  select '[{"id":"tanggal_bku","label":"Tanggal BKU"},{"id":"no_bku","label":"No. BKU"},{"id":"subkegiatan","label":"Kode dan Nama Subkegiatan"},
  {"id":"rekening_belanja","label":"Kode dan Nama Rekening Belanja"},{"id":"uraian","label":"Uraian Kuitansi"},{"id":"penerima","label":"Nama Penerima"},
  {"id":"bruto","label":"Nilai Bruto"},{"id":"total_pajak","label":"Total Pajak"},{"id":"dibayarkan","label":"Jumlah Dibayarkan"},{"id":"nip_rekening","label":"NIP/NIK dan Nomor Rekening"}]'::jsonb $$;

create or replace function public.laporan_kolom_kustom() returns jsonb
language sql stable security definer set search_path = public, amanda as $$
  select coalesce(jsonb_agg(k), '[]') from jsonb_array_elements(amanda.kolom_kustom()) k
  where amanda.peran() in ('bendahara','pptk','verifikator','pa_kpa')
    and (amanda.peran() <> 'pa_kpa' or not (k->>'id') in ('rekening_belanja','uraian','penerima','nip_rekening')) $$;

-- p_param: {"kolom":["no_bku",...], "seksi_ta_id":"", "dari":"", "sampai":""}
create or replace function public.laporan_kustom(p_ta text, p_param jsonb, p_batas int default null) returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
declare pr text := amanda.peran(); minta text[]; boleh text[]; sc jsonb; seksi text[]; kolom jsonb := '[]'; baris jsonb := '[]'; urut text[]; r record; k jsonb; v_id text; o jsonb;
        total int := 0; tp bigint; fm form_dinamis; n int := 0;
begin
  if pr not in ('bendahara','pptk','verifikator','pa_kpa') then return amanda.gagal('Peran Anda tidak memiliki akses Penyusunan Laporan Kustom.'); end if;
  if p_param is null or jsonb_typeof(p_param->'kolom') <> 'array' or jsonb_array_length(p_param->'kolom') = 0 then return amanda.gagal('Pilih minimal satu kolom.'); end if;
  select array_agg(x) into minta from jsonb_array_elements_text(p_param->'kolom') x;
  select array_agg(v->>'id') into boleh from jsonb_array_elements(public.laporan_kolom_kustom()) v;
  if exists (select 1 from unnest(minta) m where not (m = any(boleh))) then return amanda.gagal('Permintaan ditolak: memuat kolom yang tidak diizinkan untuk peran Anda.'); end if;
  sc := amanda.cakupan_seksi(p_ta, p_param->>'seksi_ta_id');
  if sc ? 'error' then return amanda.gagal(sc->>'error'); end if;
  select coalesce(array_agg(x), '{}') into seksi from jsonb_array_elements_text(sc->'seksi') x;
  for o in select e from jsonb_array_elements(amanda.kolom_kustom()) e loop
    v_id := o->>'id';
    continue when not (v_id = any(minta));
    urut := urut || v_id;
    if v_id = 'nip_rekening' then kolom := kolom || jsonb_build_array(amanda.kol('NIP/NIK'), amanda.kol('Nomor Rekening'));
    else kolom := kolom || jsonb_build_array(amanda.kol(o->>'label', case when v_id in ('bruto','total_pajak','dibayarkan') then 'rupiah' end)); end if;
  end loop;
  for r in select x.* from amanda.baris_realisasi(p_ta, seksi, p_param->>'dari', p_param->>'sampai') x order by x.tanggal_bku, x.nomor_bku, x.bku_id loop
    total := total + 1;
    continue when p_batas is not null and total > p_batas;
    select coalesce(sum(nominal), 0) into tp from spj_pajak where spj_id = r.spj_id;
    select * into fm from form_dinamis where jenis_belanja = r.jenis_belanja and versi = r.versi_form;
    o := '[]';
    foreach v_id in array urut loop
      o := o || case v_id
        when 'tanggal_bku' then jsonb_build_array(r.tanggal_bku::text)
        when 'no_bku' then jsonb_build_array(r.nomor_bku)
        when 'subkegiatan' then jsonb_build_array(coalesce((select btrim(kode_snapshot || ' ' || nama_snapshot) from pemetaan_subkegiatan_ta where id = r.pemetaan_id), ''))
        when 'rekening_belanja' then jsonb_build_array(coalesce((select btrim(kode_rekening || ' ' || nama) from rekening_belanja where id = r.rekening_id), ''))
        when 'uraian' then jsonb_build_array(r.uraian)
        when 'penerima' then jsonb_build_array(r.penerima)
        when 'bruto' then jsonb_build_array(r.bruto)
        when 'total_pajak' then jsonb_build_array(tp)
        when 'dibayarkan' then jsonb_build_array(r.bruto - tp)
        when 'nip_rekening' then jsonb_build_array(nullif(amanda.nip_pelaku(fm.fields, fm.blok_berulang, r.jawaban), ''),
              nullif((select string_agg(account_number, '; ' order by ctid) from spj_rekening_penerima where spj_id = r.spj_id), ''))
        end;
    end loop;
    baris := baris || jsonb_build_array(o);
  end loop;
  return jsonb_build_object('ok', true, 'data', jsonb_build_object('kolom', kolom, 'baris', baris, 'totalBaris', total));
end $$;

-- ============ DRILL-DOWN (DRL-01, DRL-02) ============
create or replace function amanda.angka_tingkat(p_pagu bigint, p_real bigint, p_komit bigint, p_sisa bigint, p_seimbang boolean) returns jsonb language sql immutable as $$
  select jsonb_build_object('pagu', p_pagu, 'realisasi', p_real, 'komitmen', p_komit, 'sisaSpdBebas', p_sisa,
    'serapanPersen', case when p_pagu > 0 then ((p_real + p_komit)::numeric / p_pagu * 100)::float8 else 0 end, 'seimbang', p_seimbang) $$;

-- Cakupan: Bendahara/Verifikator/PPTK sampai rekening; PA/KPA sampai subkegiatan; Admin/Pengawas tidak punya drill-down.
create or replace function amanda.izin_drill(p_ta text, p_tingkat int, p_seksi text default null) returns text
language plpgsql stable security definer set search_path = public, amanda as $$
declare pr text := amanda.peran(); batas int;
begin
  batas := case pr when 'bendahara' then 3 when 'verifikator' then 3 when 'pptk' then 3 when 'pa_kpa' then 2 else null end;
  if batas is null then return 'Peran ini tidak memiliki tampilan drill-down anggaran.'; end if;
  if amanda.ta() is distinct from p_ta then return 'TA tidak sesuai dengan sesi aktif.'; end if;
  if p_tingkat > batas then return 'Peran ini tidak dapat membuka tingkat rekening belanja.'; end if;
  if pr = 'pptk' and p_seksi is not null and p_seksi <> amanda.seksi() then return 'PPTK hanya dapat melihat seksinya sendiri.'; end if;
  return null;
end $$;

create or replace function public.drill_seksi(p_ta text) returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
declare e text := amanda.izin_drill(p_ta, 1); res jsonb := '[]'; s record; pagu bigint; v_real bigint; komit bigint; sisa bigint; st text;
begin
  if e is not null then return amanda.gagal(e); end if;
  for s in select * from seksi_ta where ta_id = p_ta and (amanda.peran() <> 'pptk' or id = amanda.seksi()) order by nama_snapshot, id loop
    select coalesce(sum(amanda.pagu_sub(p.id)), 0), coalesce(sum(amanda.realisasi(a.id)), 0), coalesce(sum(amanda.komitmen(a.id)), 0), coalesce(sum(amanda.sisa_spd_bebas(a.id)), 0)
      into pagu, v_real, komit, sisa
      from pemetaan_subkegiatan_ta p left join alokasi_rekening a on a.pemetaan_subkegiatan_id = p.id where p.ta_id = p_ta and p.seksi_ta_id = s.id;
    -- pagu subkegiatan dijumlah sekali per subkegiatan (bukan per rekening)
    select coalesce(sum(amanda.pagu_sub(p.id)), 0) into pagu from pemetaan_subkegiatan_ta p where p.ta_id = p_ta and p.seksi_ta_id = s.id;
    st := amanda.status_seksi(p_ta, s.id);
    res := res || jsonb_build_array(jsonb_build_object('seksi_ta_id', s.id, 'nama', s.nama_snapshot, 'status', st) || amanda.angka_tingkat(pagu, v_real, komit, sisa, st = 'Tuntas (100% Seimbang)'));
  end loop;
  return jsonb_build_object('ok', true, 'data', res);
end $$;

create or replace function public.drill_subkegiatan(p_ta text, p_seksi text) returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
declare e text := amanda.izin_drill(p_ta, 2, p_seksi); res jsonb := '[]'; p record;
begin
  if e is not null then return amanda.gagal(e); end if;
  for p in select * from pemetaan_subkegiatan_ta where ta_id = p_ta and seksi_ta_id = p_seksi order by kode_snapshot loop
    res := res || jsonb_build_array(jsonb_build_object('pemetaan_id', p.id, 'kode', p.kode_snapshot, 'nama', p.nama_snapshot) || amanda.angka_tingkat(
      amanda.pagu_sub(p.id),
      (select coalesce(sum(amanda.realisasi(a.id)), 0) from alokasi_rekening a where a.pemetaan_subkegiatan_id = p.id)::bigint,
      (select coalesce(sum(amanda.komitmen(a.id)), 0) from alokasi_rekening a where a.pemetaan_subkegiatan_id = p.id)::bigint,
      (select coalesce(sum(amanda.sisa_spd_bebas(a.id)), 0) from alokasi_rekening a where a.pemetaan_subkegiatan_id = p.id)::bigint,
      amanda.pemetaan_seimbang(p.id)));
  end loop;
  return jsonb_build_object('ok', true, 'data', res);
end $$;

create or replace function public.drill_rekening(p_ta text, p_pemetaan text) returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
declare p pemetaan_subkegiatan_ta; e text; res jsonb := '[]'; a record; sb boolean;
begin
  select * into p from pemetaan_subkegiatan_ta where id = p_pemetaan and ta_id = p_ta;
  if not found then return amanda.gagal('Subkegiatan tidak ditemukan pada TA ini.'); end if;
  e := amanda.izin_drill(p_ta, 3, p.seksi_ta_id);
  if e is not null then return amanda.gagal(e); end if;
  sb := amanda.pemetaan_seimbang(p_pemetaan);
  for a in select * from alokasi_rekening where ta_id = p_ta and pemetaan_subkegiatan_id = p_pemetaan order by kode_rekening_snapshot loop
    res := res || jsonb_build_array(jsonb_build_object('alokasi_id', a.id, 'kode', a.kode_rekening_snapshot, 'nama', a.nama_rekening_snapshot)
      || amanda.angka_tingkat(a.pagu, amanda.realisasi(a.id), amanda.komitmen(a.id), amanda.sisa_spd_bebas(a.id), sb));
  end loop;
  return jsonb_build_object('ok', true, 'data', res);
end $$;

-- ============ ANALITIK PA/KPA (ANA-01..07) ============
create or replace function amanda.time_elapsed_pct(p_tahun int, p_hari date) returns numeric language plpgsql immutable as $$
declare awal date := make_date(p_tahun, 1, 1); akhir date := make_date(p_tahun, 12, 31); total int;
begin
  total := (akhir - awal) + 1;
  if p_hari < awal then return 0; end if;
  if p_hari > akhir then return 100; end if;
  return round(((p_hari - awal) + 1)::numeric / total * 100, 2);
end $$;

create or replace function public.analitik_seksi(p_ta text, p_hari text default null) returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
declare t tahun_anggaran; beku boolean; acuan date; te numeric; awalj date; s record; pagu bigint; v_real bigint; lonj bigint; burn numeric; spike numeric; zona text; lbl text; hasil jsonb := '[]';
        hijau int := 0; kuning int := 0; oranye int := 0; merah int := 0; dev text; burnteks text; tt int := 0; tahun int;
begin
  if amanda.peran() is distinct from 'pa_kpa' then return amanda.gagal('Analitik hanya dapat diakses PA/KPA.'); end if;
  if amanda.ta() is distinct from p_ta then return amanda.gagal('TA tidak sesuai dengan sesi aktif.'); end if;
  select * into t from tahun_anggaran where id = p_ta;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  beku := t.status in ('Masa Transisi','Arsip Read-Only');
  tahun := t.tahun::int;
  if nullif(p_hari, '') is not null and not amanda.tanggal_valid(p_hari) then return amanda.gagal('Format tanggal acuan tidak valid.'); end if;
  acuan := case when beku then make_date(tahun, 12, 31) else coalesce(nullif(p_hari, '')::date, amanda.hari_ini_wita()) end;
  te := case when beku then 100 else amanda.time_elapsed_pct(tahun, acuan) end;
  awalj := acuan - 13;
  for s in select * from seksi_ta where ta_id = p_ta order by nama_snapshot, id loop
    pagu := amanda.pagu_seksi(p_ta, s.id);
    select coalesce(sum(x.bruto), 0) into v_real from amanda.baris_realisasi(p_ta, array[s.id]) x;
    select coalesce(sum(x.bruto), 0) into lonj from amanda.baris_realisasi(p_ta, array[s.id]) x where x.tanggal_bku >= awalj and x.tanggal_bku <= acuan;
    burn := case when pagu > 0 then v_real::numeric / pagu * 100 end;
    spike := case when pagu > 0 then lonj::numeric / pagu * 100 end;
    zona := 'HIJAU';
    if burn is not null and te > 90 and burn < 60 then zona := 'MERAH';
    elsif spike is not null and spike >= 40 then zona := 'ORANYE';
    elsif burn is not null and te > 75 and burn < 50 then zona := 'KUNING'; end if;
    lbl := case zona when 'MERAH' then 'Kritis' when 'ORANYE' then 'Lonjakan Tidak Wajar' when 'KUNING' then 'Serapan Lambat' else 'Normal' end;
    burnteks := case when burn is null then 'Belum tersedia' else to_char(burn, 'FM990.0') || '%' end;
    dev := case when burn is null then '' else ' (deviasi ' || to_char(burn - te, 'FM990.0') || ' poin)' end;
    hasil := hasil || jsonb_build_array(jsonb_build_object('seksi_id', s.id, 'nama', s.nama_snapshot, 'pagu_sah_terakhir', pagu, 'realisasi_bku', v_real,
      'burn_rate_pct', case when burn is null then null else round(burn, 2) end, 'time_elapsed_pct', te,
      'bku_spike_14d_pct', case when spike is null then null else round(spike, 2) end, 'zona', zona, 'label', lbl,
      'deviasi', 'Burn-Rate ' || burnteks || ' vs Time Elapsed ' || to_char(te, 'FM990.0') || '%' || dev || case when spike is not null then ' • BKU 14 hari ' || to_char(spike, 'FM990.0') || '% dari pagu' else '' end,
      'is_frozen', beku));
    tt := tt + 1;
    if zona = 'HIJAU' then hijau := hijau + 1; elsif zona = 'MERAH' then merah := merah + 1; kuning := kuning + 1;
    elsif zona = 'KUNING' then kuning := kuning + 1; else oranye := oranye + 1; end if;
  end loop;
  -- Kritis diangkat ke baris teratas; urutan lain dipertahankan
  hasil := coalesce((select jsonb_agg(x order by (case when x->>'zona' = 'MERAH' then 0 else 1 end), o) from jsonb_array_elements(hasil) with ordinality t2(x, o)), '[]');
  return jsonb_build_object('ok', true, 'data', jsonb_build_object('ta_label', 'TA ' || t.tahun, 'time_elapsed_pct', te, 'is_frozen', beku, 'tanggal_acuan', acuan::text,
    'ringkasan', jsonb_build_object('normal', hijau, 'perhatian', kuning, 'lonjakan', oranye, 'total', tt), 'seksi', hasil));
end $$;

create or replace function public.heatmap_bulanan(p_ta text) returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
declare t tahun_anggaran; s record; p record; baris jsonb := '[]'; ok boolean := true; bulan numeric[]; luar bigint; tot bigint; pagu bigint; sub_total bigint; sub_sum bigint; i int; pb jsonb; bj jsonb; x record;
        b_sub jsonb; b_seksi jsonb;
begin
  if amanda.peran() is distinct from 'pa_kpa' then return amanda.gagal('Analitik hanya dapat diakses PA/KPA.'); end if;
  if amanda.ta() is distinct from p_ta then return amanda.gagal('TA tidak sesuai dengan sesi aktif.'); end if;
  select * into t from tahun_anggaran where id = p_ta;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  for s in select * from seksi_ta where ta_id = p_ta order by nama_snapshot, id loop
    sub_sum := 0; b_sub := '[]';
    for p in select * from pemetaan_subkegiatan_ta where ta_id = p_ta and seksi_ta_id = s.id order by kode_snapshot loop
      bulan := array_fill(0::numeric, array[12]); luar := 0; tot := 0;
      for x in select r.tanggal_bku, r.bruto from amanda.baris_realisasi(p_ta, array[s.id]) r where r.pemetaan_id = p.id loop
        tot := tot + x.bruto;
        if to_char(x.tanggal_bku, 'YYYY') = t.tahun then bulan[extract(month from x.tanggal_bku)::int] := bulan[extract(month from x.tanggal_bku)::int] + x.bruto; else luar := luar + x.bruto; end if;
      end loop;
      pagu := amanda.pagu_sub(p.id);
      pb := '[]'; for i in 1..12 loop pb := pb || jsonb_build_array(amanda.persen1(bulan[i], pagu)); end loop;
      if (select sum(v) from unnest(bulan) v) + luar <> tot then ok := false; end if;
      sub_sum := sub_sum + tot;
      b_sub := b_sub || jsonb_build_array(jsonb_build_object('tingkat', 'subkegiatan', 'id', p.id, 'nama', p.nama_snapshot, 'kode', p.kode_snapshot, 'bulan', to_jsonb(bulan), 'luar_tahun', luar, 'total', tot, 'pagu', pagu, 'persen_bulan', pb));
    end loop;
    bulan := array_fill(0::numeric, array[12]); luar := 0; tot := 0;
    for x in select r.tanggal_bku, r.bruto from amanda.baris_realisasi(p_ta, array[s.id]) r loop
      tot := tot + x.bruto;
      if to_char(x.tanggal_bku, 'YYYY') = t.tahun then bulan[extract(month from x.tanggal_bku)::int] := bulan[extract(month from x.tanggal_bku)::int] + x.bruto; else luar := luar + x.bruto; end if;
    end loop;
    pagu := amanda.pagu_seksi(p_ta, s.id);
    pb := '[]'; for i in 1..12 loop pb := pb || jsonb_build_array(amanda.persen1(bulan[i], pagu)); end loop;
    if sub_sum <> tot then ok := false; end if;
    baris := baris || jsonb_build_array(jsonb_build_object('tingkat', 'seksi', 'id', s.id, 'nama', s.nama_snapshot, 'bulan', to_jsonb(bulan), 'luar_tahun', luar, 'total', tot, 'pagu', pagu, 'persen_bulan', pb)) || b_sub;
  end loop;
  return jsonb_build_object('ok', true, 'data', jsonb_build_object('ta_label', 'TA ' || t.tahun, 'baris', baris, 'rekonsiliasi_ok', ok, 'snapshot', t.status in ('Masa Transisi','Arsip Read-Only')));
end $$;

-- ============ PORTAL PUBLIK (PUB-01..06) — anonim, hanya agregat ============
-- Tidak ada nominal rupiah, baris transaksi, penerima, NIP/NIK, rekening, akun, maupun audit (D01 §10; D04 §2.3).
create or replace function public.publik_daftar_ta() returns jsonb
language sql stable security definer set search_path = public, amanda as $$
  with tersedia as (select * from tahun_anggaran where status in ('Aktif Penuh','Masa Transisi','Arsip Read-Only')),
       bawaan as (select id from tersedia order by (status = 'Aktif Penuh') desc, tahun desc limit 1)
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'label', 'TA ' || t.tahun, 'status', t.status, 'bawaan', t.id = (select id from bawaan)) order by t.tahun desc), '[]') from tersedia t $$;

create or replace function public.publik_ringkasan(p_ta text) returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
declare t tahun_anggaran; total bigint; jml int; hit int[]; k jsonb := '[]'; sk jsonb; kode text[] := array['selesai','verifikasi','perbaikan','draf'];
        lab text[] := array['Selesai / Dibukukan BKU','Dalam Verifikasi','Perlu Perbaikan','Draf / Persiapan PPTK']; i int; r record;
begin
  select * into t from tahun_anggaran where id = p_ta and status in ('Aktif Penuh','Masa Transisi','Arsip Read-Only');
  if not found then return jsonb_build_object('ok', false); end if;
  select coalesce(sum(x.bruto), 0) into total from amanda.baris_realisasi(p_ta, (select coalesce(array_agg(id), '{}') from seksi_ta where ta_id = p_ta)) x;
  select count(*) into jml from spj where ta_id = p_ta;
  hit := array[
    (select count(*) from spj where ta_id = p_ta and status = 'Dibukukan'),
    (select count(*) from spj where ta_id = p_ta and status in ('Terkunci','Menunggu BKU')),
    (select count(*) from spj where ta_id = p_ta and status = 'Draft' and dikembalikan),
    (select count(*) from spj where ta_id = p_ta and status = 'Draft' and not dikembalikan)];
  for i in 1..4 loop k := k || jsonb_build_array(jsonb_build_object('kode', kode[i], 'label', lab[i], 'cacah', hit[i], 'persen', amanda.persen1(hit[i], jml))); end loop;
  select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'nama', z.nama, 'persen', z.persen, 'peringkat', z.rn) order by z.rn), '[]') into sk from (
    select q.id, q.nama, q.persen, row_number() over (order by q.persen desc nulls last, q.nama) rn from (
      select s.id, s.nama_snapshot as nama, amanda.persen1((select coalesce(sum(x.bruto), 0) from amanda.baris_realisasi(p_ta, array[s.id]) x), amanda.pagu_seksi(p_ta, s.id)) as persen
      from seksi_ta s where s.ta_id = p_ta) q) z;
  return jsonb_build_object('ok', true, 'ta_id', p_ta, 'ta_label', 'TA ' || t.tahun, 'persen_realisasi', amanda.persen1(total, amanda.pagu_induk_aktif(p_ta)),
    'total_spj', jml, 'kategori', k, 'seksi', sk, 'diperbarui', to_char(now() at time zone 'Asia/Makassar', 'YYYY-MM-DD HH24:MI'));
end $$;

-- ============ RETENSI TA 12 TAHUN (TA-07) ============
create or replace function amanda.retensi_lewat(p_ta text) returns boolean language sql stable security definer set search_path = public, amanda as $$
  select coalesce((select status = 'Arsip Read-Only' and tanggal_arsip_terakhir is not null and amanda.hari_ini_wita() >= (tanggal_arsip_terakhir + interval '12 years')::date
                   from tahun_anggaran where id = p_ta), false) $$;

create or replace function public.adm_ta_ringkasan_hapus(p_ta text) returns jsonb
language plpgsql stable security definer set search_path = public, amanda as $$
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat melihat ringkasan penghapusan.'); end if;
  return jsonb_build_object('ok', true, 'kuitansi', (select count(*) from kuitansi where ta_id = p_ta), 'spj', (select count(*) from spj where ta_id = p_ta),
    'bku', (select count(*) from bku where ta_id = p_ta), 'lampiran', (select count(*) from spj where ta_id = p_ta and lampiran_key is not null),
    'retensi_lewat', amanda.retensi_lewat(p_ta));
end $$;

-- Hapus total TA Arsip yang melewati retensi 12 tahun. Tanpa catatan penghapusan (D01 §1.3 poin 6).
-- Mengembalikan daftar kunci lampiran agar berkasnya dihapus dari Storage.
create or replace function public.adm_ta_hapus_retensi(p_ta text, p_kode text) returns jsonb
language plpgsql volatile security definer set search_path = public, amanda as $$
declare t tahun_anggaran; keys jsonb;
begin
  if amanda.bukan_admin() then return amanda.gagal('Hanya Admin yang dapat menghapus TA.'); end if;
  select * into t from tahun_anggaran where id = p_ta for update;
  if not found then return amanda.gagal('TA tidak ditemukan.'); end if;
  if t.status <> 'Arsip Read-Only' then return amanda.gagal('Hanya TA Arsip Read-Only yang dapat dihapus.'); end if;
  if not amanda.retensi_lewat(p_ta) then return amanda.gagal('Retensi 12 tahun belum terlewati.'); end if;
  if p_kode is distinct from t.tahun then return amanda.gagal('Kode TA yang diketik tidak sama persis.'); end if;
  select coalesce(jsonb_agg(lampiran_key), '[]') into keys from spj where ta_id = p_ta and lampiran_key is not null;
  perform set_config('amanda.retensi', '1', true);
  delete from direktori_transaksional_ref where spj_id in (select id from spj where ta_id = p_ta);
  delete from sesi_amanda where ta_id = p_ta;
  delete from tahun_anggaran where id = p_ta;     -- cascade: seluruh data TA, termasuk jejak audit terkait
  perform set_config('amanda.retensi', '0', true);
  return jsonb_build_object('ok', true, 'lampiran', keys);
end $$;

-- ============ IZIN EKSEKUSI ============
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('laporan_buat','laporan_kolom_kustom','laporan_kustom','drill_seksi','drill_subkegiatan','drill_rekening',
             'analitik_seksi','heatmap_bulanan','publik_daftar_ta','publik_ringkasan','adm_ta_ringkasan_hapus','adm_ta_hapus_retensi')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname in ('publik_daftar_ta','publik_ringkasan') then execute format('grant execute on function %s to anon, authenticated', f.sig);
    else execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $$;
grant execute on all functions in schema amanda to authenticated;
