-- ═══════════════════════════════════════════════════════════════
-- FIX: proses_transaksi_atomic - tambah UPDATE produk.stok
-- untuk bibit DAN botol setelah potong stok
-- Jalankan di Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════
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
  p_items JSONB
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

  INSERT INTO transaksi (toko_id, no_nota, user_id, user_nama, pelanggan_nama,
    subtotal, diskon, total, bayar, kembalian, metode, status)
  VALUES (p_toko_id, v_nota, p_user_id, p_user_nama, COALESCE(p_pelanggan, 'Walk-in'),
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

    -- Lock + potong stok bibit
    SELECT stok INTO v_stok_bibit FROM produk
    WHERE id = (v_item->>'produk_id')::UUID FOR UPDATE;

    INSERT INTO stok_movement (toko_id, produk_id, tipe, qty,
      stok_sebelum, stok_sesudah, keterangan, user_id)
    VALUES (p_toko_id, (v_item->>'produk_id')::UUID, 'penjualan', -v_potong_bibit,
      v_stok_bibit, v_stok_bibit - v_potong_bibit,
      'Jual ' || (v_item->>'nama_item') || ' x' || v_qty, p_user_id);

    -- UPDATE stok bibit di tabel produk
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

      -- UPDATE stok botol di tabel produk
      UPDATE produk SET stok = v_stok_botol - v_qty
      WHERE id = (v_item->>'botol_id')::UUID;
    END IF;
  END LOOP;

  RETURN v_nota;
EXCEPTION
  WHEN OTHERS THEN
    RAISE;
END;
$$ LANGUAGE plpgsql;
-- ═══════════════════════════════════════════════════════════════
-- SELESAI! Sekarang stok bibit + botol langsung berkurang saat jual
-- ═══════════════════════════════════════════════════════════════
