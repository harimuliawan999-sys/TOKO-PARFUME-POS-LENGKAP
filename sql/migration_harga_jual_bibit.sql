-- Tambah kolom harga jual bibit di tabel produk
-- Digunakan untuk bibit yang dijual langsung (bukan lewat varian parfum)
-- Contoh: BIBIT Tobacco Vanilla buy_price=1500, harga_jual_bibit=4000
ALTER TABLE produk ADD COLUMN IF NOT EXISTS harga_jual_bibit BIGINT DEFAULT 0;

-- Update existing bibit dengan harga_jual_bibit = 0 (perlu di-import ulang dari Olsera)
-- Setelah migrasi, jalankan Import Produk dari Import screen untuk mengisi nilainya
