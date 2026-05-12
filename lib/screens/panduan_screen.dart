import 'package:flutter/material.dart';

class PanduanScreen extends StatelessWidget {
  const PanduanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Panduan Penggunaan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _header('Panduan KS Parfume v3', 'Untuk Owner & Kasir — Migrasi dari Olsera'),
        const SizedBox(height: 16),

        // ─── Migrasi dari Olsera ─────────────────────────────────────────────────
        _sectionCard(Icons.swap_horiz, 'Migrasi dari Olsera', const Color(0xFF2980B9), [
          _item('Langkah 1 — Export Produk dari Olsera',
            'Buka Olsera → Produk → Export → pilih format .xlsx\n'
            'Olsera max 1000 baris/file, export beberapa file jika banyak.\n'
            'Simpan semua file di HP (Download / Files).'),
          _item('Langkah 2 — Import Produk ke App',
            'Buka menu Import/Export di app ini.\n'
            'Tekan "Pilih File .xlsx" → pilih file produk Olsera.\n'
            'Ulangi untuk tiap file (multi-file aman, tidak duplikat).\n'
            'Log akan menampilkan: "X bibit baru, Y varian baru, Z botol baru".'),
          _item('Langkah 3 — Export Resep/BOM dari Olsera',
            'Olsera → Produk → BOM/Resep → Export → format .xlsx atau .csv\n'
            'File format: product_name | product_variant_name | material_product_name | qty'),
          _item('Langkah 4 — Import Resep ke App',
            'Import/Export → "Pilih File Resep" → pilih file BOM dari Olsera.\n'
            'App mendukung .xlsx DAN .csv (separator ";").\n'
            'Setelah import, cek di Katalog → klik parfum → lihat Stok Bibit.'),
          _item('Langkah 5 — Setup Cabang',
            'Pengaturan → Edit Nama Cabang → isi nama & alamat toko.\n'
            'Upload foto QRIS untuk pembayaran non-tunai.\n'
            'Setup Bluetooth Printer jika pakai printer thermal 58mm.'),
          _item('Langkah 6 — Verifikasi',
            'Inventori → cek jumlah produk sudah sesuai.\n'
            'Katalog → klik parfum → pastikan resep bibit & botol terisi.\n'
            'Coba 1 transaksi test di POS → pastikan stok berkurang.'),
        ]),
        const SizedBox(height: 10),

        // ─── Format File Olsera ──────────────────────────────────────────────────
        _sectionCard(Icons.table_chart, 'Format File Olsera', const Color(0xFF16A085), [
          _item('Format Produk A (36 kolom)',
            'Kolom penting: name, category, variant_names, buy_price, sell_price, stock_qty\n'
            'BIBIT: name="BIBIT X", category="STOCK PARFUME", variant_names kosong\n'
            'BOTOL: name="BOTOL X" atau category="STOK BOTOL"\n'
            'VARIAN: name="Paris Hilton", variant_names="15ML,MEDIUM"'),
          _item('Format Produk B (41 kolom)',
            'Sama dengan A, hanya lebih banyak kolom (multi-store).\n'
            'App mendeteksi otomatis berdasarkan nama header kolom.'),
          _item('Format Resep/BOM (9 kolom)',
            'to_all_store_id ; to_store_url_id ; product_name ; product_variant_name ;\n'
            'material_product_name ; material_variant_name ; qty ; uom ; uom_conversion\n\n'
            'Kolom yang dipakai: [2]=product_name, [3]=product_variant_name,\n'
            '[4]=material_product_name, [6]=qty'),
          _item('Tips Multi-file',
            'Olsera export max 1000 baris/file.\n'
            'Import file 1, 2, 3 dst secara berurutan.\n'
            'App upsert (tidak duplikat) — aman import ulang file yang sama.'),
        ]),
        const SizedBox(height: 10),

        // ─── POS / Kasir ─────────────────────────────────────────────────────────
        _sectionCard(Icons.point_of_sale, 'Kasir / POS (Penjualan)', const Color(0xFF27AE60), [
          _item('Jual Parfum Racik',
            '1. Buka POS → cari parfum\n'
            '2. Klik kartu parfum → pilih Ukuran → pilih Kualitas\n'
            '3. Item masuk keranjang — ulangi untuk item lain\n'
            '4. Pilih metode bayar: Cash / QRIS / Transfer\n'
            '5. Cash: masukkan nominal terima → klik Bayar\n'
            '6. QRIS: klik Tampilkan QRIS → customer scan → Sudah Bayar\n'
            '7. Stok bibit & botol otomatis berkurang sesuai resep'),
          _item('Jual Bibit Langsung (per ml)',
            'Scroll ke bawah POS → bagian "Jual Bibit Langsung"\n'
            'Pilih bibit → harga otomatis dari harga_jual_bibit (atau fallback harga_beli)\n'
            'Pilih botol (opsional) → masukkan ml → Catat Penjualan'),
          _item('Harga Range pada Kartu Parfum',
            'Kartu parfum menampilkan range harga: Rp 45.000 – Rp 150.000\n'
            'Dihitung dari harga_jual varian terendah sampai tertinggi.'),
          _item('Stok Habis',
            'Jika stok bibit < kebutuhan resep, tombol varian tidak bisa diklik.\n'
            'Restok dulu via menu Stok Masuk.'),
        ]),
        const SizedBox(height: 10),

