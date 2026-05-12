-- ═══════════════════════════════════════════════════════════════
-- BERSIHKAN CABANG DUPLIKAT — Sisakan hanya 3 cabang
-- Jalankan di Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- Hapus semua data terkait cabang duplikat (yang ke-4 dst)
DELETE FROM varian WHERE produk_id IN (
  SELECT id FROM produk WHERE toko_id IN (
    SELECT id FROM toko WHERE id NOT IN (SELECT id FROM toko ORDER BY created_at LIMIT 3)
  )
);

DELETE FROM stok_movement WHERE toko_id IN (
  SELECT id FROM toko WHERE id NOT IN (SELECT id FROM toko ORDER BY created_at LIMIT 3)
);

DELETE FROM transaksi_item WHERE transaksi_id IN (
  SELECT id FROM transaksi WHERE toko_id IN (
    SELECT id FROM toko WHERE id NOT IN (SELECT id FROM toko ORDER BY created_at LIMIT 3)
  )
);

DELETE FROM transaksi WHERE toko_id IN (
  SELECT id FROM toko WHERE id NOT IN (SELECT id FROM toko ORDER BY created_at LIMIT 3)
);

DELETE FROM pengeluaran WHERE toko_id IN (
  SELECT id FROM toko WHERE id NOT IN (SELECT id FROM toko ORDER BY created_at LIMIT 3)
);

DELETE FROM produk WHERE toko_id IN (
  SELECT id FROM toko WHERE id NOT IN (SELECT id FROM toko ORDER BY created_at LIMIT 3)
);

DELETE FROM users WHERE toko_id IN (
  SELECT id FROM toko WHERE id NOT IN (SELECT id FROM toko ORDER BY created_at LIMIT 3)
);

-- Hapus toko duplikat (sisakan 3 pertama)
DELETE FROM toko WHERE id NOT IN (SELECT id FROM toko ORDER BY created_at LIMIT 3);

-- Cek hasil: harus 3 cabang
SELECT nama, alamat, created_at FROM toko ORDER BY created_at;
