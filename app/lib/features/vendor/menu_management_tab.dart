import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/format.dart';
import '../../core/models/menu_item.dart';

class MenuManagementTab extends StatefulWidget {
  const MenuManagementTab({super.key});

  @override
  State<MenuManagementTab> createState() => _MenuManagementTabState();
}

class _MenuManagementTabState extends State<MenuManagementTab> {
  late Future<List<MenuItem>> _itemsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _itemsFuture = context.read<ApiClient>().listMyMenuItems();
  }

  Future<void> _openEditor({MenuItem? item}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MenuItemEditor(item: item),
    );
    if (result == true) setState(_load);
  }

  Future<void> _toggleAvailable(MenuItem item, bool value) async {
    await context.read<ApiClient>().updateMenuItem(
          item.id,
          name: item.name,
          priceCents: item.priceCents,
          description: item.description,
          isAvailable: value,
        );
    setState(_load);
  }

  Future<void> _delete(MenuItem item) async {
    await context.read<ApiClient>().deleteMenuItem(item.id);
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<MenuItem>>(
        future: _itemsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('โหลดเมนูไม่สำเร็จ'));
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(child: Text('ยังไม่มีเมนู กดปุ่ม + เพื่อเพิ่มเมนู'));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                title: Text(item.name),
                subtitle: Text(formatBaht(item.priceCents)),
                onTap: () => _openEditor(item: item),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(value: item.isAvailable, onChanged: (v) => _toggleAvailable(item, v)),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(item),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MenuItemEditor extends StatefulWidget {
  final MenuItem? item;

  const _MenuItemEditor({this.item});

  @override
  State<_MenuItemEditor> createState() => _MenuItemEditorState();
}

class _MenuItemEditorState extends State<_MenuItemEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _descriptionController;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item?.name ?? '');
    _priceController = TextEditingController(
      text: widget.item != null ? (widget.item!.priceCents / 100).toStringAsFixed(2) : '',
    );
    _descriptionController = TextEditingController(text: widget.item?.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final priceCents = ((double.tryParse(_priceController.text) ?? 0) * 100).round();
    try {
      final api = context.read<ApiClient>();
      if (widget.item == null) {
        await api.createMenuItem(
          name: _nameController.text.trim(),
          priceCents: priceCents,
          description: _descriptionController.text.trim(),
        );
      } else {
        await api.updateMenuItem(
          widget.item!.id,
          name: _nameController.text.trim(),
          priceCents: priceCents,
          description: _descriptionController.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'บันทึกเมนูไม่สำเร็จ ลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.item == null ? 'เพิ่มเมนู' : 'แก้ไขเมนู', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'ชื่อเมนู'),
              validator: (v) => (v == null || v.isEmpty) ? 'กรุณากรอกชื่อเมนู' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceController,
              decoration: const InputDecoration(labelText: 'ราคา (บาท)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final parsed = double.tryParse(v ?? '');
                return (parsed == null || parsed <= 0) ? 'กรุณากรอกราคาที่ถูกต้อง' : null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'รายละเอียด (ไม่บังคับ)'),
              maxLines: 2,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }
}