        // ─── Inventori ───────────────────────────────────────────────────────────
        _sectionCard(Icons.inventory_2, 'Inventori', const Color(0xFF2980B9), [
          _item('Lihat Stok',
            'Cari produk dengan kolom pencarian.\n'
            'Filter: Semua / STOCK PARFUME / STOK BOTOL\n'
            'Angka merah = stok di bawah minimum → perlu restok.'),
          _item('Edit Stok Manual',
            'Owner bisa tap ikon edit di tiap produk.\n'
            'Ubah stok aktual dan harga beli.\n'
            'Gunakan ini untuk koreksi stok.'),
        ]),
        const SizedBox(height: 10),

        // ─── Stok Masuk / Keluar ─────────────────────────────────────────────────
        _sectionCard(Icons.add_box, 'Stok Masuk & Keluar', const Color(0xFF16A085), [
          _item('Stok Masuk (Restok)',
            '1. Pilih produk yang direstok\n'
            '2. Masukkan qty dan harga beli (auto-fill dari harga terakhir)\n'
            '3. Tambahkan catatan (opsional) → Simpan\n'
            '4. Riwayat tercatat dengan tanggal & waktu'),
          _item('Stok Keluar (Non-penjualan)',
            '1. Pilih produk → masukkan qty\n'
            '2. Pilih alasan: Rusak / Hilang / Sample-Tester / Koreksi Stok / Lainnya\n'
            '3. Tambah catatan opsional → Catat Keluar'),
        ]),
        const SizedBox(height: 10),

        // ─── Katalog ─────────────────────────────────────────────────────────────
        _sectionCard(Icons.menu_book, 'Katalog Produk', const Color(0xFFD4A574), [
          _item('Lihat Varian & Resep',
            'Pilih parfum → detail menampilkan semua varian + harga jual.\n'
            'Di bawah varian ada section Stok Bibit dengan resep (ml bibit + botol).'),
          _item('Edit Bahan Resep',
            'Tap ikon edit di bagian Stok Bibit → ubah qty bibit / botol.\n'
            'Owner dapat ubah resep kapan saja.'),
          _item('Export Katalog',
            'Import/Export Excel untuk backup katalog lengkap.\n'
            'Export Resep CSV untuk file BOM/resep format Olsera.'),
        ]),
        const SizedBox(height: 10),

        // ─── Pergerakan Stok ─────────────────────────────────────────────────────
        _sectionCard(Icons.swap_vert, 'Pergerakan Stok', const Color(0xFFE67E22), [
          _item('Filter & Range Tanggal',
            'Filter by: Hari Ini / Bulan Ini / Tahun Ini / Semua\n'
            'Atau pilih range tanggal custom dengan date picker.\n'
            'Filter tipe: Semua / Masuk / Penjualan / Keluar'),
          _item('Ringkasan Tabel',
            'Tabel menampilkan per produk: Saldo Awal, Masuk, Jual, Keluar, Sisa.\n'
            'Simpan Saldo Awal setiap awal bulan (ikon bookmark di AppBar).'),
        ]),
        const SizedBox(height: 10),

        // ─── Laporan ─────────────────────────────────────────────────────────────
        _sectionCard(Icons.bar_chart, 'Laporan Keuangan', const Color(0xFF8E44AD), [
          _item('Profit Loss (Gaya Olsera)',
            'A. Income = total penjualan\n'
            'B. Cost of Goods Sold (HPP) = biaya bahan sesuai resep\n'
            'C. Gross Profit = A - B\n'
            'D. Expenses = pengeluaran operasional\n'
            'G. Nett Profit = Gross Profit - Expenses'),
          _item('Export PDF',
            'Tap ikon PDF di AppBar → share / print laporan.\n'
            'Laporan berisi Profit Loss + detail pengeluaran + produk terlaris.'),
        ]),
        const SizedBox(height: 10),

