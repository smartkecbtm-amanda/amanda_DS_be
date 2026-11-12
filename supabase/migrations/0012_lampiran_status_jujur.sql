-- Status optimasi lampiran dibuat jujur: berkas > 5 MB tanpa kompresi sungguhan dicatat FAILED (disimpan utuh),
-- bukan SERVER_FALLBACK_COMPRESSED. Nilai CLIENT_COMPRESSED / SERVER_FALLBACK_COMPRESSED hanya diterima bila
-- pemanggil (klien atau layanan kompresi) benar-benar mengompres dan melaporkan ukuran final yang lebih kecil.
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
  elsif st in ('CLIENT_COMPRESSED','SERVER_FALLBACK_COMPRESSED') and fin is not null and fin > 0 and fin < p_ukuran_asal then null;
  else st := 'FAILED'; fin := p_ukuran_asal;   -- tidak dikompres: disimpan utuh
  end if;
  update spj set lampiran_key = p_key, lampiran_nama_asli = p_nama, lampiran_ukuran_asal = p_ukuran_asal, lampiran_ukuran_final = fin, lampiran_status_optimasi = st where id = p_spj;
  perform amanda.sentuh();
  return jsonb_build_object('ok', true, 'status_optimasi', st);
end $$;
revoke all on function public.pptk_spj_lampiran(text,text,text,bigint,bigint,text) from public, anon;
grant execute on function public.pptk_spj_lampiran(text,text,text,bigint,bigint,text) to authenticated;
