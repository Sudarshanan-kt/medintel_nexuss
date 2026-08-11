import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:medintel_nexus/app/router/route_names.dart';
import 'package:medintel_nexus/features/dashboard/presentation/app_shell.dart';
import 'package:medintel_nexus/features/push/application/push_controller.dart';
import 'package:medintel_nexus/features/reminders/reminders_controller.dart';
import 'package:medintel_nexus/l10n/generated/app_localizations.dart';

class _FakeRemindersController extends RemindersController {
  @override
  MedicineManagerState build() => const MedicineManagerState();
}

class _FakePushController extends PushController {
  @override
  void build() {}
}

/// The five branches of the real shell, with placeholder screens — this is
/// about what the back gesture does to the shell, not what the tabs render.
///
/// The body text is deliberately not the tab's own label: the bottom bar
/// renders those too, and a finder would match both.
GoRouter _buildRouter() {
  StatefulShellBranch branch(String path, String label) {
    return StatefulShellBranch(
      routes: [
        GoRoute(
          path: path,
          builder: (_, __) => Scaffold(body: Center(child: Text('$label!'))),
          routes: [
            GoRoute(
              path: 'detail',
              builder: (_, __) =>
                  Scaffold(body: Center(child: Text('$label detail!'))),
            ),
          ],
        ),
      ],
    );
  }

  return GoRouter(
    initialLocation: Routes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, __, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          branch(Routes.home, 'Home'),
          branch(Routes.assistant, 'Assistant'),
          branch(Routes.scan, 'Scan'),
          branch(Routes.reports, 'Reports'),
          branch(Routes.profile, 'Profile'),
        ],
      ),
    ],
  );
}

/// Whatever Android's back gesture would do here — the platform sends
/// `popRoute` and the app either handles it or is closed.
Future<bool> _systemBack(WidgetTester tester) async {
  var handled = false;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec()
        .encodeMethodCall(const MethodCall('popRoute')),
    (data) {
      if (data != null) {
        handled = const JSONMethodCodec().decodeEnvelope(data) as bool? ?? false;
      }
    },
  );
  await tester.pumpAndSettle();
  return handled;
}

Future<GoRouter> _pumpShell(WidgetTester tester) async {
  // A phone-sized surface, so the shell renders its compact layout with the
  // bottom bar rather than the tablet side rail.
  tester.view.physicalSize = const Size(400, 840);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = _buildRouter();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        remindersControllerProvider.overrideWith(_FakeRemindersController.new),
        pushControllerProvider.overrideWith(_FakePushController.new),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('back from another tab returns to Home instead of exiting',
      (tester) async {
    final router = await _pumpShell(tester);

    router.go(Routes.reports);
    await tester.pumpAndSettle();
    expect(find.text('Reports!'), findsOneWidget);

    final handled = await _systemBack(tester);

    // Handled here means "the app dealt with it" — an unhandled popRoute is
    // exactly what closes the app.
    expect(handled, isTrue);
    expect(find.text('Home!'), findsOneWidget);
    expect(find.text('Reports!'), findsNothing);
  });

  testWidgets('back on Home is allowed to leave the app', (tester) async {
    await _pumpShell(tester);
    expect(find.text('Home!'), findsOneWidget);

    // Nothing left to go back to, so the shell must not swallow this — if it
    // did, the app could never be closed with the back gesture.
    expect(await _systemBack(tester), isFalse);
  });

  testWidgets('back from a pushed screen returns to the tab it came from',
      (tester) async {
    final router = await _pumpShell(tester);

    router.go(Routes.reports);
    await tester.pumpAndSettle();
    unawaited(router.push('${Routes.reports}/detail'));
    await tester.pumpAndSettle();
    expect(find.text('Reports detail!'), findsOneWidget);

    expect(await _systemBack(tester), isTrue);

    // The pushed screen pops; the shell's own handling stays out of the way
    // until the branch really has nothing left.
    expect(find.text('Reports!'), findsOneWidget);
    expect(find.text('Reports detail!'), findsNothing);
  });
}
