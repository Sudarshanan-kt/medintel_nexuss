# MedIntel Nexus — Flutter scaffold

Premium, enterprise-grade healthcare SaaS client for **MedIntel Nexus**, the AI-Powered Clinical Intelligence & Prescription Risk Analysis Platform.

This is the **runnable Flutter scaffold** that realises Phases 0–2 of the architecture blueprint (`../MedIntel_Nexus_Architecture_Blueprint.md`) and stubs Phases 3–5 screens against the real theme, router and widget kit.

## What's inside

```
lib/
├── main.dart                 # zone-guarded entrypoint
├── app/
│   ├── app.dart              # MaterialApp.router, theme, i18n
│   └── router/               # GoRouter + typed route names + auth guard
├── core/
│   ├── constants/            # app + breakpoints + asset paths
│   ├── theme/                # colours, typography, spacing, shadows, ThemeData
│   ├── network/              # Dio client + endpoints
│   ├── errors/               # Failure sealed type + exceptions
│   └── utils/                # Result, validators, responsive extensions
├── shared/widgets/           # the design-system kit (17 widgets)
└── features/                 # vertical slices (presentation/application/domain/data)
    ├── splash/   auth/   dashboard/   scan/   assistant/   reports/   profile/
```

Every layer follows the dependency rule **presentation → application → domain ← data**. `domain` files never import Flutter.

## Running it

```bash
flutter pub get
flutter run            # mobile
flutter run -d chrome  # web dashboard mode (responsive shell flips to side nav)
```

The auth flow accepts **any 6-digit OTP** in demo mode (`AuthRepositoryImpl`). Swap the bodies for real Dio calls against `ApiEndpoints` for production — the interface, the controller and every screen stay untouched.

## Where to look first

- **Theme system** — `lib/core/theme/`. Every colour, type style, spacing value and shadow is a token. No hex values in widgets, ever.
- **Design-system kit** — `lib/shared/widgets/widgets.dart`. Feature screens are assembled almost entirely from this kit.
- **Routing** — `lib/app/router/app_router.dart`. Auth-aware redirect, shared-axis and fade-through transitions, persistent shell.
- **Hero screens** — `features/dashboard/presentation/home_dashboard_screen.dart`, `features/scan/presentation/scan_result_screen.dart`, `features/assistant/presentation/assistant_screen.dart`.

## Code conventions

- One public widget per file; file name = snake_case of the class.
- Screens end in `_screen.dart`; reusable widgets do not.
- Providers live in `application/` and are named `<thing>Provider`.
- Barrel files are permitted only in `shared/`.
- Risk information is **never conveyed by colour alone** — every risk state pairs colour with an icon and a text label.

## Next steps (Phases 3–7)

The companion blueprint covers the full roadmap; the obvious next moves:

1. Wire the real backend behind `AuthRepositoryImpl`, then build `prescription_repository.dart` and `report_repository.dart` against `ApiEndpoints`.
2. Plug `camera` and on-device edge detection into `ScannerScreen`.
3. Add the offline sync engine described in §15 of the blueprint.
4. Build the clinic web shell — the `AppShell` already swaps in a side rail on `expanded`; the clinic slice (`features/clinic/`) plugs in there.
