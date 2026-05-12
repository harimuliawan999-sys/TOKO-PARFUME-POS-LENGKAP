-- ═══════════════════════════════════════════════════════════════
-- Fix stok bibit & botol untuk transaksi BBT26042628943
-- TIDAK perlu tahu berapa kali retry gagal —
-- kita pakai stok_movement history untuk hitung nilai yang benar.
-- ═══════════════════════════════════════════════════════════════

-- ══ STEP 1: CEK — stok sekarang vs seharusnya ══
-- Jalankan ini dulu, lihat hasilnya sebelum fix.
SELECT
  pb.nama                         AS nama_bibit,
  pb.stok                         AS stok_SEKARANG,
  sm.stok_sebelum + ti.qty        AS stok_SEHARUSNYA,
  pb.stok - (sm.stok_sebelum + ti.qty) AS KELEBIHAN,
  pbotol.nama                     AS nama_botol,
  pbotol.stok                     AS stok_botol_SEKARANG,
  sm2.stok_sebelum + ti.qty       AS stok_botol_SEHARUSNYA,
  pbotol.stok - (sm2.stok_sebelum + ti.qty) AS KELEBIHAN_botol
FROM transaksi t
JOIN transaksi_item ti  ON ti.transaksi_id = t.id
JOIN produk pb          ON pb.id = ti.produk_id
LEFT JOIN produk pbotol ON pbotol.id = ti.botol_id
LEFT JOIN stok_movement sm
  ON sm.produk_id = ti.produk_id
  AND sm.tipe = 'penjualan'
  AND sm.created_at BETWEEN t.created_at - INTERVAL '10 minutes'
                        AND t.created_at + INTERVAL '10 minutes'
LEFT JOIN stok_movement sm2
  ON sm2.produk_id = ti.botol_id
  AND sm2.tipe = 'penjualan'
  AND sm2.created_at BETWEEN t.created_at - INTERVAL '10 minutes'
                         AND t.created_at + INTERVAL '10 minutes'
WHERE t.no_nota = 'BBT26042628943';

-- ══ STEP 2: FIX stok BIBIT ke nilai yang benar ══
UPDATE produk pb
SET stok = sm.stok_sebelum + ti.qty
FROM transaksi t
JOIN transaksi_item ti ON ti.transaksi_id = t.id
JOIN stok_movement sm
  ON sm.produk_id = ti.produk_id
  AND sm.tipe = 'penjualan'
  AND sm.created_at BETWEEN t.created_at - INTERVAL '10 minutes'
                        AND t.created_at + INTERVAL '10 minutes'
WHERE t.no_nota = 'BBT26042628943'
  AND pb.id = ti.produk_id;

-- ══ STEP 3: FIX stok BOTOL ke nilai yang benar (kalau ada) ══
UPDATE produk pb
SET stok = sm.stok_sebelum + ti.qty
FROM transaksi t
JOIN transaksi_item ti ON ti.transaksi_id = t.id
JOIN stok_movement sm
  ON sm.produk_id = ti.botol_id
  AND sm.tipe = 'penjualan'
  AND sm.created_at BETWEEN t.created_at - INTERVAL '10 minutes'
                        AND t.created_at + INTERVAL '10 minutes'
WHERE t.no_nota = 'BBT26042628943'
  AND ti.botol_id IS NOT NULL
  AND pb.id = ti.botol_id;

-- ══ STEP 4: VERIFIKASI — stok sesudah fix ══
SELECT pb.nama, pb.stok AS stok_sesudah_fix
FROM transaksi t
JOIN transaksi_item ti ON ti.transaksi_id = t.id
JOIN produk pb ON pb.id = ti.produk_id
WHERE t.no_nota = 'BBT26042628943';
