# Glass UI refresh

The user supplied four desktop/mobile light/dark visual references on 2026-11-08 and requested this appearance. Their newer preference replaces the initial PRD restrictions on glass, gradients, card radius, and shadows. Financial calculations, backend schema, permissions, and stored financial data are unchanged.

The new system uses a navy/ice-blue backdrop with curved glass ribbons, translucent blurred panels with highlight borders, blue accent controls, 20–26 px card radii, and a consistent Inter type hierarchy. Background curves and the balance-card wave are painted in Flutter and adapt to available space. Shared backdrop grouping and a repaint boundary keep decorative work separate from foreground content. No new image downloads or external asset services are required.

Desktop has a floating glass sidebar, period pill and circular toolbar actions. Mobile keeps the drawer and a round primary action; there is no bottom navigation. The dashboard includes balance visibility, horizontally scrollable accounts linked to filtered transactions, income/expense/net metrics, an actual/projected chart with an expense toggle, budget usage, recent transactions, and split-aware category distribution. Values and projections use the existing calculation paths; reference-image numbers and example banks are not seeded into user data.

The same palette, corners, fields, dialogs, and panel treatment extend to authentication and all existing management screens. Existing saved dashboard order/visibility remains usable; new account/category sections are inserted into the existing ordering.

Verification: static analysis, existing unit tests, responsive widget regressions and rendered previews at 360/768/1366 logical pixels in light and dark. The responsive test also exercises balance visibility and chart selection. Device rendering/performance is not represented as measured from widget tests.

Preview files: `test/previews/dashboard-{360,768,1366}-{light,dark}.png`.

## Published build

[Build 15](https://github.com/alids522/financegpt/actions/runs/42486905453) passed formatting, static analysis, all 22 tests, Android release compilation and Web release compilation. [Download the release](https://github.com/alids522/financegpt/releases/tag/v1.0.0-build.15).

The downloaded Android artifact matches both its checksum manifest and the GitHub release digest: `5847925309716c7990517afaae9807bab00317c82dfd547a0a9887f69b6cc7ef`. Its verified signing certificate is identical to build 14, with package `id.financegpt.finance_tracker` and version code 15. No signing-key change is required to install this update.
