-- AMANDA — Storage: bucket `lampiran-spj` (PDF ≤ 30 MB) dan `sk` (PDF/JPG/PNG ≤ 5 MB), dengan kebijakan akses per peran.
-- Dilewati otomatis bila skema `storage` tidak ada (mis. pada uji lokal). Nama objek lampiran: `<spj_id>/<nama-berkas>`;
-- nama objek SK: `<penugasan_id>/<nama-berkas>`. Basis data hanya menyimpan kunci dan metadata; berkas diunggah klien.

create or replace function amanda.lampiran_boleh_tulis(p_spj text) returns boolean language sql stable security definer set search_path = public, amanda as $$
  -- PPTK seksi pemilik, SPJ masih Draft, TA Aktif Penuh
  select exists (select 1 from spj s join kuitansi k on k.id = s.kuitansi_id
    where s.id = p_spj and s.status = 'Draft' and amanda.peran() = 'pptk' and amanda.ta() = s.ta_id and amanda.seksi() = k.seksi_ta_id and amanda.ta_boleh(s.ta_id, 'buat')) $$;

create or replace function amanda.lampiran_boleh_baca(p_spj text) returns boolean language sql stable security definer set search_path = public, amanda as $$
  -- Bendahara, Verifikator, PA/KPA seluruh seksi; PPTK seksinya. Admin, Pengawas, dan Publik ditolak (SPJ-08).
  select exists (select 1 from spj s join kuitansi k on k.id = s.kuitansi_id
    where s.id = p_spj and amanda.ta() = s.ta_id
      and (amanda.peran() in ('bendahara','verifikator','pa_kpa') or (amanda.peran() = 'pptk' and amanda.seksi() = k.seksi_ta_id))) $$;

-- Hapus objek yatim (SPJ sudah dilepas/dihapus retensi): PPTK atau Admin boleh membersihkannya.
create or replace function amanda.objek_yatim(p_folder text) returns boolean language sql stable security definer set search_path = public, amanda as $$
  select amanda.peran() in ('pptk','admin') and not exists (select 1 from spj where id = p_folder) $$;

create or replace function amanda.sk_boleh_tulis() returns boolean language sql stable as $$ select amanda.peran() = 'admin' $$;

do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'Skema storage tidak ada; migrasi 0010 dilewati.'; return;
  end if;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('lampiran-spj', 'lampiran-spj', false, 30 * 1048576, array['application/pdf'])
    on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('sk', 'sk', false, 5 * 1048576, array['application/pdf','image/jpeg','image/png'])
    on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

  drop policy if exists amanda_lampiran_baca on storage.objects;
  drop policy if exists amanda_lampiran_tulis on storage.objects;
  drop policy if exists amanda_lampiran_ubah on storage.objects;
  drop policy if exists amanda_lampiran_hapus on storage.objects;
  drop policy if exists amanda_sk_baca on storage.objects;
  drop policy if exists amanda_sk_tulis on storage.objects;
  drop policy if exists amanda_sk_ubah on storage.objects;
  drop policy if exists amanda_sk_hapus on storage.objects;

  create policy amanda_lampiran_baca on storage.objects for select to authenticated
    using (bucket_id = 'lampiran-spj' and amanda.lampiran_boleh_baca((storage.foldername(name))[1]));
  create policy amanda_lampiran_tulis on storage.objects for insert to authenticated
    with check (bucket_id = 'lampiran-spj' and amanda.lampiran_boleh_tulis((storage.foldername(name))[1]));
  create policy amanda_lampiran_ubah on storage.objects for update to authenticated
    using (bucket_id = 'lampiran-spj' and amanda.lampiran_boleh_tulis((storage.foldername(name))[1]))
    with check (bucket_id = 'lampiran-spj' and amanda.lampiran_boleh_tulis((storage.foldername(name))[1]));
  create policy amanda_lampiran_hapus on storage.objects for delete to authenticated
    using (bucket_id = 'lampiran-spj' and (amanda.lampiran_boleh_tulis((storage.foldername(name))[1]) or amanda.objek_yatim((storage.foldername(name))[1])));

  -- SK: hanya Admin menulis; pembacaan oleh Admin (Pengelolaan Penugasan)
  create policy amanda_sk_baca on storage.objects for select to authenticated using (bucket_id = 'sk' and amanda.peran() = 'admin');
  create policy amanda_sk_tulis on storage.objects for insert to authenticated with check (bucket_id = 'sk' and amanda.sk_boleh_tulis());
  create policy amanda_sk_ubah on storage.objects for update to authenticated using (bucket_id = 'sk' and amanda.sk_boleh_tulis()) with check (bucket_id = 'sk' and amanda.sk_boleh_tulis());
  create policy amanda_sk_hapus on storage.objects for delete to authenticated using (bucket_id = 'sk' and amanda.sk_boleh_tulis());
end $$;
grant execute on all functions in schema amanda to authenticated;
