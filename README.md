# سير اعتماد المستندات — Document Approval Workflow

تطبيق Flutter لسير اعتماد المستندات، يتكامل مع Laravel API الموثّق في
`API_DOCUMENTATION.md`.

## Tech stack

- **Flutter 3.19+** / Dart 3.3+
- **Riverpod** (`flutter_riverpod`) — state management
- **Dio** — HTTP client with auth + error interceptors
- **go_router** — navigation with auth-guard redirect
- **flutter_secure_storage** — Keychain / EncryptedSharedPreferences for the bearer token
- **google_fonts** — Cairo loaded at runtime (no font assets required)
- **file_picker / open_filex / cached_network_image** — file selection & preview

## Visual identity

| Color    | Hex       | Use                              |
| -------- | --------- | -------------------------------- |
| Primary  | `#224067` | App bars, primary buttons        |
| Accent   | `#B36A8C` | FAB, "your turn" highlights      |
| Lavender | `#BC8CCC` | Tab indicator, soft accents      |
| Neutral  | `#D3D3D3` | Borders                          |
| White    | `#FFFFFF` | Surfaces                         |

Status colors are tasteful muted greens/reds (`#2E7D5B`, `#B3261E`) plus
the brand mauve for "pending".

The whole app is forced to **RTL** regardless of system locale.

## Project layout

```
lib/
├── main.dart                 # ProviderScope + MaterialApp.router + RTL
├── core/
│   ├── theme/                # Colors + Material 3 theme (Cairo)
│   ├── network/api_client.dart  # Dio + Bearer interceptor + 401 handler
│   ├── storage/token_storage.dart
│   ├── errors/api_failure.dart  # Typed error codes + Arabic messages
│   ├── router/app_router.dart   # go_router with auth guard
│   └── utils/app_constants.dart
├── features/
│   ├── auth/
│   │   ├── domain/user.dart
│   │   ├── data/auth_repository.dart
│   │   └── presentation/
│   │       ├── providers/auth_controller.dart
│   │       └── screens/login_screen.dart
│   └── documents/
│       ├── domain/document.dart       # Document, WorkflowStep, DocumentLog
│       ├── data/
│       │   ├── documents_repository.dart
│       │   └── users_repository.dart
│       └── presentation/
│           ├── providers/             # list + details state notifiers
│           ├── screens/               # home, details, create
│           └── widgets/               # stepper, list item, picker sheet
└── shared/widgets/                    # status chip, empty/error views
```

## Setup

```bash
flutter pub get
```

Set the API base URL at build/run time via a Dart define (defaults to
`https://api.yourcompany.com/api`):

```bash
flutter run --dart-define=API_BASE_URL=https://api.your-real-host.com/api
```

For a release build:

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.your-real-host.com/api
```

## Features delivered

- ✅ Login (email + password) with secure bearer-token storage
- ✅ Inbox / sent tabs with pull-to-refresh and infinite scroll
- ✅ Document details with file preview (image inline, others via system viewer)
- ✅ Sequential workflow rendered as a vertical stepper
- ✅ Parallel workflow rendered as a flat approver list
- ✅ Audit log with action-typed icons and Arabic labels
- ✅ "Is it my turn?" highlight + approve/reject actions with notes
  (rejection requires a note, approval is optional)
- ✅ Create document: title, description, file upload (PDF / DOC / DOCX /
  JPG / PNG / WEBP, ≤ 20 MB), workflow mode toggle, approver picker with
  reorderable list for sequential mode
- ✅ Forced logout on 401 with redirect to login
- ✅ Centralised error mapping → Arabic UX messages

## Known limitations / to follow up

1. **Login endpoint shape**: the API doc says auth endpoints "already
   exist" but doesn't specify the response. I assumed standard Sanctum:
   `POST /login` → `{ user, token }`. Adjust `AuthRepository.login` if
   your backend differs.

2. **Approver picker uses `/admin/users`**: the docs only expose admin
   endpoints for listing users, so managers will hit a `403` when
   choosing approvers. The picker handles this gracefully with an
   Arabic message. **Backend follow-up needed**: add a non-admin
   `GET /users` or `GET /approvers` endpoint that managers can call.

3. **Admin features deferred** per scope: department / section / user
   management screens are not included. The `User` model already carries
   `role`, so adding them later is straightforward.

4. **No PDF inline viewer** — PDFs and Word docs open via the system
   viewer (`open_filex`). Add `pdfx` / `flutter_pdfview` if you want
   in-app preview.

5. **No push notifications, no offline cache, no unit tests** in this
   first pass.

## Notes on the architecture

- **Riverpod is the source of truth** for auth state. `go_router` listens
  to a small `ChangeNotifier` adapter that bridges the Riverpod stream
  into the router's `refreshListenable`.
- **401 handling** uses a shared `UnauthenticatedSignal` so that the API
  client doesn't import the auth feature (no circular dependency). On
  any 401, storage is cleared and the signal fires; `AuthController`
  picks it up and the router redirects to `/login`.
- **List sync after approve/reject**: the details screen pushes the
  updated `Document` back into both the inbox and sent list states, so
  the home screen reflects new statuses without a full refresh.
