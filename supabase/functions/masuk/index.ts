// Edge Function `masuk` — pintu login AMANDA (Dokumen 04 §3). BELUM DIUJI pada proyek Supabase nyata
// (logika basis data di migrasi 0002 sudah diuji lokal). Deploy: supabase functions deploy masuk --no-verify-jwt
//
// Langkah 1  POST { aksi: 'verifikasi', identitas, sandi }  -> { ok, tiket, nama, konteks[] }  (kunci 10x gagal di DB)
// Langkah 2  POST { aksi: 'buka', tiket, ta_id, peran, seksi_ta_id } -> { ok, sesi: {access_token, refresh_token, expires_in}, payload }
//
// Kata sandi sebenarnya hanya ada sebagai hash bcrypt di tabel akun_*. Akun Supabase Auth diberi kata sandi acak
// sekali pakai oleh fungsi ini, sehingga login langsung ke GoTrue dengan kata sandi asli tidak mungkin
// (tidak ada jalan memutar yang menghindari penghitung kegagalan di basis data).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const admin = createClient(URL, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } });

// Batasi asal permintaan: set ALLOWED_ORIGIN (mis. https://amanda.example.go.id) di pengaturan Edge Function. Bila kosong, '*' (hanya untuk uji).
const ORIGIN = Deno.env.get('ALLOWED_ORIGIN') ?? '*';
const CORS = {
  'Access-Control-Allow-Origin': ORIGIN,
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

function acak(): string {
  const b = new Uint8Array(32); crypto.getRandomValues(b);
  return Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
}
function klaimSesi(jwt: string): string | null {
  try { return JSON.parse(atob(jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).session_id ?? null; } catch { return null; }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ ok: false, error: 'Metode tidak didukung.' }, 405);
  let body: Record<string, string>;
  try { body = await req.json(); } catch { return json({ ok: false, error: 'Permintaan tidak valid.' }, 400); }

  // Pembatasan laju: per IP dan per pasangan IP+identitas. Penolakan memakai pesan seragam.
  const ip = (req.headers.get('x-forwarded-for') ?? req.headers.get('cf-connecting-ip') ?? 'tak-dikenal').split(',')[0].trim();
  const cekLaju = async (kunci: string, batas: number, menit: number): Promise<boolean> => {
    const { data, error } = await admin.rpc('cek_laju_masuk', { p_kunci: kunci, p_batas: batas, p_menit: menit });
    return !error && data === true;   // gagal memeriksa = tolak (aman)
  };
  const hash = async (t: string) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(t.trim().toLowerCase()))), (x) => x.toString(16).padStart(2, '0')).join('');
  const TERLALU_SERING = { ok: false, error: 'Terlalu banyak percobaan. Coba lagi beberapa menit lagi.' };

  if (body.aksi === 'verifikasi') {
    const idh = await hash(body.identitas ?? '');
    if (!(await cekLaju(`ip:${ip}`, 40, 15)) || !(await cekLaju(`ipid:${ip}:${idh}`, 6, 15))) return json(TERLALU_SERING, 429);
    const { data, error } = await admin.rpc('verifikasi_login', { p_identitas: body.identitas ?? '', p_sandi: body.sandi ?? '' });
    if (error) return json({ ok: false, error: 'Layanan tidak tersedia. Coba lagi.' }, 500);
    const { auth_user_id: _a, akun_id: _b, ...aman } = data as Record<string, unknown>;
    return json(aman);
  }

  if (body.aksi === 'buka') {
    if (!(await cekLaju(`buka:${ip}`, 60, 15))) return json(TERLALU_SERING, 429);
    const info = (await admin.rpc('tiket_info', { p_tiket: body.tiket ?? '' })).data as
      | { ok: boolean; tipe: string; akun_id: string; auth_user_id: string | null; email: string } | null;
    if (!info?.ok) return json({ ok: false, error: 'Tiket masuk tidak berlaku. Silakan masuk kembali.' }, 401);

    // Pastikan akun Supabase Auth ada, lalu beri kata sandi acak sekali pakai.
    const sandiAcak = acak();
    let uid = info.auth_user_id;
    if (!uid) {
      const { data, error } = await admin.auth.admin.createUser({ email: info.email, password: sandiAcak, email_confirm: true });
      if (error || !data.user) return json({ ok: false, error: 'Gagal menyiapkan sesi.' }, 500);
      uid = data.user.id;
      await admin.rpc('simpan_auth_user', { p_tipe: info.tipe, p_akun_id: info.akun_id, p_auth_user: uid });
    } else {
      const { error } = await admin.auth.admin.updateUserById(uid, { password: sandiAcak, email: info.email, email_confirm: true });
      if (error) return json({ ok: false, error: 'Gagal menyiapkan sesi.' }, 500);
    }

    const anon = createClient(URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: masuk, error: eMasuk } = await anon.auth.signInWithPassword({ email: info.email, password: sandiAcak });
    if (eMasuk || !masuk.session) return json({ ok: false, error: 'Gagal menyiapkan sesi.' }, 500);
    const sesiId = klaimSesi(masuk.session.access_token);
    if (!sesiId) return json({ ok: false, error: 'Gagal menyiapkan sesi.' }, 500);

    const { data: hasil, error: eBuka } = await admin.rpc('buka_sesi', {
      p_tiket: body.tiket, p_sesi_id: sesiId, p_ta: body.ta_id ?? null, p_peran: body.peran ?? '', p_seksi: body.seksi_ta_id ?? null,
    });
    if (eBuka || !(hasil as { ok: boolean }).ok) {
      await admin.auth.admin.signOut(masuk.session.access_token).catch(() => {});
      return json({ ok: false, error: (hasil as { error?: string })?.error ?? 'Konteks tidak sah.' }, 403);
    }
    return json({
      ok: true,
      sesi: { access_token: masuk.session.access_token, refresh_token: masuk.session.refresh_token, expires_in: masuk.session.expires_in },
      payload: hasil,
    });
  }

  return json({ ok: false, error: 'Aksi tidak dikenal.' }, 400);
});
