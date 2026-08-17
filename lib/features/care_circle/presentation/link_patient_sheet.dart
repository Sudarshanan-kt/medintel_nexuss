import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/router/navigation.dart';
import '../../../app/router/route_names.dart';
import '../../../shared/widgets/widgets.dart';
import 'caregiver_theme.dart';

/// Lets a caregiver link a patient by typing the invite code they were given,
/// rather than only by following a `medintel://invite/<code>` link.
///
/// The link is the happy path and this is everything else: a code read off a
/// screen, over the phone, or written down — and a demo, where deep links
/// are the one thing that reliably does not work.
///
/// Deliberately thin. It collects six characters and hands them to
/// [Routes.inviteAccept], which already previews whose circle the code
/// belongs to and redeems it server-side; duplicating that here would mean
/// two places to keep correct.
Future<void> showLinkPatientSheet(BuildContext context) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => const _LinkPatientSheet(),
  );
}

class _LinkPatientSheet extends StatefulWidget {
  const _LinkPatientSheet();

  @override
  State<_LinkPatientSheet> createState() => _LinkPatientSheetState();
}

class _LinkPatientSheetState extends State<_LinkPatientSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Codes are generated as six characters; anything shorter is a typo
  /// rather than a code, and saying so here costs a round trip less than
  /// letting the lookup fail.
  void _submit() {
    final code = _controller.text.trim().toUpperCase();
    if (code.length < 6) {
      setState(() => _error = 'Invite codes are 6 characters.');
      return;
    }
    Navigator.of(context).pop();
    context.openScreen(Routes.inviteAcceptCode(code));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Link a patient',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kInk,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ask the person you look after to open Care Circle and share '
            'their invite code with you.',
            style: TextStyle(fontSize: 13.5, height: 1.45, color: kMuted),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.go,
            maxLength: 6,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            inputFormatters: [
              // The codes are alphanumeric and stored upper-case; folding
              // here means a lower-case typing and a stray space both still
              // find the invite.
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
              TextInputFormatter.withFunction(
                (_, next) => next.copyWith(text: next.text.toUpperCase()),
              ),
            ],
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 6,
              color: kInk,
            ),
            decoration: InputDecoration(
              hintText: 'A1B2C3',
              counterText: '',
              errorText: _error,
              hintStyle: TextStyle(
                letterSpacing: 6,
                color: kMuted.withValues(alpha: 0.5),
              ),
              filled: true,
              fillColor: kVioletSoft,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kViolet,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _submit,
              child: const Text(
                'Find this invite',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
