-- Hapus constraint yang ditambahkan sebelumnya (kalau ada)
-- Jalankan di Supabase SQL Editor
ALTER TABLE stok_movement DROP CONSTRAINT IF EXISTS stok_movement_type_check;
