#!/usr/bin/env bash
# Uji basis data di Postgres LOKAL (bukan di Supabase). Butuh psql dan server Postgres 15+ yang sedang berjalan.
# Pemakaian: PGHOST=/var/tmp PGPORT=5444 PGUSER=postgres ./jalankan.sh [berkas_uji...]
# Setiap berkas uji berjalan pada salinan segar basis data (migrasi + seed) sehingga tidak saling mengubah data.
set -euo pipefail
cd "$(dirname "$0")/.."
BASE=amd_dasar
psql -q -c "drop database if exists $BASE" -c "create database $BASE" 2>&1 | grep -v NOTICE || true
psql -d $BASE -q -v ON_ERROR_STOP=1 -f tests/00_tiruan_supabase.sql
for f in migrations/*.sql seed.sql; do echo ">> $f"; psql -d $BASE -q -v ON_ERROR_STOP=1 -f "$f"; done
TESTS=("$@"); [ ${#TESTS[@]} -eq 0 ] && TESTS=(tests/t*.sql)
GAGAL=0
for t in "${TESTS[@]}"; do
  echo ">> $t"
  psql -q -c "drop database if exists amd_uji" -c "create database amd_uji template $BASE" >/dev/null 2>&1
  KELUARAN=$(psql -d amd_uji -q -f "$t" 2>&1 || true)
  echo "$KELUARAN" | grep -E "NOTICE|ERROR|^ " || true
  # Uji dinyatakan bersih hanya bila tidak ada baris GAGAL dan tidak ada ERROR SQL apa pun.
  if echo "$KELUARAN" | grep -qE "GAGAL|ERROR|FATAL"; then echo "!! $t TIDAK BERSIH"; GAGAL=1; fi
  echo "   lulus: $(echo "$KELUARAN" | grep -c 'lulus')"
done
[ $GAGAL -eq 0 ] && echo "SEMUA UJI BERSIH" || { echo "ADA UJI GAGAL"; exit 1; }
