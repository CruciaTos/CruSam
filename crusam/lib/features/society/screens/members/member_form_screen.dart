import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/member_models.dart';
import '../../shared/widgets/society_page.dart';

class MemberFormScreen extends StatefulWidget {
  final int? personId;
  const MemberFormScreen({super.key, this.personId});

  @override
  State<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends State<MemberFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _altEmailController = TextEditingController();
  final _panController = TextEditingController();
  final _gstinController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isActive = true;

  bool _loading = true;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    if (widget.personId == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final services = await SocietyServices.instance();
      final p = await services.member.getPerson(widget.personId!);
      if (mounted && p != null) {
        setState(() {
          _nameController.text = p.fullName;
          _phoneController.text = p.phone ?? '';
          _emailController.text = p.email ?? '';
          _altEmailController.text = p.alternateEmail ?? '';
          _panController.text = p.pan ?? '';
          _gstinController.text = p.gstin ?? '';
          _addressController.text = p.address ?? '';
          _isActive = p.isActive;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() => _saving = true);

    try {
      final services = await SocietyServices.instance();
      final draft = PersonDraft(
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        alternateEmail: _altEmailController.text.trim().isEmpty ? null : _altEmailController.text.trim(),
        pan: _panController.text.trim().isEmpty ? null : _panController.text.trim().toUpperCase(),
        gstin: _gstinController.text.trim().isEmpty ? null : _gstinController.text.trim().toUpperCase(),
        address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        isActive: _isActive,
      );

      if (widget.personId == null) {
        await services.member.createPerson(societyId, draft);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Member "${draft.fullName}" created')),
          );
          context.pop();
        }
      } else {
        await services.member.updatePerson(societyId, widget.personId!, draft);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Member "${draft.fullName}" updated')),
          );
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.personId != null;

    return SocietyPage(
      title: isEdit ? 'Edit Member' : 'New Member',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              isEdit ? 'Update Member Profile' : 'Add Person / Member',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 20),

                            // Full Name
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(labelText: 'Full Name *'),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                            const SizedBox(height: 16),

                            // Phone & Email
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _phoneController,
                                    decoration: const InputDecoration(labelText: 'Phone Number'),
                                    keyboardType: TextInputType.phone,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: _emailController,
                                    decoration: const InputDecoration(labelText: 'Email Address'),
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Alternate Email
                            TextFormField(
                              controller: _altEmailController,
                              decoration: const InputDecoration(labelText: 'Alternate Email'),
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 16),

                            // PAN & GSTIN
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _panController,
                                    decoration: const InputDecoration(labelText: 'PAN Number'),
                                    textCapitalization: TextCapitalization.characters,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: _gstinController,
                                    decoration: const InputDecoration(labelText: 'GSTIN (if commercial)'),
                                    textCapitalization: TextCapitalization.characters,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Address
                            TextFormField(
                              controller: _addressController,
                              decoration: const InputDecoration(labelText: 'Permanent / Mailing Address'),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 16),

                            // Active
                            SwitchListTile(
                              title: const Text('Active'),
                              value: _isActive,
                              onChanged: (v) => setState(() => _isActive = v),
                            ),
                            const SizedBox(height: 24),

                            // Buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton(
                                  onPressed: _saving ? null : () => context.pop(),
                                  child: const Text('Cancel'),
                                ),
                                const SizedBox(width: 12),
                                FilledButton(
                                  onPressed: _saving ? null : _save,
                                  child: _saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Text('Save Member'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
