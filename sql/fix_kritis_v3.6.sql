-- ═══════════════════════════════════════════════════════════════
-- KS PARFUME v3.6 — CRITICAL FIXES
-- Jalankan 1x di Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ═══ 1. NOTA SEQUENCE (anti duplikat) ═══
CREATE TABLE IF NOT EXISTS nota_counter (
  toko_id UUID REFERENCES toko(id) ON DELETE CASCADE,
  tanggal DATE NOT NULL,
  counter INT DEFAULT 0,
  PRIMARY KEY (toko_id, tanggal)
);

ALTER TABLE nota_counter ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all for anon" ON nota_counter;
CREATE POLICY "Allow all for anon" ON nota_counter FOR ALL USING (true) WITH CHECK (true);

-- Function: generate nomor nota unik per toko per hari
CREATE OR REPLACE FUNCTION generate_nota(p_toko_id UUID)
RETURNS TEXT AS $$
DECLARE
  v_counter INT;
  v_date DATE := CURRENT_DATE;
  v_nota TEXT;
BEGIN
  INSERT INTO nota_counter (toko_id, tanggal, counter)
  VALUES (p_toko_id, v_date, 1)
  ON CONFLICT (toko_id, tanggal)
  DO UPDATE SET counter = nota_counter.counter + 1
  RETURNING counter INTO v_counter;

  v_nota := 'INV' || TO_CHAR(v_date, 'YYMMDD') || LPAD(v_counter::TEXT, 5, '0');
  RETURN v_nota;
END;
$$ LANGUAGE plpgsql;

-- ═══ 2. ATOMIC TRANSACTION (anti race condition) ═══
-- Process transaksi server-side dengan lock per-produk
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
  p_items JSONB  -- [{varian_id, produk_id, botol_id, nama_item, qty, harga_satuan, resep_bibit, hpp}]
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
  -- Generate nota sequential
  v_nota := generate_nota(p_toko_id);

  -- Insert transaksi header
  INSERT INTO transaksi (toko_id, no_nota, user_id, user_nama, pelanggan_nama,
    subtotal, diskon, total, bayar, kembalian, metode, status)
  VALUES (p_toko_id, v_nota, p_user_id, p_user_nama, COALESCE(p_pelanggan, 'Walk-in'),
    p_subtotal, p_diskon, p_total, p_bayar, p_kembalian, p_metode, 'selesai')
  RETURNING id INTO v_trx_id;

  -- Process each item dengan lock per-produk
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_qty := (v_item->>'qty')::INT;
    v_potong_bibit := (v_item->>'resep_bibit')::DECIMAL * v_qty;

    -- Insert transaksi_item
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

    -- Lock + potong stok bibit
    SELECT stok INTO v_stok_bibit FROM produk
    WHERE id = (v_item->>'produk_id')::UUID FOR UPDATE;

    INSERT INTO stok_movement (toko_id, produk_id, tipe, qty,
      stok_sebelum, stok_sesudah, keterangan, user_id)
    VALUES (p_toko_id, (v_item->>'produk_id')::UUID, 'penjualan', -v_potong_bibit,
      v_stok_bibit, v_stok_bibit - v_potong_bibit,
      'Jual ' || (v_item->>'nama_item') || ' x' || v_qty, p_user_id);

    -- Samakan stok bibit di tabel produk (UI & laporan pakai kolom ini)
    UPDATE produk SET stok = v_stok_bibit - v_potong_bibit
    WHERE id = (v_item->>'produk_id')::UUID;

    -- Lock + potong stok botol (jika ada)
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

  RETURN v_nota;
EXCEPTION
  WHEN OTHERS THEN
    -- Rollback otomatis karena ini single transaction
    RAISE;
END;
$$ LANGUAGE plpgsql;

-- ═══ 3. LOGIN WITH PIN HASH (anti plaintext) ═══
-- Fungsi verify PIN dengan hash SHA256
CREATE OR REPLACE FUNCTION verify_pin(p_toko_id UUID, p_pin_hash TEXT)
RETURNS TABLE(id UUID, nama TEXT, peran TEXT) AS $$
BEGIN
  RETURN QUERY
  SELECT u.id, u.nama, u.peran FROM users u
  WHERE u.toko_id = p_toko_id
    AND (u.pin = p_pin_hash OR u.pin_hash = p_pin_hash);
END;
$$ LANGUAGE plpgsql;

-- Kolom pin_hash baru (biarkan pin lama untuk backward compat)
ALTER TABLE users ADD COLUMN IF NOT EXISTS pin_hash TEXT;
CREATE INDEX IF NOT EXISTS idx_users_pin_hash ON users(pin_hash);

-- ═══ 4. LOCKOUT TABLE (brute force protection) ═══
CREATE TABLE IF NOT EXISTS login_attempts (
  toko_id UUID,
  device_id TEXT,
  failed_count INT DEFAULT 0,
  locked_until TIMESTAMP WITH TIME ZONE,
  last_attempt TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (toko_id, device_id)
);

ALTER TABLE login_attempts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all for anon" ON login_attempts;
CREATE POLICY "Allow all for anon" ON login_attempts FOR ALL USING (true) WITH CHECK (true);

-- ═══ SELESAI ═══
-- Setelah jalankan SQL ini, update APK ke v3.6 yang pakai RPC proses_transaksi_atomic
