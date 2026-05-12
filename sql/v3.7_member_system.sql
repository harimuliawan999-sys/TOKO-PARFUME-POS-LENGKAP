-- ═══════════════════════════════════════════════════════════════
-- KS PARFUME v3.7 — MEMBER SYSTEM + LOYALTY DISKON
-- ═══════════════════════════════════════════════════════════════
-- AMAN UNTUK DATA EXISTING (sudah jalan ~2 minggu):
--   ✅ Tidak ada DELETE data
--   ✅ Tidak ada DROP TABLE / DROP COLUMN
--   ✅ Cuma ADD COLUMN (kolom baru, default 0/NULL — tidak ganggu kolom lama)
--   ✅ DROP FUNCTION + CREATE FUNCTION dibungkus transaction (atomik)
--   ✅ Semua ALTER pakai IF NOT EXISTS (idempotent — bisa dijalankan ulang)
--
-- CARA PAKAI:
--   1. Backup database dulu (Supabase Dashboard → Database → Backups)
--   2. Pilih waktu sepi (mis. malam, di luar jam operasi toko)
--   3. Copy isi file ini, paste ke SQL Editor, klik Run
--   4. Lihat hasil di bagian VERIFIKASI (paling bawah)
--   5. Kalau angka SEBELUM = SESUDAH, berarti data aman
-- ═══════════════════════════════════════════════════════════════

-- ═══ VERIFIKASI SEBELUM (catat angka-nya) ═══
SELECT
  'transaksi'  AS tabel, COUNT(*) AS jumlah_sebelum FROM transaksi
UNION ALL SELECT 'produk',       COUNT(*) FROM produk
UNION ALL SELECT 'transaksi_item', COUNT(*) FROM transaksi_item
UNION ALL SELECT 'pengeluaran',  COUNT(*) FROM pengeluaran
UNION ALL SELECT 'stok_movement', COUNT(*) FROM stok_movement;

-- ═══ MULAI TRANSACTION (semua atau tidak sama sekali) ═══
BEGIN;

