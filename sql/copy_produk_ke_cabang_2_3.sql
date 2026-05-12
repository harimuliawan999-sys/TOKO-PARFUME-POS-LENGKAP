-- ═══════════════════════════════════════════════════════════════
-- COPY PRODUK & VARIAN DARI CABANG 1 KE CABANG 2 DAN 3
-- Jalankan SETELAH tambah_2_cabang.sql
-- Dan SETELAH import_1 sampai import_6 sudah selesai di cabang 1
-- ═══════════════════════════════════════════════════════════════

-- ═══ COPY PRODUK KE CABANG 2 ═══
INSERT INTO produk (toko_id, nama, kategori, kelas, harga_beli, stok, min_stok, satuan)
SELECT 
  (SELECT id FROM toko WHERE nama = 'KS Parfume Cabang 2' LIMIT 1),
  nama, kategori, kelas, harga_beli, 100, min_stok, satuan
FROM produk 
WHERE toko_id = (SELECT id FROM toko ORDER BY created_at LIMIT 1);

-- ═══ COPY VARIAN KE CABANG 2 ═══
INSERT INTO varian (produk_id, nama, ukuran, kualitas, harga_jual, resep_bibit, resep_botol_id)
SELECT 
  p2.id,
  v1.nama, v1.ukuran, v1.kualitas, v1.harga_jual, v1.resep_bibit,
  (SELECT p2b.id FROM produk p2b WHERE p2b.toko_id = (SELECT id FROM toko WHERE nama = 'KS Parfume Cabang 2' LIMIT 1) AND LOWER(p2b.nama) = LOWER(botol.nama) LIMIT 1)
FROM varian v1
JOIN produk p1 ON v1.produk_id = p1.id AND p1.toko_id = (SELECT id FROM toko ORDER BY created_at LIMIT 1)
JOIN produk p2 ON LOWER(p2.nama) = LOWER(p1.nama) AND p2.toko_id = (SELECT id FROM toko WHERE nama = 'KS Parfume Cabang 2' LIMIT 1)
LEFT JOIN produk botol ON v1.resep_botol_id = botol.id;

-- ═══ COPY PRODUK KE CABANG 3 ═══
INSERT INTO produk (toko_id, nama, kategori, kelas, harga_beli, stok, min_stok, satuan)
SELECT 
  (SELECT id FROM toko WHERE nama = 'KS Parfume Cabang 3' LIMIT 1),
  nama, kategori, kelas, harga_beli, 100, min_stok, satuan
FROM produk 
WHERE toko_id = (SELECT id FROM toko ORDER BY created_at LIMIT 1);

-- ═══ COPY VARIAN KE CABANG 3 ═══
INSERT INTO varian (produk_id, nama, ukuran, kualitas, harga_jual, resep_bibit, resep_botol_id)
SELECT 
  p2.id,
  v1.nama, v1.ukuran, v1.kualitas, v1.harga_jual, v1.resep_bibit,
  (SELECT p2b.id FROM produk p2b WHERE p2b.toko_id = (SELECT id FROM toko WHERE nama = 'KS Parfume Cabang 3' LIMIT 1) AND LOWER(p2b.nama) = LOWER(botol.nama) LIMIT 1)
FROM varian v1
JOIN produk p1 ON v1.produk_id = p1.id AND p1.toko_id = (SELECT id FROM toko ORDER BY created_at LIMIT 1)
JOIN produk p2 ON LOWER(p2.nama) = LOWER(p1.nama) AND p2.toko_id = (SELECT id FROM toko WHERE nama = 'KS Parfume Cabang 3' LIMIT 1)
LEFT JOIN produk botol ON v1.resep_botol_id = botol.id;

-- ═══════════════════════════════════════════════════════════════
-- SELESAI! Sekarang 3 cabang punya produk & varian yang sama
-- Stok masing-masing cabang terpisah (mulai dari 100)
-- ═══════════════════════════════════════════════════════════════
