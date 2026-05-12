-- ═══════════════════════════════════════════════════════════════
-- TAMBAH 2 CABANG BARU + USERS MASING-MASING
-- Jalankan di Supabase SQL Editor (1x saja)
-- ═══════════════════════════════════════════════════════════════

-- ═══ CABANG 2 ═══
INSERT INTO toko (nama, alamat, telp) VALUES 
('KS Parfume Cabang 2', 'Medan, Sumatera Utara', '081234567891');

-- Users Cabang 2
INSERT INTO users (toko_id, nama, pin, peran) VALUES 
((SELECT id FROM toko WHERE nama = 'KS Parfume Cabang 2' LIMIT 1), 'Owner', '1234', 'owner'),
((SELECT id FROM toko WHERE nama = 'KS Parfume Cabang 2' LIMIT 1), 'Kasir 1', '0000', 'kasir');

-- ═══ CABANG 3 ═══
INSERT INTO toko (nama, alamat, telp) VALUES 
('KS Parfume Cabang 3', 'Medan, Sumatera Utara', '081234567892');

-- Users Cabang 3
INSERT INTO users (toko_id, nama, pin, peran) VALUES 
((SELECT id FROM toko WHERE nama = 'KS Parfume Cabang 3' LIMIT 1), 'Owner', '1234', 'owner'),
((SELECT id FROM toko WHERE nama = 'KS Parfume Cabang 3' LIMIT 1), 'Kasir 1', '0000', 'kasir');

-- ═══════════════════════════════════════════════════════════════
-- SELESAI! Sekarang ada 3 cabang.
-- Nama cabang bisa diedit dari app: Pengaturan → Edit Nama Cabang
-- Contoh: "KS Parfume Cabang 2" → "KS Parfume Sunggal"
--
-- Untuk import produk ke cabang baru, copy SQL import_1 sampai import_6
-- dan jalankan ulang (data produk per cabang terpisah)
-- ═══════════════════════════════════════════════════════════════
