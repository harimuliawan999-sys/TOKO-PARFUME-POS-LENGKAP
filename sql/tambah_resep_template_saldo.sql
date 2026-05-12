-- ═══════════════════════════════════════════════════════════════
-- FITUR BARU v3.6: Template Resep Otomatis + Saldo Awal Bulanan
-- Jalankan 1x di Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- 1. Template resep global (per ukuran + kualitas)
-- Saat bikin varian baru, otomatis pakai template ini
CREATE TABLE IF NOT EXISTS resep_template (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  ukuran VARCHAR(20) NOT NULL,
  kualitas VARCHAR(30) NOT NULL,
  qty_bibit DECIMAL(10,2) NOT NULL,
  qty_botol DECIMAL(10,2) DEFAULT 1,
  botol_kategori VARCHAR(50),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(ukuran, kualitas)
);

-- Insert default template berdasarkan file 01_csv.xls (Olsera recipe)
INSERT INTO resep_template (ukuran, kualitas, qty_bibit, qty_botol, botol_kategori) VALUES
  ('15ML', 'MEDIUM', 8, 1, 'STOK BOTOL 15ML'),
  ('15ML', 'SUPER', 9, 1, 'STOK BOTOL 15ML'),
  ('15ML', 'PLATINUM', 11, 1, 'STOK BOTOL 15ML'),
  ('15ML', 'FULL BIBIT', 15, 1, 'STOK BOTOL 15ML'),
  ('20ML', 'MEDIUM', 10, 1, 'STOK BOTOL 20ML'),
  ('20ML', 'SUPER', 11, 1, 'STOK BOTOL 20ML'),
  ('20ML', 'PLATINUM', 14, 1, 'STOK BOTOL 20ML'),
  ('20ML', 'FULL BIBIT', 20, 1, 'STOK BOTOL 20ML'),
  ('25ML', 'MEDIUM', 12, 1, 'STOK BOTOL 25ML'),
  ('25ML', 'SUPER', 13, 1, 'STOK BOTOL 25ML'),
  ('25ML', 'PLATINUM', 18, 1, 'STOK BOTOL 25ML'),
  ('25ML', 'FULL BIBIT', 25, 1, 'STOK BOTOL 25ML'),
  ('30ML', 'MEDIUM', 14, 1, 'STOK BOTOL 30ML'),
  ('30ML', 'SUPER', 16, 1, 'STOK BOTOL 30ML'),
  ('30ML', 'PLATINUM', 21, 1, 'STOK BOTOL 30ML'),
  ('30ML', 'FULL BIBIT', 30, 1, 'STOK BOTOL 30ML'),
  ('35ML', 'MEDIUM', 16, 1, 'STOK BOTOL 35ML'),
  ('35ML', 'SUPER', 18, 1, 'STOK BOTOL 35ML'),
  ('35ML', 'PLATINUM', 25, 1, 'STOK BOTOL 35ML'),
  ('35ML', 'FULL BIBIT', 35, 1, 'STOK BOTOL 35ML'),
  ('40ML', 'MEDIUM', 18, 1, 'STOK BOTOL 40ML'),
  ('40ML', 'SUPER', 21, 1, 'STOK BOTOL 40ML'),
  ('40ML', 'PLATINUM', 28, 1, 'STOK BOTOL 40ML'),
  ('40ML', 'FULL BIBIT', 40, 1, 'STOK BOTOL 40ML'),
  ('50ML', 'MEDIUM', 23, 1, 'STOK BOTOL 50ML'),
  ('50ML', 'SUPER', 26, 1, 'STOK BOTOL 50ML'),
  ('50ML', 'PLATINUM', 35, 1, 'STOK BOTOL 50ML'),
  ('50ML', 'FULL BIBIT', 50, 1, 'STOK BOTOL 50ML'),
  ('55ML', 'MEDIUM', 25, 1, 'STOK BOTOL 55ML'),
  ('55ML', 'SUPER', 28, 1, 'STOK BOTOL 55ML'),
  ('55ML', 'PLATINUM', 38, 1, 'STOK BOTOL 55ML'),
  ('55ML', 'FULL BIBIT', 55, 1, 'STOK BOTOL 55ML'),
  ('60ML', 'MEDIUM', 27, 1, 'STOK BOTOL 60ML'),
  ('60ML', 'SUPER', 31, 1, 'STOK BOTOL 60ML'),
  ('60ML', 'PLATINUM', 42, 1, 'STOK BOTOL 60ML'),
  ('60ML', 'FULL BIBIT', 60, 1, 'STOK BOTOL 60ML'),
  ('100ML', 'MEDIUM', 45, 1, 'STOK BOTOL 100ML'),
  ('100ML', 'SUPER', 52, 1, 'STOK BOTOL 100ML'),
  ('100ML', 'PLATINUM', 70, 1, 'STOK BOTOL 100ML'),
  ('100ML', 'FULL BIBIT', 100, 1, 'STOK BOTOL 100ML')
ON CONFLICT (ukuran, kualitas) DO NOTHING;

-- 2. Saldo awal bulanan (snapshot stok tiap awal bulan)
CREATE TABLE IF NOT EXISTS saldo_awal (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  toko_id UUID REFERENCES toko(id) ON DELETE CASCADE,
  produk_id UUID REFERENCES produk(id) ON DELETE CASCADE,
  periode_bulan INT NOT NULL,
  periode_tahun INT NOT NULL,
  saldo DECIMAL(15,2) DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(toko_id, produk_id, periode_bulan, periode_tahun)
);

CREATE INDEX IF NOT EXISTS idx_saldo_awal_toko ON saldo_awal(toko_id);
CREATE INDEX IF NOT EXISTS idx_saldo_awal_periode ON saldo_awal(periode_tahun, periode_bulan);

-- 3. RLS
ALTER TABLE resep_template ENABLE ROW LEVEL SECURITY;
ALTER TABLE saldo_awal ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all for anon" ON resep_template;
DROP POLICY IF EXISTS "Allow all for anon" ON saldo_awal;

CREATE POLICY "Allow all for anon" ON resep_template FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all for anon" ON saldo_awal FOR ALL USING (true) WITH CHECK (true);

-- ═══════════════════════════════════════════════════════════════
-- SELESAI! Template resep siap + tabel saldo awal siap
-- ═══════════════════════════════════════════════════════════════
