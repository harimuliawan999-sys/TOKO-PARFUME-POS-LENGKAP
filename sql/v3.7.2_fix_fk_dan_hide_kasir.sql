-- ═══════════════════════════════════════════════════════════════
-- KS PARFUME v3.7.2 — FIX FK + HIDE KASIR + CLEANUP
-- ═══════════════════════════════════════════════════════════════
-- 3 hal sekaligus:
--  1. Fix FK transaksi.pelanggan_id → ON DELETE SET NULL
--     (supaya hapus pelanggan dari APK tidak error meski ada transaksi lama)
--  2. Tambah kolom pengeluaran.hide_kasir untuk fitur sembunyikan dari kasir
--  3. Hapus pelanggan "adre" yang tersisa dari versi lama
--
-- AMAN: dibungkus BEGIN/COMMIT (atomik), pakai IF NOT EXISTS,
-- tidak ada DELETE data transaksi/produk/stok.
-- ═══════════════════════════════════════════════════════════════

-- ═══ VERIFIKASI SEBELUM ═══
SELECT
  'transaksi'      AS tabel, COUNT(*) AS jumlah_sebelum FROM transaksi
UNION ALL SELECT 'pelanggan',     COUNT(*) FROM pelanggan
UNION ALL SELECT 'pengeluaran',   COUNT(*) FROM pengeluaran
UNION ALL SELECT 'transaksi_item', COUNT(*) FROM transaksi_item;

BEGIN;

-- ─── 1. FIX FK transaksi.pelanggan_id ────────────────────────────────
-- Drop FK lama (apapun bentuknya), pasang ulang dengan ON DELETE SET NULL.
-- Aman: cuma ganti aturan, tidak hapus data.
ALTER TABLE transaksi DROP CONSTRAINT IF EXISTS transaksi_pelanggan_id_fkey;

ALTER TABLE transaksi
  ADD CONSTRAINT transaksi_pelanggan_id_fkey
  FOREIGN KEY (pelanggan_id)
  REFERENCES pelanggan(id)
  ON DELETE SET NULL;

-- ─── 2. TAMBAH KOLOM hide_kasir DI PENGELUARAN ───────────────────────
-- Default FALSE = visible ke kasir. Owner bisa toggle TRUE per item.
ALTER TABLE pengeluaran
  ADD COLUMN IF NOT EXISTS hide_kasir BOOLEAN DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_pengeluaran_hide_kasir
  ON pengeluaran(toko_id, hide_kasir);

-- ─── 3. CLEANUP PELANGGAN "adre" ────────────────────────────────────
-- Lepas link transaksi dulu (otomatis via ON DELETE SET NULL setelah step 1,
-- tapi kita lakukan eksplisit di sini untuk amannya).
UPDATE transaksi
  SET pelanggan_id = NULL
  WHERE pelanggan_id IN (
    SELECT id FROM pelanggan WHERE LOWER(TRIM(nama)) = 'adre'
  );

-- Hapus pelanggan "adre" (case-insensitive, trim spasi)
DELETE FROM pelanggan WHERE LOWER(TRIM(nama)) = 'adre';

COMMIT;

-- ═══ VERIFIKASI SESUDAH ═══
-- Angka transaksi/transaksi_item/pengeluaran HARUS SAMA dengan sebelum.
-- Pelanggan kurang 1 (adre terhapus).
SELECT
  'transaksi'      AS tabel, COUNT(*) AS jumlah_sesudah FROM transaksi
UNION ALL SELECT 'pelanggan',     COUNT(*) FROM pelanggan
UNION ALL SELECT 'pengeluaran',   COUNT(*) FROM pengeluaran
UNION ALL SELECT 'transaksi_item', COUNT(*) FROM transaksi_item;

-- Cek FK aturan baru sudah benar (harus muncul "SET NULL")
SELECT conname, confdeltype
FROM pg_constraint
WHERE conname = 'transaksi_pelanggan_id_fkey';
-- confdeltype 'n' = SET NULL, 'a' = NO ACTION (jelek), 'r' = RESTRICT

-- Cek kolom hide_kasir sudah ada
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name='pengeluaran' AND column_name='hide_kasir';

-- Cek adre sudah hilang (harus 0 baris)
SELECT * FROM pelanggan WHERE LOWER(TRIM(nama)) = 'adre';
