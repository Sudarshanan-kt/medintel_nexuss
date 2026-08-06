import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/features/dashboard/application/dashboard_controller.dart';
import 'package:medintel_nexus/features/dashboard/presentation/health_timeline_screen.dart';
import 'package:medintel_nexus/features/vitals/presentation/health_insights_screen.dart';
import 'package:medintel_nexus/l10n/generated/app_localizations.dart';

const _emptyDashboard = DashboardState(
  scansCount: 0,
  reportsCount: 0,
  medicineCount: 0,
  riskAlertCount: 0,
  recentScans: [],
  recentReports: [],
  insights: [],
  signals: [],
);

Future<void> _pump(WidgetTester tester, Widget screen) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        dashboardStateProvider.overrideWithValue(_emptyDashboard),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
}

void main() {
  testWidgets(
      'HealthInsightsScreen renders its empty state without throwing',
      (tester) async {
    await _pump(tester, const HealthInsightsScreen());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(HealthInsightsScreen), findsOneWidget);
  });

  testWidgets(
      'HealthTimelineScreen renders its empty state without throwing',
      (tester) async {
    await _pump(tester, const HealthTimelineScreen());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final t = AppLocalizations.of(
      tester.element(find.byType(HealthTimelineScreen)),
    )!;
    expect(find.text(t.healthTimelineEmptyState), findsOneWidget);
  });
}