        // ─── Pengaturan / Reset ───────────────────────────────────────────────────
        _sectionCard(Icons.settings, 'Pengaturan & Reset', const Color(0xFF6B5B4B), [
          _item('Kelola User',
            'Tambah / hapus kasir. Ubah PIN 4 digit.\n'
            'Owner: akses semua menu.\n'
            'Kasir: hanya POS, Shift, Pengeluaran.'),
          _item('Danger Zone',
            'Reset Semua Resep: hapus resep_bibit & botol (sebelum import resep baru)\n'
            'Hapus Semua Produk: hapus produk + varian (untuk rekonfigurasi katalog)\n'
            'RESET SEMUA DATA: hapus produk + transaksi + pengeluaran (fresh start)\n\n'
            'Setiap aksi butuh konfirmasi 2 langkah + ketik kata kunci.'),
        ]),
        const SizedBox(height: 10),

        // ─── Menu Referensi ───────────────────────────────────────────────────────
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF3A2E24), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.grid_view, color: Colors.white, size: 18)),
            const SizedBox(width: 10),
            const Text('Referensi Menu', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          ...[
            ['Kasir / POS', 'Transaksi penjualan parfum', Icons.point_of_sale, 0xFFD4A574],
            ['Shift', 'Buka/tutup shift, kas masuk/keluar', Icons.access_time, 0xFF16A085],
            ['Pengeluaran', 'Catat pengeluaran operasional', Icons.receipt_long, 0xFFC0392B],
            ['Katalog', 'Daftar parfum, varian & resep', Icons.menu_book, 0xFFD4A574],
            ['Inventori', 'Stok bahan baku (bibit + botol)', Icons.inventory_2, 0xFF2980B9],
            ['Pergerakan', 'Riwayat semua gerakan stok', Icons.swap_vert, 0xFF27AE60],
            ['Stok Masuk', 'Catat penambahan stok (restok)', Icons.add_box, 0xFF16A085],
            ['Stok Keluar', 'Catat stok hilang/rusak/sample', Icons.remove_circle, 0xFFC0392B],
            ['Produk', 'Kelola produk & varian (nama/harga)', Icons.style, 0xFFE67E22],
            ['Template Resep', 'Template default bibit/botol per ukuran', Icons.rule, 0xFF8E44AD],
            ['Laporan', 'Profit Loss + grafik + transaksi', Icons.bar_chart, 0xFF8E44AD],
            ['Cabang', 'Laporan perbandingan antar cabang', Icons.store, 0xFF0984E3],
            ['Import/Export', 'Import xlsx Olsera, export backup', Icons.file_copy, 0xFF6B5B4B],
            ['Pengaturan', 'User, QRIS, printer, danger zone', Icons.settings, 0xFF6B5B4B],
            ['Panduan', 'Panduan penggunaan (halaman ini)', Icons.menu_book_outlined, 0xFFD4A574],
            ['Bluetooth', 'Setup & test printer thermal 58mm', Icons.bluetooth, 0xFF2980B9],
          ].map((x) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
            Container(width: 30, height: 30, decoration: BoxDecoration(color: Color(x[3] as int).withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
              child: Icon(x[2] as IconData, color: Color(x[3] as int), size: 16)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x[0] as String, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Text(x[1] as String, style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
            ])),
          ]))),
        ]))),
        const SizedBox(height: 16),

        // ─── Tips ─────────────────────────────────────────────────────────────────
        Card(color: const Color(0xFFFAF8F5), child: Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Tips & Catatan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...[
            'Tarik layar ke bawah untuk refresh data di semua halaman',
            'Data sinkron otomatis antar HP (Owner & semua Kasir)',
            'Import produk bisa dilakukan beberapa kali — tidak akan duplikat',
            'Stok berkurang otomatis saat ada penjualan (via trigger database)',
            'Backup rutin via Import/Export → Backup Semua (JSON)',
            'Printer Bluetooth: pairing dulu di Setting HP, lalu pilih di menu Bluetooth',
          ].map((t) => Padding(padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('• ', style: TextStyle(fontSize: 12, color: Color(0xFFD4A574), fontWeight: FontWeight.w700)),
              Expanded(child: Text(t, style: const TextStyle(fontSize: 11, color: Color(0xFF6B5B4B), height: 1.4))),
            ]))),
        ]))),
        const SizedBox(height: 24),
      ]),
    );
  }

  static Widget _header(String title, String sub) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF3A2E24))),
    const SizedBox(height: 4),
    Text(sub, style: const TextStyle(fontSize: 12, color: Color(0xFFA09080))),
  ]);

  static Widget _sectionCard(IconData icon, String title, Color color, List<Widget> children) =>
    Card(margin: const EdgeInsets.only(bottom: 10), child: Theme(
      data: ThemeData(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: Colors.white, size: 18)),
        title: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: children)));

  static Widget _item(String title, String body) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF3A2E24))),
    const SizedBox(height: 4),
    Text(body, style: const TextStyle(fontSize: 11, color: Color(0xFF6B5B4B), height: 1.5)),
  ]));
}
