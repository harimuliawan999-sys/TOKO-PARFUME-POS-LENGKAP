-- ═══════════════════════════════════════════════════════════════
-- KS PARFUME — Fix Pembatalan Transaksi
-- WAJIB jalankan 1x di Supabase SQL Editor sebelum pakai fitur batalkan transaksi
-- ═══════════════════════════════════════════════════════════════

-- 1. Tambah kolom 'status' di tabel transaksi (kalau belum ada)
ALTER TABLE transaksi ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'selesai';

-- 2. Perluas constraint tipe di stok_movement agar izinkan 'batal'
--    (sebelumnya hanya: masuk, keluar, penjualan)
ALTER TABLE stok_movement DROP CONSTRAINT IF EXISTS stok_movement_type_check;
ALTER TABLE stok_movement ADD CONSTRAINT stok_movement_type_check
  CHECK (tipe IN ('masuk', 'keluar', 'penjualan', 'batal'));

-- ═══════════════════════════════════════════════════════════════
-- SELESAI! Sekarang fitur batalkan transaksi bisa berjalan.
-- ═══════════════════════════════════════════════════════════════
