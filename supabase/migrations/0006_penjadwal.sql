-- AMANDA — Penjadwal (PEN-06): menutup delegasi Plh./Plt. yang jatuh tempo setiap hari pukul 23:59 WITA (= 15:59 UTC).
-- Memerlukan ekstensi pg_cron (Supabase: Database → Extensions → pg_cron → Enable). Bila belum aktif, langkah ini dilewati
-- tanpa galat; hak akses delegasi tetap benar karena dinilai per tanggal pada saat login (daftar_konteks) dan pada sesi.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule(jobid) from cron.job where jobname = 'amanda-akhiri-delegasi';
    perform cron.schedule('amanda-akhiri-delegasi', '59 15 * * *', $job$select public.akhiri_delegasi_jatuh_tempo()$job$);
  else
    raise notice 'pg_cron tidak tersedia: jadwal pengakhiran delegasi dilewati. Aktifkan pg_cron lalu jalankan ulang berkas ini.';
  end if;
end $$;
