-- ═══════════════════════════════════════════════════════════════
-- KS PARFUME v3.7.1 — PATCH: Pastikan kolom hp & alamat ada di pelanggan
-- ═══════════════════════════════════════════════════════════════
-- Ini fix bug: "tambah pelanggan baru tidak bisa simpan"
-- Penyebab: tabel pelanggan lama mungkin belum punya kolom 'hp' / 'alamat'
-- Solusi: ADD COLUMN IF NOT EXISTS (idempotent, aman)
--
-- AMAN: cuma menambah kolom baru, tidak ubah/hapus data
-- ═══════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE pelanggan
  ADD COLUMN IF NOT EXISTS hp TEXT,
  ADD COLUMN IF NOT EXISTS alamat TEXT,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

COMMIT;

-- Verifikasi: harus muncul kolom hp, alamat, created_at
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name='pelanggan' AND column_name IN ('hp', 'alamat', 'created_at')
ORDER BY column_name;