-- ─── 1. TABEL PELANGGAN (idempotent) ─────────────────────────────────
-- IF NOT EXISTS: kalau sudah ada, langsung skip. Data lama AMAN.
CREATE TABLE IF NOT EXISTS pelanggan (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id UUID REFERENCES toko(id) ON DELETE CASCADE,
  nama TEXT NOT NULL,
  hp TEXT,
  alamat TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─── 2. TAMBAH KOLOM MEMBER LOYALTY ──────────────────────────────────
-- ADD COLUMN IF NOT EXISTS: kalau kolom sudah ada, skip. Data lama AMAN.
-- Default 0 → pelanggan lama otomatis dianggap belum belanja apa-apa via member system
ALTER TABLE pelanggan
  ADD COLUMN IF NOT EXISTS total_belanja DECIMAL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS diskon_dipakai DECIMAL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS jumlah_transaksi INT DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_pelanggan_toko_nama ON pelanggan(toko_id, nama);

-- RLS policy refresh (tidak ada efek ke data, cuma izin akses)
ALTER TABLE pelanggan ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all for anon pelanggan" ON pelanggan;
CREATE POLICY "Allow all for anon pelanggan" ON pelanggan FOR ALL USING (true) WITH CHECK (true);

-- ─── 3. TAMBAH KOLOM pelanggan_id DI TRANSAKSI ───────────────────────
-- Nullable (default NULL) → semua transaksi lama otomatis NULL = "Walk-in"
-- Tidak ada UPDATE ke transaksi existing — data lama 100% utuh.
ALTER TABLE transaksi
  ADD COLUMN IF NOT EXISTS pelanggan_id UUID REFERENCES pelanggan(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_transaksi_pelanggan_id ON transaksi(pelanggan_id);

-- ─── 4. UPDATE RPC proses_transaksi_atomic ───────────────────────────
-- Drop+Create dalam transaction SAMA = atomik dari sudut pandang aplikasi lain.
-- Tidak ada window dimana RPC tidak tersedia.
-- Versi baru = versi lama + 2 param baru (p_pelanggan_id, p_diskon_member_dipakai) DENGAN DEFAULT.
-- → Kode lama yang panggil tanpa param baru tetap jalan normal (backward compatible).
DROP FUNCTION IF EXISTS proses_transaksi_atomic(UUID, UUID, TEXT, TEXT, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, TEXT, JSONB);

CREATE OR REPLACE FUNCTION proses_transaksi_atomic(
  p_toko_id UUID,
  p_user_id UUID,
  p_user_nama TEXT,
  p_pelanggan TEXT,
  p_subtotal DECIMAL,
  p_diskon DECIMAL,
  p_total DECIMAL,
  p_bayar DECIMAL,
  p_kembalian DECIMAL,
  p_metode TEXT,
  p_items JSONB,
  p_pelanggan_id UUID DEFAULT NULL,
  p_diskon_member_dipakai DECIMAL DEFAULT 0
) RETURNS TEXT AS $$
DECLARE
  v_nota TEXT;
  v_trx_id UUID;
  v_item JSONB;
  v_stok_bibit DECIMAL;
  v_stok_botol DECIMAL;
  v_potong_bibit DECIMAL;
  v_qty INT;
BEGIN
  v_nota := generate_nota(p_toko_id);

  INSERT INTO transaksi (toko_id, no_nota, user_id, user_nama, pelanggan_nama, pelanggan_id,
    subtotal, diskon, total, bayar, kembalian, metode, status)
  VALUES (p_toko_id, v_nota, p_user_id, p_user_nama, COALESCE(p_pelanggan, 'Walk-in'), p_pelanggan_id,
    p_subtotal, p_diskon, p_total, p_bayar, p_kembalian, p_metode, 'selesai')
  RETURNING id INTO v_trx_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_qty := (v_item->>'qty')::INT;
    v_potong_bibit := (v_item->>'resep_bibit')::DECIMAL * v_qty;

    INSERT INTO transaksi_item (transaksi_id, varian_id, produk_id, botol_id,
      nama_item, qty, harga_satuan, subtotal, resep_bibit, hpp)
    VALUES (v_trx_id,
      (v_item->>'varian_id')::UUID,
      (v_item->>'produk_id')::UUID,
      NULLIF(v_item->>'botol_id', '')::UUID,
      v_item->>'nama_item',
      v_qty,
      (v_item->>'harga_satuan')::DECIMAL,
      (v_item->>'harga_satuan')::DECIMAL * v_qty,
      (v_item->>'resep_bibit')::DECIMAL,
      (v_item->>'hpp')::DECIMAL);

    SELECT stok INTO v_stok_bibit FROM produk
    WHERE id = (v_item->>'produk_id')::UUID FOR UPDATE;

    INSERT INTO stok_movement (toko_id, produk_id, tipe, qty,
      stok_sebelum, stok_sesudah, keterangan, user_id)
    VALUES (p_toko_id, (v_item->>'produk_id')::UUID, 'penjualan', -v_potong_bibit,
      v_stok_bibit, v_stok_bibit - v_potong_bibit,
      'Jual ' || (v_item->>'nama_item') || ' x' || v_qty, p_user_id);

    UPDATE produk SET stok = v_stok_bibit - v_potong_bibit
    WHERE id = (v_item->>'produk_id')::UUID;

    IF (v_item->>'botol_id') IS NOT NULL AND (v_item->>'botol_id') <> '' THEN
      SELECT stok INTO v_stok_botol FROM produk
      WHERE id = (v_item->>'botol_id')::UUID FOR UPDATE;

      INSERT INTO stok_movement (toko_id, produk_id, tipe, qty,
        stok_sebelum, stok_sesudah, keterangan, user_id)
      VALUES (p_toko_id, (v_item->>'botol_id')::UUID, 'penjualan', -v_qty,
        v_stok_botol, v_stok_botol - v_qty,
        'Botol untuk ' || (v_item->>'nama_item') || ' x' || v_qty, p_user_id);

      UPDATE produk SET stok = v_stok_botol - v_qty
      WHERE id = (v_item->>'botol_id')::UUID;
    END IF;
  END LOOP;

  -- Update stats pelanggan (cuma kalau pakai pelanggan_id)
  IF p_pelanggan_id IS NOT NULL THEN
    UPDATE pelanggan
    SET total_belanja = COALESCE(total_belanja, 0) + p_total,
        diskon_dipakai = COALESCE(diskon_dipakai, 0) + COALESCE(p_diskon_member_dipakai, 0),
        jumlah_transaksi = COALESCE(jumlah_transaksi, 0) + 1
    WHERE id = p_pelanggan_id;
  END IF;

  RETURN v_nota;
EXCEPTION
  WHEN OTHERS THEN
    RAISE;
END;
$$ LANGUAGE plpgsql;

-- ─── 5. HELPER FUNCTION: HITUNG DISKON TERSEDIA ──────────────────────
-- Function baru — tidak menggantikan apapun. AMAN.
CREATE OR REPLACE FUNCTION hitung_diskon_tersedia(p_pelanggan_id UUID)
RETURNS DECIMAL AS $$
DECLARE
  v_total DECIMAL;
  v_dipakai DECIMAL;
  v_eligible DECIMAL;
BEGIN
  SELECT COALESCE(total_belanja, 0), COALESCE(diskon_dipakai, 0)
    INTO v_total, v_dipakai
  FROM pelanggan WHERE id = p_pelanggan_id;
  IF v_total IS NULL THEN RETURN 0; END IF;
  v_eligible := FLOOR(v_total / 500000) * 50000;
  RETURN GREATEST(0, v_eligible - v_dipakai);
END;
$$ LANGUAGE plpgsql;

-- ═══ COMMIT TRANSACTION ═══
COMMIT;

-- ═══ VERIFIKASI SESUDAH (bandingkan dengan angka SEBELUM) ═══
-- Angka harus SAMA PERSIS dengan query verifikasi di awal.
-- Kalau berbeda, segera lapor (tapi seharusnya tidak mungkin karena tidak ada DELETE).
SELECT
  'transaksi'  AS tabel, COUNT(*) AS jumlah_sesudah FROM transaksi
UNION ALL SELECT 'produk',       COUNT(*) FROM produk
UNION ALL SELECT 'transaksi_item', COUNT(*) FROM transaksi_item
UNION ALL SELECT 'pengeluaran',  COUNT(*) FROM pengeluaran
UNION ALL SELECT 'stok_movement', COUNT(*) FROM stok_movement;

-- ═══ VERIFIKASI STRUKTUR BARU ═══
-- Pastikan kolom baru sudah ada
SELECT column_name, data_type, column_default FROM information_schema.columns
WHERE table_name='pelanggan'
  AND column_name IN ('total_belanja','diskon_dipakai','jumlah_transaksi');

SELECT column_name, data_type FROM information_schema.columns
WHERE table_name='transaksi' AND column_name='pelanggan_id';

-- ═══ SELESAI ═══
-- Kalau verifikasi SEBELUM = SESUDAH, dan kolom baru muncul,
-- berarti migration SUKSES dan data lama AMAN.
