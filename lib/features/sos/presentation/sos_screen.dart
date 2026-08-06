import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../profile/application/profile_controller.dart';
import '../../profile/domain/profile_record.dart';
import '../application/sos_controller.dart';
import '../domain/emergency_event.dart';
import 'sos_countdown_dialog.dart';

/// Complete Emergency SOS Screen
class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key});

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> {
  static const _red = Color(0xFFDC2626);
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _green = Color(0xFF16A34A);
  static const _primary = Color(0xFF2563EB);

  late final TextEditingController _msgCtrl;
  bool? _hasAutoDispatchPermissions;

  @override
  void initState() {
    super.initState();
    final currentMsg = ref.read(sosControllerProvider).customMessage;
    _msgCtrl = TextEditingController(text: currentMsg);
    _checkAutoDispatchPermissions();
  }

  Future<void> _checkAutoDispatchPermissions() async {
    final granted = await ref
        .read(sosControllerProvider.notifier)
        .hasAutomaticDispatchPermissions();
    if (mounted) setState(() => _hasAutoDispatchPermissions = granted);
  }

  Future<void> _requestAutoDispatchPermissions() async {
    final granted = await ref
        .read(sosControllerProvider.notifier)
        .requestAutomaticDispatchPermissions();
    if (mounted) setState(() => _hasAutoDispatchPermissions = granted);
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sosState = ref.watch(sosControllerProvider);
    final profile = ref.watch(profileControllerProvider);
    final contacts = profile.emergencyContacts;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.home),
        ),
        title: const Text(
          'Emergency SOS',
          style: TextStyle(fontWeight: FontWeight.w800, color: _red),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          // ── Big Red SOS Trigger Card ───────────────────────────────────────
          _buildSosTriggerCard(context),
          const SizedBox(height: 24),

          // ── Automatic dispatch permission banner ────────────────────────────
          if (_hasAutoDispatchPermissions == false) _buildAutoDispatchBanner(),
          if (_hasAutoDispatchPermissions == false) const SizedBox(height: 24),

          // ── Emergency Contacts Section ─────────────────────────────────────
          _buildSectionHeader(
            'EMERGENCY CONTACTS (${contacts.length})',
            actionLabel: '+ Add Contact',
            onAction: () => _openContactEditor(context),
          ),
          const SizedBox(height: 8),

          if (contacts.isEmpty)
            _buildEmptyContactsCard(context)
          else
            Column(
              children: [
                for (final c in contacts)
                  _buildContactTile(c, sosState.customMessage),
              ],
            ),

          const SizedBox(height: 24),

          // ── Emergency Message Configuration ──────────────────────────────
          _buildSectionHeader('PREDEFINED EMERGENCY MESSAGE'),
          const SizedBox(height: 8),
          _buildMessageCard(),

          const SizedBox(height: 24),

          // ── SOS Event History ─────────────────────────────────────────────
          _buildSectionHeader('RECENT SOS ALERTS (${sosState.events.length})'),
          const SizedBox(height: 8),
          if (sosState.events.isEmpty)
            const Card(
              elevation: 0,
              color: Colors.white,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No emergency alerts triggered yet.',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
              ),
            )
          else
            Column(
              children: [
                for (final ev in sosState.events) _buildEventHistoryTile(ev),
              ],
            ),
        ],
      ),
    );
  }

  // ── Automatic dispatch permission banner ────────────────────────────────────

  Widget _buildAutoDispatchBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3E2),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.bolt_rounded,
                color: Color(0xFFF59E0B),
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Enable automatic calling & SMS',
                  style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Without this, SOS opens the dialer/SMS app pre-filled and you '
            'tap send yourself. With it, triggering SOS calls and texts your '
            'contacts with no taps needed.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _requestAutoDispatchPermissions,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
              ),
              child: const Text('Grant permissions'),
            ),
          ),
        ],
      ),
    );
  }

  // ── SOS Trigger Card ───────────────────────────────────────────────────────

  Widget _buildSosTriggerCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFCA5A5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1FDC2626),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'IN AN EMERGENCY',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _red,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap the SOS button to start a 3-second countdown. It will automatically call your primary contact and text your GPS location to all emergency contacts.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _ink, height: 1.4),
          ),
          const SizedBox(height: 20),

          // Big Glowing Red Button
          GestureDetector(
            onTap: () => SosCountdownDialog.show(context),
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                color: _red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _red.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.touch_app_rounded, size: 40, color: Colors.white),
                  SizedBox(height: 4),
                  Text(
                    'SOS',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Contact List & Actions ─────────────────────────────────────────────────

  Widget _buildEmptyContactsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_add_outlined, color: _muted, size: 32),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'No emergency contacts added yet. Add family or doctor contacts.',
              style: TextStyle(fontSize: 13, color: _muted),
            ),
          ),
          TextButton(
            onPressed: () => _openContactEditor(context),
            child: const Text('Add Contact'),
          ),
        ],
      ),
    );
  }

  Widget _buildContactTile(EmergencyContact c, String customMsg) {
    final notifier = ref.read(sosControllerProvider.notifier);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              c.isPrimary ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0),
          width: c.isPrimary ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: c.isPrimary
                    ? const Color(0xFFEFF6FF)
                    : const Color(0xFFF1F5F9),
                child: Text(
                  c.name.isNotEmpty ? c.name[0].toUpperCase() : 'C',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: c.isPrimary ? _primary : _ink,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          c.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                          ),
                        ),
                        if (c.isPrimary) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDBEAFE),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'PRIMARY',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: _primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${c.relation.isEmpty ? "Contact" : c.relation} · ${c.phone}',
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: _muted),
                onSelected: (val) {
                  if (val == 'primary') {
                    _setPrimaryContact(c);
                  } else if (val == 'edit') {
                    _openContactEditor(context, existing: c);
                  } else if (val == 'delete') {
                    ref
                        .read(profileControllerProvider.notifier)
                        .removeEmergencyContact(c.id);
                  }
                },
                itemBuilder: (_) => [
                  if (!c.isPrimary)
                    const PopupMenuItem(
                      value: 'primary',
                      child: Text('Set as Primary Contact'),
                    ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit Contact'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: _red)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Action buttons: Call, SMS, WhatsApp
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => notifier.makePhoneCall(c.phone),
                  icon:
                      const Icon(Icons.call_rounded, size: 16, color: _primary),
                  label: const Text(
                    'Call',
                    style: TextStyle(fontSize: 12, color: _primary),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => notifier.sendSms(
                    c.phone,
                    customMsg.isNotEmpty ? customMsg : 'EMERGENCY: Need help!',
                  ),
                  icon:
                      const Icon(Icons.sms_rounded, size: 16, color: _primary),
                  label: const Text(
                    'SMS',
                    style: TextStyle(fontSize: 12, color: _primary),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => notifier.openWhatsApp(
                    c.phone,
                    customMsg.isNotEmpty ? customMsg : 'EMERGENCY: Need help!',
                  ),
                  icon: const Icon(Icons.chat_rounded, size: 16, color: _green),
                  label: const Text(
                    'WhatsApp',
                    style: TextStyle(fontSize: 12, color: _green),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF86EFAC)),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _setPrimaryContact(EmergencyContact target) {
    final profile = ref.read(profileControllerProvider);
    final updated = profile.emergencyContacts.map((c) {
      return c.copyWith(isPrimary: c.id == target.id);
    }).toList();

    for (final c in updated) {
      ref.read(profileControllerProvider.notifier).updateEmergencyContact(c);
    }
  }

  // ── Predefined Emergency Message Card ─────────────────────────────────────

  Widget _buildMessageCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _msgCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'e.g. EMERGENCY: Need immediate medical help!',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {
                ref
                    .read(sosControllerProvider.notifier)
                    .setCustomMessage(_msgCtrl.text);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Emergency message updated.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Text('Save Message'),
            ),
          ),
        ],
      ),
    );
  }

  // ── History Tile ──────────────────────────────────────────────────────────

  Widget _buildEventHistoryTile(EmergencyEvent ev) {
    final dateStr = DateFormat.yMMMd().add_jm().format(ev.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _red, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SOS to ${ev.primaryContactName}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                Text(
                  '$dateStr${ev.hasLocation ? " · GPS Attached" : ""}',
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: _muted, size: 20),
            onPressed: () {
              ref.read(sosControllerProvider.notifier).deleteEvent(ev.id);
            },
          ),
        ],
      ),
    );
  }

  // ── Section Header Widget ─────────────────────────────────────────────────

  Widget _buildSectionHeader(
    String title, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: _muted,
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel),
          ),
      ],
    );
  }

  // ── Contact Add/Edit Dialog ───────────────────────────────────────────────

  Future<void> _openContactEditor(
    BuildContext context, {
    EmergencyContact? existing,
  }) async {
    final nameCtl = TextEditingController(text: existing?.name ?? '');
    final relCtl = TextEditingController(text: existing?.relation ?? '');
    final phoneCtl = TextEditingController(text: existing?.phone ?? '');
    final waKeyCtl =
        TextEditingController(text: existing?.whatsappApiKey ?? '');
    bool isPrimary = existing?.isPrimary ?? false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(existing == null ? 'Add Contact' : 'Edit Contact'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: relCtl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Relationship'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneCtl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Primary Contact'),
                  value: isPrimary,
                  onChanged: (val) => setDlg(() => isPrimary = val ?? false),
                ),
                const Divider(height: 24),
                const Text(
                  'WhatsApp auto-send (optional)',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _ink,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'To have SOS message this contact on WhatsApp automatically: '
                  'from their phone, message +34 698 28 89 73 on WhatsApp with '
                  'exactly "I allow callmebot to send me messages", then paste '
                  'the API key it replies with below. Without a key, WhatsApp '
                  'opens pre-filled instead — still one tap to send.',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: waKeyCtl,
                  decoration:
                      const InputDecoration(labelText: 'CallMeBot API key'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (nameCtl.text.trim().isEmpty) return;
                final id = existing?.id ??
                    'contact_${DateTime.now().microsecondsSinceEpoch}';
                final waKey = waKeyCtl.text.trim();
                final contact = EmergencyContact(
                  id: id,
                  name: nameCtl.text.trim(),
                  relation: relCtl.text.trim(),
                  phone: phoneCtl.text.trim(),
                  isPrimary: isPrimary,
                  whatsappApiKey: waKey.isEmpty ? null : waKey,
                );

                if (existing == null) {
                  ref
                      .read(profileControllerProvider.notifier)
                      .addEmergencyContact(contact);
                } else {
                  ref
                      .read(profileControllerProvider.notifier)
                      .updateEmergencyContact(contact);
                }

                if (isPrimary) {
                  _setPrimaryContact(contact);
                }

                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    nameCtl.dispose();
    relCtl.dispose();
    phoneCtl.dispose();
    waKeyCtl.dispose();
  }
}
