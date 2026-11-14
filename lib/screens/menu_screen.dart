
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../db/database.dart';
import '../models.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import '../widgets/common.dart';

Future<Uint8List?> pickImageBytes(BuildContext context, {double maxWidth = 600, int quality = 75}) async {
  final src = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded),
            title: const Text('Ambil dari Kamera'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('Pilih dari Galeri'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (src == null) return null;
  try {
    final x = await ImagePicker().pickImage(source: src, maxWidth: maxWidth, maxHeight: maxWidth, imageQuality: quality);
    if (x == null) return null;
    return await x.readAsBytes();
  } catch (e) {
    Notify.error('Gagal mengambil gambar: $e');
    return null;
  }
}

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  List<MenuItem> _menus = [];
  List<Category> _cats = [];
  int? _cat;
  String _q = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await Repo.menus();
    final c = await Repo.categories();
    if (!mounted) return;
    setState(() {
      _menus = m;
      _cats = c;
      _loading = false;
      if (_cat != null && !c.any((e) => e.id == _cat)) _cat = null;
    });
  }

  Future<void> _openForm([MenuItem? m]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MenuFormScreen(item: m, categories: _cats)),
    );
    if (saved == true) _load();
  }

  Future<void> _manageCategories() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CategoryScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _q.trim().toLowerCase();
    final list = _menus.where((m) {
      if (_cat != null && m.categoryId != _cat) return false;
      if (q.isNotEmpty && !m.name.toLowerCase().contains(q)) return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Menu', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          TextButton.icon(
            onPressed: _manageCategories,
            icon: const Icon(Icons.category_rounded),
            label: const Text('Kategori'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah Menu'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'Cari menu...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withOpacity(0.5),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text('Semua (${_menus.length})'), selected: _cat == null, onSelected: (_) => setState(() => _cat = null)),
                ),
                for (final c in _cats)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(c.name), selected: _cat == c.id, onSelected: (_) => setState(() => _cat = c.id)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? EmptyState(
                        icon: Icons.restaurant_menu_rounded,
                        title: 'Belum ada menu',
                        subtitle: 'Tekan tombol "Tambah Menu" untuk menambahkan',
                        action: FilledButton.icon(onPressed: () => _openForm(), icon: const Icon(Icons.add), label: const Text('Tambah Menu')),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final m = list[i];
                            return SoftCard(
                              padding: const EdgeInsets.all(8),
                              onTap: () => _openForm(m),
                              child: Row(
                                children: [
                                  SizedBox(width: 64, height: 64, child: MenuThumb(image: m.image, name: m.name, cacheWidth: 160)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                        Text(m.categoryName.isEmpty ? 'Tanpa kategori' : m.categoryName,
                                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                                        const SizedBox(height: 2),
                                        Text(rp(m.price), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    children: [
                                      Switch(
                                        value: m.available,
                                        onChanged: (v) async {
                                          await Repo.setMenuAvailable(m.id!, v);
                                          setState(() => m.available = v);
                                          Notify.info(v ? '${m.name} tersedia' : '${m.name} ditandai habis');
                                        },
                                      ),
                                      Text(m.available ? 'Tersedia' : 'Habis',
                                          style: TextStyle(fontSize: 11, color: m.available ? cs.primary : cs.error)),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ======================= FORM MENU =======================
class MenuFormScreen extends StatefulWidget {
  final MenuItem? item;
  final List<Category> categories;
  const MenuFormScreen({super.key, this.item, required this.categories});

  @override
  State<MenuFormScreen> createState() => _MenuFormScreenState();
}

class _MenuFormScreenState extends State<MenuFormScreen> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _sort = TextEditingController();
  int? _catId;
  bool _available = true;
  Uint8List? _image;
  bool _saving = false;

  bool get _isEdit => widget.item?.id != null;

  @override
  void initState() {
    super.initState();
    final m = widget.item;
    if (m != null) {
      _name.text = m.name;
      _price.text = nf(m.price);
      _sort.text = '${m.sort}';
      _catId = m.categoryId;
      _available = m.available;
      _image = m.image;
    } else {
      _sort.text = '0';
      if (widget.categories.isNotEmpty) _catId = widget.categories.first.id;
    }
    if (_catId != null && !widget.categories.any((c) => c.id == _catId)) _catId = null;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _sort.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final b = await pickImageBytes(context);
    if (b != null && mounted) setState(() => _image = b);
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      Notify.warning('Nama menu wajib diisi');
      return;
    }
    final price = parseNum(_price.text);
    setState(() => _saving = true);
    try {
      final m = MenuItem(
        id: widget.item?.id,
        name: name,
        categoryId: _catId,
        price: price,
        image: _image,
        available: _available,
        sort: int.tryParse(_sort.text.trim()) ?? 0,
      );
      await Repo.saveMenu(m);
      Notify.success(_isEdit ? 'Menu diperbarui' : 'Menu ditambahkan');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      Notify.error('Gagal menyimpan: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'Hapus menu?', message: 'Menu "${widget.item!.name}" akan dihapus. Riwayat penjualan tetap tersimpan.', okText: 'Hapus', danger: true);
    if (!ok) return;
    await Repo.deleteMenu(widget.item!.id!);
    Notify.success('Menu dihapus');
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Ubah Menu' : 'Tambah Menu'),
        actions: [
          if (_isEdit) IconButton(onPressed: _delete, icon: Icon(Icons.delete_outline_rounded, color: cs.error)),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pick,
                  child: Stack(
                    children: [
                      SizedBox(width: 180, height: 180, child: MenuThumb(image: _image, name: _name.text.isEmpty ? '+' : _name.text, radius: 24, cacheWidth: 400)),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: CircleAvatar(
                          backgroundColor: cs.primary,
                          child: Icon(Icons.camera_alt_rounded, color: cs.onPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_image != null)
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _image = null),
                    icon: const Icon(Icons.hide_image_outlined),
                    label: const Text('Hapus gambar'),
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: inputDeco('Nama Menu', icon: Icons.restaurant_rounded),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahFormatter()],
                decoration: inputDeco('Harga', icon: Icons.sell_rounded, prefix: 'Rp '),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: _catId,
                decoration: inputDeco('Kategori', icon: Icons.category_rounded),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Tanpa kategori')),
                  for (final c in widget.categories) DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _catId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sort,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: inputDeco('Urutan tampil (angka kecil tampil dulu)', icon: Icons.sort_rounded),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _available,
                onChanged: (v) => setState(() => _available = v),
                title: const Text('Tersedia / bisa dijual'),
                subtitle: const Text('Matikan bila menu sedang habis'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('SIMPAN', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================= KATEGORI =======================
class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  List<Category> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await Repo.categories();
    if (mounted) setState(() => _list = l);
  }

  Future<void> _edit([Category? c]) async {
    final name = await inputDialog(context, title: c == null ? 'Tambah Kategori' : 'Ubah Kategori', initial: c?.name ?? '', label: 'Nama kategori');
    if (name == null || name.trim().isEmpty) return;
    await Repo.saveCategory(id: c?.id, name: name, sort: c?.sort ?? _list.length);
    Notify.success('Kategori disimpan');
    _load();
  }

  Future<void> _move(int i, int dir) async {
    final j = i + dir;
    if (j < 0 || j >= _list.length) return;
    final l = List.of(_list);
    final tmp = l[i];
    l[i] = l[j];
    l[j] = tmp;
    for (var k = 0; k < l.length; k++) {
      await Repo.saveCategory(id: l[k].id, name: l[k].name, sort: k);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Kategori Menu')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Kategori')),
      body: _list.isEmpty
          ? const EmptyState(icon: Icons.category_rounded, title: 'Belum ada kategori')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: _list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final c = _list[i];
                return SoftCard(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(backgroundColor: cs.primaryContainer, child: Text('${i + 1}')),
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    onTap: () => _edit(c),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(onPressed: i == 0 ? null : () => _move(i, -1), icon: const Icon(Icons.arrow_upward_rounded)),
                        IconButton(onPressed: i == _list.length - 1 ? null : () => _move(i, 1), icon: const Icon(Icons.arrow_downward_rounded)),
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                          onPressed: () async {
                            final ok = await confirmDialog(context,
                                title: 'Hapus kategori?',
                                message: 'Menu di kategori "${c.name}" akan menjadi tanpa kategori.',
                                okText: 'Hapus',
                                danger: true);
                            if (!ok) return;
                            await Repo.deleteCategory(c.id);
                            Notify.success('Kategori dihapus');
                            _load();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
