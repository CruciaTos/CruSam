import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:crusam/features/society/core/society_context.dart';
import 'package:crusam/features/society/data/models/society_models.dart';

class SocietyPicker extends StatefulWidget {
  const SocietyPicker({super.key});

  @override
  State<SocietyPicker> createState() => _SocietyPickerState();
}

class _SocietyPickerState extends State<SocietyPicker> {
  @override
  void initState() {
    super.initState();
    SocietyContext.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SocietyContext.instance,
      builder: (context, _) {
        final ctx = SocietyContext.instance;
        final screenWidth = MediaQuery.of(context).size.width;
        final isWide = screenWidth >= 1100;

        if (ctx.societies.isEmpty && !ctx.loading) {
          if (!isWide) {
            return IconButton(
              icon: const Icon(Icons.add_business_outlined, size: 20, color: Color(0xFF94A3B8)),
              tooltip: 'Add society',
              onPressed: () => context.go('/society/societies/new'),
            );
          }
          return InkWell(
            onTap: () => context.go('/society/societies/new'),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 240,
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.add, size: 16, color: Color(0xFF38BDF8)),
                  SizedBox(width: 8),
                  Text(
                    'Add society',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF38BDF8)),
                  ),
                ],
              ),
            ),
          );
        }

        final currentLabel = ctx.allSocieties
            ? 'All societies'
            : (ctx.society?.name ?? (ctx.societies.isNotEmpty ? ctx.societies.first.name : 'No society selected'));

        if (!isWide) {
          return IconButton(
            icon: const Icon(Icons.apartment_outlined, size: 20, color: Color(0xFF94A3B8)),
            tooltip: currentLabel,
            onPressed: () => _showPickerMenu(context, ctx),
          );
        }

        return InkWell(
          onTap: () => _showPickerMenu(context, ctx),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 240,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              children: [
                const Icon(Icons.apartment_outlined, size: 16, color: Color(0xFF94A3B8)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    currentLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFF8FAFC),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (ctx.financialYear != null && !ctx.allSocieties) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      ctx.financialYear!.code,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                const Icon(Icons.unfold_more, size: 16, color: Color(0xFF64748B)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPickerMenu(BuildContext context, SocietyContext ctx) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => _SocietyPickerDialog(ctx: ctx),
    );
  }
}

class _SocietyPickerDialog extends StatefulWidget {
  final SocietyContext ctx;
  const _SocietyPickerDialog({required this.ctx});

  @override
  State<_SocietyPickerDialog> createState() => _SocietyPickerDialogState();
}

class _SocietyPickerDialogState extends State<_SocietyPickerDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeSocieties = widget.ctx.societies.where((s) => s.isActive).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final filtered = _filter.isEmpty
        ? activeSocieties
        : activeSocieties
            .where((s) => s.name.toLowerCase().contains(_filter.toLowerCase()) ||
                (s.city?.toLowerCase().contains(_filter.toLowerCase()) ?? false))
            .toList();

    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340, maxHeight: 450),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 13, color: Color(0xFFF8FAFC)),
                decoration: InputDecoration(
                  hintText: 'Search societies...',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                ),
                onChanged: (val) => setState(() => _filter = val),
              ),
              const SizedBox(height: 8),
              ListTile(
                dense: true,
                leading: const Icon(Icons.apps, size: 18, color: Color(0xFF94A3B8)),
                title: const Text('All societies', style: TextStyle(fontSize: 13, color: Color(0xFFF8FAFC))),
                selected: widget.ctx.allSocieties,
                selectedTileColor: const Color(0x261E3A8A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.ctx.selectAllSocieties();
                },
              ),
              const Divider(color: Color(0xFF334155), height: 12),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, idx) {
                    final soc = filtered[idx];
                    final isSelected = !widget.ctx.allSocieties && widget.ctx.societyId == soc.id;
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.apartment, size: 18, color: Color(0xFF94A3B8)),
                      title: Text(
                        soc.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFFF8FAFC),
                        ),
                      ),
                      subtitle: soc.city != null
                          ? Text(soc.city!, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)))
                          : null,
                      selected: isSelected,
                      selectedTileColor: const Color(0x261E3A8A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.ctx.selectSociety(soc.id);
                      },
                    );
                  },
                ),
              ),
              const Divider(color: Color(0xFF334155), height: 12),
              ListTile(
                dense: true,
                leading: const Icon(Icons.settings_outlined, size: 18, color: Color(0xFF94A3B8)),
                title: const Text('Manage societies', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                onTap: () {
                  Navigator.of(context).pop();
                  context.go('/society/societies');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
