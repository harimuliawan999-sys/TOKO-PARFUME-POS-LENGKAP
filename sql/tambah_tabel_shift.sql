-- ═══════════════════════════════════════════════════════════════
-- FITUR BARU: Shift Management, Kas Masuk/Keluar, Pembatalan
-- Jalankan 1x di Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- 1. TABEL SHIFT
CREATE TABLE IF NOT EXISTS shift (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  toko_id UUID REFERENCES toko(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id),
  user_nama VARCHAR(100),
  mulai TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  selesai TIMESTAMP WITH TIME ZONE,
  kas_awal DECIMAL(15,2) DEFAULT 0,
  kas_penjualan DECIMAL(15,2) DEFAULT 0,
  kas_pengembalian DECIMAL(15,2) DEFAULT 0,
  kas_pembatalan DECIMAL(15,2) DEFAULT 0,
  kas_masuk_keluar DECIMAL(15,2) DEFAULT 0,
  total_diharapkan DECIMAL(15,2) DEFAULT 0,
  kas_aktual DECIMAL(15,2) DEFAULT 0,
  selisih DECIMAL(15,2) DEFAULT 0,
  status VARCHAR(20) DEFAULT 'aktif' CHECK (status IN ('aktif', 'selesai')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. TABEL SHIFT KAS (kas masuk/keluar selama shift)
CREATE TABLE IF NOT EXISTS shift_kas (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  shift_id UUID REFERENCES shift(id) ON DELETE CASCADE,
  toko_id UUID REFERENCES toko(id) ON DELETE CASCADE,
  tipe VARCHAR(10) NOT NULL CHECK (tipe IN ('masuk', 'keluar')),
  jumlah DECIMAL(15,2) NOT NULL,
  keterangan TEXT,
  user_id UUID REFERENCES users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. TABEL PEMBATALAN (void)
CREATE TABLE IF NOT EXISTS pembatalan (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  toko_id UUID REFERENCES toko(id) ON DELETE CASCADE,
  shift_id UUID REFERENCES shift(id),
  transaksi_id UUID REFERENCES transaksi(id),
  varian_id UUID,
  produk_id UUID,
  nama_item VARCHAR(200),
  qty INT DEFAULT 1,
  harga DECIMAL(15,2) DEFAULT 0,
  total DECIMAL(15,2) DEFAULT 0,
  alasan TEXT,
  user_id UUID REFERENCES users(id),
  user_nama VARCHAR(100),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- INDEXES
CREATE INDEX IF NOT EXISTS idx_shift_toko ON shift(toko_id);
CREATE INDEX IF NOT EXISTS idx_shift_status ON shift(status);
CREATE INDEX IF NOT EXISTS idx_shift_kas_shift ON shift_kas(shift_id);
CREATE INDEX IF NOT EXISTS idx_pembatalan_toko ON pembatalan(toko_id);

-- RLS
ALTER TABLE shift ENABLE ROW LEVEL SECURITY;
ALTER TABLE shift_kas ENABLE ROW LEVEL SECURITY;
ALTER TABLE pembatalan ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow all for anon" ON shift FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for anon" ON shift_kas FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for anon" ON pembatalan FOR ALL USING (true) WITH CHECK (true);

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE shift;

-- ═══════════════════════════════════════════════════════════════
-- SELESAI! Tabel shift, shift_kas, pembatalan siap dipakai
-- ═══════════════════════════════════════════════════════════════
