# Document Approval Workflow — Mobile API Documentation

**Version:** 1.0
**Base URL:** `https://api.yourcompany.com/api`
**Auth:** Laravel Sanctum (Bearer token)

---

## Table of Contents

1. [General Conventions](#1-general-conventions)
2. [Authentication](#2-authentication)
3. [Error Format](#3-error-format)
4. [Roles & Permissions](#4-roles--permissions)
5. [Documents API](#5-documents-api)
6. [Workflow Actions API](#6-workflow-actions-api)
7. [Admin — Users API](#7-admin--users-api)
8. [Admin — Departments API](#8-admin--departments-api)
9. [Admin — Sections API](#9-admin--sections-api)
10. [Status & Enum Reference](#10-status--enum-reference)
11. [Mobile Implementation Notes](#11-mobile-implementation-notes)

---

## 1. General Conventions

| Item         | Value                                                     |
| ------------ | --------------------------------------------------------- |
| Protocol     | HTTPS only                                                |
| Format       | JSON for requests and responses                           |
| File uploads | `multipart/form-data`                                     |
| Date format  | ISO 8601 UTC (`2026-05-02T10:14:22.000000Z`)              |
| Pagination   | Laravel-style: `{ data, current_page, last_page, total }` |

### Required headers on every request

```
Authorization: Bearer {token}
Accept: application/json
Content-Type: application/json
```

For file uploads, replace `Content-Type` with `multipart/form-data` (most HTTP libraries set this automatically).

---

## 2. Authentication

> Auth endpoints (login/logout) are assumed to already exist on the backend. The mobile app receives a Bearer token after login, stores it securely (Keychain on iOS, EncryptedSharedPreferences on Android), and attaches it to every request.

If the token is missing or invalid:

```json
HTTP 401
{ "message": "Unauthenticated.", "error": "unauthenticated" }
```

When this happens, redirect the user to the login screen and clear the stored token.

---

## 3. Error Format

All errors share the same shape:

```json
{
  "message": "Human-readable message",
  "error":   "machine_readable_code",
  "errors":  { "field": ["validation message"] }   // only on 422
}
```

### Error codes the mobile app should handle

| HTTP | `error` code                 | Meaning                    | Suggested UX                         |
| ---- | ---------------------------- | -------------------------- | ------------------------------------ |
| 401  | `unauthenticated`            | Token missing/expired      | Force logout                         |
| 403  | `forbidden`                  | Not allowed by policy      | Show "no permission" message         |
| 403  | `not_your_turn`              | Sequential workflow — wait | Show "waiting for previous approver" |
| 404  | `not_found`                  | Resource doesn't exist     | Go back to list                      |
| 404  | `no_pending_action`          | User has nothing to act on | Refresh inbox                        |
| 404  | `route_not_found`            | Wrong URL                  | Likely a bug — log it                |
| 409  | `document_already_finalized` | Already approved/rejected  | Refresh document                     |
| 422  | `validation_failed`          | Form errors                | Show field errors inline             |
| 422  | `invalid_workflow`           | Bad workflow setup         | Show in alert                        |
| 500  | `server_error`               | Backend bug                | Generic "try again" message          |

---

## 4. Roles & Permissions

| Role      | Can do                                                       |
| --------- | ------------------------------------------------------------ |
| `manager` | Create documents, view inbox/sent, approve/reject when it's their turn |
| `admin`   | Everything a manager can + manage users, departments, sections, view all documents |

The current user's role comes back in the login response. Use it to show/hide the admin section in your UI.

---

## 5. Documents API

### 5.1 List documents (inbox or sent)

```
GET /documents?type={inbox|sent}&page=1
```

| Query param | Type   | Notes                                                       |
| ----------- | ------ | ----------------------------------------------------------- |
| `type`      | string | `inbox` (default) — assigned to me. `sent` — created by me. |
| `page`      | int    | Pagination                                                  |

**Response — `200 OK`**

```json
{
  "type": "inbox",
  "documents": {
    "current_page": 1,
    "last_page": 4,
    "per_page": 15,
    "total": 52,
    "data": [
      {
        "id": 17,
        "title": "Q1 Vendor Contract",
        "description": "Annual renewal for ACME supplies",
        "file_path": "documents/abc123.pdf",
        "file_name": "contract.pdf",
        "file_mime": "application/pdf",
        "file_size": 482910,
        "status": "pending",
        "workflow_mode": "sequential",
        "created_by": 2,
        "created_at": "2026-05-02T10:14:22.000000Z",
        "creator": { "id": 2, "name": "Ali Rashid", "email": "ali@company.com" },
        "workflows": [
          { "id": 41, "user_id": 5,  "order": 1, "status": "approved",
            "user": { "id": 5, "name": "Layla Hassan" } },
          { "id": 42, "user_id": 8,  "order": 2, "status": "pending",
            "user": { "id": 8, "name": "Omar Tahir" } }
        ]
      }
    ]
  }
}
```

### 5.2 Get document details

```
GET /documents/{id}
```

**Response — `200 OK`**

```json
{
  "document": {
    "id": 17,
    "title": "Q1 Vendor Contract",
    "description": "Annual renewal for ACME supplies",
    "file_path": "documents/abc123.pdf",
    "file_name": "contract.pdf",
    "file_mime": "application/pdf",
    "file_size": 482910,
    "status": "pending",
    "workflow_mode": "sequential",
    "creator": { "id": 2, "name": "Ali Rashid", "email": "ali@company.com" },
    "workflows": [
      { "id": 41, "user_id": 5, "order": 1, "status": "approved",
        "signed_at": "2026-05-02T11:02:00.000000Z", "note": "Looks good",
        "user": { "id": 5, "name": "Layla Hassan", "email": "layla@company.com" } },
      { "id": 42, "user_id": 8, "order": 2, "status": "pending",
        "signed_at": null, "note": null,
        "user": { "id": 8, "name": "Omar Tahir", "email": "omar@company.com" } }
    ],
    "logs": [
      { "id": 72, "action": "sent",     "done_by": 2, "note": null,
        "created_at": "2026-05-02T10:14:22.000000Z",
        "user": { "id": 2, "name": "Ali Rashid" } },
      { "id": 71, "action": "created",  "done_by": 2, "note": null,
        "created_at": "2026-05-02T10:14:22.000000Z",
        "user": { "id": 2, "name": "Ali Rashid" } },
      { "id": 73, "action": "approved", "done_by": 5, "note": "Looks good",
        "created_at": "2026-05-02T11:02:00.000000Z",
        "user": { "id": 5, "name": "Layla Hassan" } }
    ]
  },
  "next_pending_users": [
    { "id": 8, "name": "Omar Tahir", "email": "omar@company.com" }
  ]
}
```

> `next_pending_users` tells you who needs to act next. If the current user's ID is in this list, show the **Approve / Reject** buttons.

### 5.3 Create a document

```
POST /documents
Content-Type: multipart/form-data
```

**Body**

| Field            | Type   | Required | Notes                                               |
| ---------------- | ------ | -------- | --------------------------------------------------- |
| `title`          | string | yes      | Max 255 chars                                       |
| `description`    | string | no       | Free text                                           |
| `file`           | file   | yes      | PDF, DOC, DOCX, JPG, PNG, WEBP — max 20 MB          |
| `workflow_mode`  | string | yes      | `sequential` or `parallel`                          |
| `approver_ids[]` | int[]  | yes      | At least one. **Order matters in sequential mode.** |

**Response — `201 Created`**

```json
{
  "message": "Document created and sent for approval.",
  "document": {
    "id": 17,
    "title": "Q1 Vendor Contract",
    "status": "pending",
    "workflow_mode": "sequential",
    "workflows": [ /* ... */ ],
    "logs": [ /* created + sent */ ]
  }
}
```

### 5.4 Download / view file

The `file_path` returned is a relative storage path. Construct the URL like:

```
{BASE_URL_WITHOUT_/api}/storage/{file_path}
```

Or if you implement a signed-URL endpoint later, swap to that. For images (`file_mime` starts with `image/`), render inline. For PDFs/Word, open externally or in a webview.

---

## 6. Workflow Actions API

### 6.1 Approve a document

```
POST /documents/{id}/approve
```

**Body**

```json
{ "note": "Reviewed and confirmed pricing." }
```

`note` is optional.

**Response — `200 OK`**

```json
{
  "message": "Document approved.",
  "document": { /* full updated document object */ }
}
```

> If the user was the **last** required approver, `document.status` will flip to `"approved"`. Otherwise it stays `"pending"` and the next user is shown in `next_pending_users`.

### 6.2 Reject a document

```
POST /documents/{id}/reject
```

**Body**

```json
{ "note": "Pricing exceeds approved budget." }
```

**Response — `200 OK`**

```json
{
  "message": "Document rejected.",
  "document": { /* status will be "rejected" */ }
}
```

> A single rejection terminates the workflow. The document is final.

### 6.3 Common errors on approve/reject

| HTTP | Code                         | When                                            |
| ---- | ---------------------------- | ----------------------------------------------- |
| 403  | `not_your_turn`              | Sequential — earlier approvers haven't finished |
| 403  | `forbidden`                  | User isn't an approver on this document at all  |
| 404  | `no_pending_action`          | User already acted, or was never assigned       |
| 409  | `document_already_finalized` | Already approved or rejected by the workflow    |

---

## 7. Admin — Users API

> All `/admin/*` endpoints require `role: admin`. Returns `403 forbidden` otherwise.

### 7.1 List users

```
GET /admin/users?role=manager&department_id=3&search=layla&page=1
```

All query params are optional.

**Response — `200 OK`**

```json
{
  "users": {
    "current_page": 1,
    "data": [
      {
        "id": 24,
        "name": "Layla Hassan",
        "email": "layla@company.com",
        "role": "manager",
        "department_id": 3,
        "section_id": 7,
        "department": { "id": 3, "name": "Operations" },
        "section":    { "id": 7, "name": "Procurement" },
        "created_at": "2026-04-15T08:00:00.000000Z"
      }
    ],
    "total": 1
  }
}
```

### 7.2 Get a user

```
GET /admin/users/{id}
```

### 7.3 Create a user

```
POST /admin/users
```

**Body**

```json
{
  "name": "Layla Hassan",
  "email": "layla@company.com",
  "password": "Sup3rSecret!",
  "password_confirmation": "Sup3rSecret!",
  "role": "manager",
  "department_id": 3,
  "section_id": 7
}
```

| Field                                | Required | Notes                                |
| ------------------------------------ | -------- | ------------------------------------ |
| `name`                               | yes      | Max 255                              |
| `email`                              | yes      | Unique                               |
| `password` + `password_confirmation` | yes      | Default Laravel password rules       |
| `role`                               | yes      | `admin` or `manager`                 |
| `department_id`                      | no       | Must exist if provided               |
| `section_id`                         | no       | Must belong to the chosen department |

**Response — `201 Created`** — returns the new user object.

### 7.4 Update a user

```
PATCH /admin/users/{id}
```

Body is the same as create, but every field is optional. Send only what changes.

### 7.5 Delete a user (soft delete)

```
DELETE /admin/users/{id}
```

Returns `422` if the admin tries to delete their own account.

---

## 8. Admin — Departments API

### 8.1 List

```
GET /admin/departments?search=ops&page=1
```

```json
{
  "departments": {
    "data": [
      { "id": 3, "name": "Operations", "code": "OPS",
        "sections_count": 4, "users_count": 22 }
    ]
  }
}
```

### 8.2 Get one

```
GET /admin/departments/{id}
```

Returns the department with its sections and users included.

### 8.3 Create

```
POST /admin/departments
```

```json
{ "name": "Operations", "code": "OPS" }
```

`code` must be unique.

### 8.4 Update

```
PATCH /admin/departments/{id}
```

Same body, all optional.

### 8.5 Delete

```
DELETE /admin/departments/{id}
```

Returns `422` if the department still has sections or users attached. Reassign or remove them first.

---

## 9. Admin — Sections API

### 9.1 List

```
GET /admin/sections?department_id=3&search=proc&page=1
```

```json
{
  "sections": {
    "data": [
      { "id": 7, "department_id": 3, "name": "Procurement",
        "users_count": 5,
        "department": { "id": 3, "name": "Operations", "code": "OPS" } }
    ]
  }
}
```

### 9.2 Get one

```
GET /admin/sections/{id}
```

### 9.3 Create

```
POST /admin/sections
```

```json
{ "department_id": 3, "name": "Procurement" }
```

### 9.4 Update

```
PATCH /admin/sections/{id}
```

### 9.5 Delete

```
DELETE /admin/sections/{id}
```

Returns `422` if any users are still assigned.

---

## 10. Status & Enum Reference

### Document status

| Value      | Meaning                                   |
| ---------- | ----------------------------------------- |
| `pending`  | In the workflow, waiting on approver(s)   |
| `approved` | All approvers signed                      |
| `rejected` | At least one approver rejected — terminal |

### Workflow step status

| Value      | Meaning                                      |
| ---------- | -------------------------------------------- |
| `pending`  | Waiting on this user                         |
| `approved` | This user approved                           |
| `rejected` | This user rejected (terminates the document) |

### Workflow mode

| Value        | Meaning                                        |
| ------------ | ---------------------------------------------- |
| `sequential` | Approvers act in order (`order` field matters) |
| `parallel`   | All approvers can act at the same time         |

### Log actions

| Value      | When                             |
| ---------- | -------------------------------- |
| `created`  | Document was first created       |
| `sent`     | Document dispatched to approvers |
| `approved` | An approver approved their step  |
| `rejected` | An approver rejected             |

### User roles

| Value     | Meaning            |
| --------- | ------------------ |
| `admin`   | Full system access |
| `manager` | Documents only     |

---

## 11. Mobile Implementation Notes

### Detecting "is it my turn?"

Don't rely on `document.status === 'pending'` alone. Instead:

```
isMyTurn = document.next_pending_users.some(u => u.id === currentUser.id)
```

If `isMyTurn` is true, show the Approve/Reject buttons. Otherwise show a read-only view.

### Inbox badge count

Count unfinished documents the user must act on:

```
GET /documents?type=inbox
```

Then filter client-side where `next_pending_users` contains the current user. If you need a server-side count later, ask backend to add `?action_required=true`.

### Optimistic UI for approve/reject

Both endpoints return the **full updated document**. After a successful response, replace the document in your local state with the response payload — no need for a follow-up `GET`.

### Handling sequential vs parallel visually

- **Sequential:** show the workflow as a vertical stepper with order numbers
- **Parallel:** show as a flat list of approvers with status chips

### File preview

Branch on `file_mime`:

```
if file_mime starts with "image/"  →  render <Image>
if file_mime == "application/pdf"  →  open in PDF viewer / webview
otherwise                          →  download / open externally
```

### Pagination

Standard Laravel pagination. Use `current_page`, `last_page`, and `total` to drive infinite scroll or pager UI. Page size defaults to 15 (documents) / 20 (admin lists).

### Token expiry

Sanctum tokens don't expire by default unless the backend is configured otherwise. Still, treat any `401` as a signal to clear the token and route the user back to login.

### Network errors vs API errors

Distinguish in your HTTP layer:

- **No response** (timeout, no internet) → show offline UI, allow retry
- **Response with error code** → use the `error` field to drive the message

### Recommended client-side caching

| Endpoint                                        | Cache strategy                                    |
| ----------------------------------------------- | ------------------------------------------------- |
| `GET /documents`                                | Short cache (~30s) — invalidate on approve/reject |
| `GET /documents/{id}`                           | No cache — always fresh                           |
| `GET /admin/departments`, `GET /admin/sections` | Long cache (~5 min) — they change rarely          |
| `GET /admin/users`                              | Medium cache (~1 min)                             |

---

## Endpoint Cheat Sheet

| Method | Endpoint                      | Who                             | Purpose                    |
| ------ | ----------------------------- | ------------------------------- | -------------------------- |
| GET    | `/documents?type=inbox\|sent` | All                             | List documents             |
| GET    | `/documents/{id}`             | All (if assigned/creator/admin) | Document details           |
| POST   | `/documents`                  | All                             | Create + send for approval |
| POST   | `/documents/{id}/approve`     | Current approver                | Approve step               |
| POST   | `/documents/{id}/reject`      | Current approver                | Reject document            |
| GET    | `/admin/users`                | Admin                           | List users                 |
| POST   | `/admin/users`                | Admin                           | Create user                |
| GET    | `/admin/users/{id}`           | Admin                           | User details               |
| PATCH  | `/admin/users/{id}`           | Admin                           | Update user                |
| DELETE | `/admin/users/{id}`           | Admin                           | Soft-delete user           |
| GET    | `/admin/departments`          | Admin                           | List departments           |
| POST   | `/admin/departments`          | Admin                           | Create department          |
| GET    | `/admin/departments/{id}`     | Admin                           | Department details         |
| PATCH  | `/admin/departments/{id}`     | Admin                           | Update department          |
| DELETE | `/admin/departments/{id}`     | Admin                           | Soft-delete department     |
| GET    | `/admin/sections`             | Admin                           | List sections              |
| POST   | `/admin/sections`             | Admin                           | Create section             |
| GET    | `/admin/sections/{id}`        | Admin                           | Section details            |
| PATCH  | `/admin/sections/{id}`        | Admin                           | Update section             |
| DELETE | `/admin/sections/{id}`        | Admin                           | Soft-delete section        |

---

**End of document.** For backend questions or to request new endpoints (e.g. push notifications, file signed URLs, action-required count), contact the backend team.

---

Visual Identity:

- # Document Approval Workflow — Mobile API Documentation

  **Version:** 1.0
  **Base URL:** `https://api.yourcompany.com/api`
  **Auth:** Laravel Sanctum (Bearer token)

  ---

  ## Table of Contents

  1. [General Conventions](#1-general-conventions)
  2. [Authentication](#2-authentication)
  3. [Error Format](#3-error-format)
  4. [Roles & Permissions](#4-roles--permissions)
  5. [Documents API](#5-documents-api)
  6. [Workflow Actions API](#6-workflow-actions-api)
  7. [Admin — Users API](#7-admin--users-api)
  8. [Admin — Departments API](#8-admin--departments-api)
  9. [Admin — Sections API](#9-admin--sections-api)
  10. [Status & Enum Reference](#10-status--enum-reference)
  11. [Mobile Implementation Notes](#11-mobile-implementation-notes)

  ---

  ## 1. General Conventions

  | Item         | Value                                                     |
  | ------------ | --------------------------------------------------------- |
  | Protocol     | HTTPS only                                                |
  | Format       | JSON for requests and responses                           |
  | File uploads | `multipart/form-data`                                     |
  | Date format  | ISO 8601 UTC (`2026-05-02T10:14:22.000000Z`)              |
  | Pagination   | Laravel-style: `{ data, current_page, last_page, total }` |

  ### Required headers on every request

  ```
  Authorization: Bearer {token}
  Accept: application/json
  Content-Type: application/json
  ```

  For file uploads, replace `Content-Type` with `multipart/form-data` (most HTTP libraries set this automatically).

  ---

  ## 2. Authentication

  > Auth endpoints (login/logout) are assumed to already exist on the backend. The mobile app receives a Bearer token after login, stores it securely (Keychain on iOS, EncryptedSharedPreferences on Android), and attaches it to every request.

  If the token is missing or invalid:

  ```json
  HTTP 401
  { "message": "Unauthenticated.", "error": "unauthenticated" }
  ```

  When this happens, redirect the user to the login screen and clear the stored token.

  ---

  ## 3. Error Format

  All errors share the same shape:

  ```json
  {
    "message": "Human-readable message",
    "error":   "machine_readable_code",
    "errors":  { "field": ["validation message"] }   // only on 422
  }
  ```

  ### Error codes the mobile app should handle

  | HTTP | `error` code                 | Meaning                    | Suggested UX                         |
  | ---- | ---------------------------- | -------------------------- | ------------------------------------ |
  | 401  | `unauthenticated`            | Token missing/expired      | Force logout                         |
  | 403  | `forbidden`                  | Not allowed by policy      | Show "no permission" message         |
  | 403  | `not_your_turn`              | Sequential workflow — wait | Show "waiting for previous approver" |
  | 404  | `not_found`                  | Resource doesn't exist     | Go back to list                      |
  | 404  | `no_pending_action`          | User has nothing to act on | Refresh inbox                        |
  | 404  | `route_not_found`            | Wrong URL                  | Likely a bug — log it                |
  | 409  | `document_already_finalized` | Already approved/rejected  | Refresh document                     |
  | 422  | `validation_failed`          | Form errors                | Show field errors inline             |
  | 422  | `invalid_workflow`           | Bad workflow setup         | Show in alert                        |
  | 500  | `server_error`               | Backend bug                | Generic "try again" message          |

  ---

  ## 4. Roles & Permissions

  | Role      | Can do                                                       |
  | --------- | ------------------------------------------------------------ |
  | `manager` | Create documents, view inbox/sent, approve/reject when it's their turn |
  | `admin`   | Everything a manager can + manage users, departments, sections, view all documents |

  The current user's role comes back in the login response. Use it to show/hide the admin section in your UI.

  ---

  ## 5. Documents API

  ### 5.1 List documents (inbox or sent)

  ```
  GET /documents?type={inbox|sent}&page=1
  ```

  | Query param | Type   | Notes                                                       |
  | ----------- | ------ | ----------------------------------------------------------- |
  | `type`      | string | `inbox` (default) — assigned to me. `sent` — created by me. |
  | `page`      | int    | Pagination                                                  |

  **Response — `200 OK`**

  ```json
  {
    "type": "inbox",
    "documents": {
      "current_page": 1,
      "last_page": 4,
      "per_page": 15,
      "total": 52,
      "data": [
        {
          "id": 17,
          "title": "Q1 Vendor Contract",
          "description": "Annual renewal for ACME supplies",
          "file_path": "documents/abc123.pdf",
          "file_name": "contract.pdf",
          "file_mime": "application/pdf",
          "file_size": 482910,
          "status": "pending",
          "workflow_mode": "sequential",
          "created_by": 2,
          "created_at": "2026-05-02T10:14:22.000000Z",
          "creator": { "id": 2, "name": "Ali Rashid", "email": "ali@company.com" },
          "workflows": [
            { "id": 41, "user_id": 5,  "order": 1, "status": "approved",
              "user": { "id": 5, "name": "Layla Hassan" } },
            { "id": 42, "user_id": 8,  "order": 2, "status": "pending",
              "user": { "id": 8, "name": "Omar Tahir" } }
          ]
        }
      ]
    }
  }
  ```

  ### 5.2 Get document details

  ```
  GET /documents/{id}
  ```

  **Response — `200 OK`**

  ```json
  {
    "document": {
      "id": 17,
      "title": "Q1 Vendor Contract",
      "description": "Annual renewal for ACME supplies",
      "file_path": "documents/abc123.pdf",
      "file_name": "contract.pdf",
      "file_mime": "application/pdf",
      "file_size": 482910,
      "status": "pending",
      "workflow_mode": "sequential",
      "creator": { "id": 2, "name": "Ali Rashid", "email": "ali@company.com" },
      "workflows": [
        { "id": 41, "user_id": 5, "order": 1, "status": "approved",
          "signed_at": "2026-05-02T11:02:00.000000Z", "note": "Looks good",
          "user": { "id": 5, "name": "Layla Hassan", "email": "layla@company.com" } },
        { "id": 42, "user_id": 8, "order": 2, "status": "pending",
          "signed_at": null, "note": null,
          "user": { "id": 8, "name": "Omar Tahir", "email": "omar@company.com" } }
      ],
      "logs": [
        { "id": 72, "action": "sent",     "done_by": 2, "note": null,
          "created_at": "2026-05-02T10:14:22.000000Z",
          "user": { "id": 2, "name": "Ali Rashid" } },
        { "id": 71, "action": "created",  "done_by": 2, "note": null,
          "created_at": "2026-05-02T10:14:22.000000Z",
          "user": { "id": 2, "name": "Ali Rashid" } },
        { "id": 73, "action": "approved", "done_by": 5, "note": "Looks good",
          "created_at": "2026-05-02T11:02:00.000000Z",
          "user": { "id": 5, "name": "Layla Hassan" } }
      ]
    },
    "next_pending_users": [
      { "id": 8, "name": "Omar Tahir", "email": "omar@company.com" }
    ]
  }
  ```

  > `next_pending_users` tells you who needs to act next. If the current user's ID is in this list, show the **Approve / Reject** buttons.

  ### 5.3 Create a document

  ```
  POST /documents
  Content-Type: multipart/form-data
  ```

  **Body**

  | Field            | Type   | Required | Notes                                               |
  | ---------------- | ------ | -------- | --------------------------------------------------- |
  | `title`          | string | yes      | Max 255 chars                                       |
  | `description`    | string | no       | Free text                                           |
  | `file`           | file   | yes      | PDF, DOC, DOCX, JPG, PNG, WEBP — max 20 MB          |
  | `workflow_mode`  | string | yes      | `sequential` or `parallel`                          |
  | `approver_ids[]` | int[]  | yes      | At least one. **Order matters in sequential mode.** |

  **Response — `201 Created`**

  ```json
  {
    "message": "Document created and sent for approval.",
    "document": {
      "id": 17,
      "title": "Q1 Vendor Contract",
      "status": "pending",
      "workflow_mode": "sequential",
      "workflows": [ /* ... */ ],
      "logs": [ /* created + sent */ ]
    }
  }
  ```

  ### 5.4 Download / view file

  The `file_path` returned is a relative storage path. Construct the URL like:

  ```
  {BASE_URL_WITHOUT_/api}/storage/{file_path}
  ```

  Or if you implement a signed-URL endpoint later, swap to that. For images (`file_mime` starts with `image/`), render inline. For PDFs/Word, open externally or in a webview.

  ---

  ## 6. Workflow Actions API

  ### 6.1 Approve a document

  ```
  POST /documents/{id}/approve
  ```

  **Body**

  ```json
  { "note": "Reviewed and confirmed pricing." }
  ```

  `note` is optional.

  **Response — `200 OK`**

  ```json
  {
    "message": "Document approved.",
    "document": { /* full updated document object */ }
  }
  ```

  > If the user was the **last** required approver, `document.status` will flip to `"approved"`. Otherwise it stays `"pending"` and the next user is shown in `next_pending_users`.

  ### 6.2 Reject a document

  ```
  POST /documents/{id}/reject
  ```

  **Body**

  ```json
  { "note": "Pricing exceeds approved budget." }
  ```

  **Response — `200 OK`**

  ```json
  {
    "message": "Document rejected.",
    "document": { /* status will be "rejected" */ }
  }
  ```

  > A single rejection terminates the workflow. The document is final.

  ### 6.3 Common errors on approve/reject

  | HTTP | Code                         | When                                            |
  | ---- | ---------------------------- | ----------------------------------------------- |
  | 403  | `not_your_turn`              | Sequential — earlier approvers haven't finished |
  | 403  | `forbidden`                  | User isn't an approver on this document at all  |
  | 404  | `no_pending_action`          | User already acted, or was never assigned       |
  | 409  | `document_already_finalized` | Already approved or rejected by the workflow    |

  ---

  ## 7. Admin — Users API

  > All `/admin/*` endpoints require `role: admin`. Returns `403 forbidden` otherwise.

  ### 7.1 List users

  ```
  GET /admin/users?role=manager&department_id=3&search=layla&page=1
  ```

  All query params are optional.

  **Response — `200 OK`**

  ```json
  {
    "users": {
      "current_page": 1,
      "data": [
        {
          "id": 24,
          "name": "Layla Hassan",
          "email": "layla@company.com",
          "role": "manager",
          "department_id": 3,
          "section_id": 7,
          "department": { "id": 3, "name": "Operations" },
          "section":    { "id": 7, "name": "Procurement" },
          "created_at": "2026-04-15T08:00:00.000000Z"
        }
      ],
      "total": 1
    }
  }
  ```

  ### 7.2 Get a user

  ```
  GET /admin/users/{id}
  ```

  ### 7.3 Create a user

  ```
  POST /admin/users
  ```

  **Body**

  ```json
  {
    "name": "Layla Hassan",
    "email": "layla@company.com",
    "password": "Sup3rSecret!",
    "password_confirmation": "Sup3rSecret!",
    "role": "manager",
    "department_id": 3,
    "section_id": 7
  }
  ```

  | Field                                | Required | Notes                                |
  | ------------------------------------ | -------- | ------------------------------------ |
  | `name`                               | yes      | Max 255                              |
  | `email`                              | yes      | Unique                               |
  | `password` + `password_confirmation` | yes      | Default Laravel password rules       |
  | `role`                               | yes      | `admin` or `manager`                 |
  | `department_id`                      | no       | Must exist if provided               |
  | `section_id`                         | no       | Must belong to the chosen department |

  **Response — `201 Created`** — returns the new user object.

  ### 7.4 Update a user

  ```
  PATCH /admin/users/{id}
  ```

  Body is the same as create, but every field is optional. Send only what changes.

  ### 7.5 Delete a user (soft delete)

  ```
  DELETE /admin/users/{id}
  ```

  Returns `422` if the admin tries to delete their own account.

  ---

  ## 8. Admin — Departments API

  ### 8.1 List

  ```
  GET /admin/departments?search=ops&page=1
  ```

  ```json
  {
    "departments": {
      "data": [
        { "id": 3, "name": "Operations", "code": "OPS",
          "sections_count": 4, "users_count": 22 }
      ]
    }
  }
  ```

  ### 8.2 Get one

  ```
  GET /admin/departments/{id}
  ```

  Returns the department with its sections and users included.

  ### 8.3 Create

  ```
  POST /admin/departments
  ```

  ```json
  { "name": "Operations", "code": "OPS" }
  ```

  `code` must be unique.

  ### 8.4 Update

  ```
  PATCH /admin/departments/{id}
  ```

  Same body, all optional.

  ### 8.5 Delete

  ```
  DELETE /admin/departments/{id}
  ```

  Returns `422` if the department still has sections or users attached. Reassign or remove them first.

  ---

  ## 9. Admin — Sections API

  ### 9.1 List

  ```
  GET /admin/sections?department_id=3&search=proc&page=1
  ```

  ```json
  {
    "sections": {
      "data": [
        { "id": 7, "department_id": 3, "name": "Procurement",
          "users_count": 5,
          "department": { "id": 3, "name": "Operations", "code": "OPS" } }
      ]
    }
  }
  ```

  ### 9.2 Get one

  ```
  GET /admin/sections/{id}
  ```

  ### 9.3 Create

  ```
  POST /admin/sections
  ```

  ```json
  { "department_id": 3, "name": "Procurement" }
  ```

  ### 9.4 Update

  ```
  PATCH /admin/sections/{id}
  ```

  ### 9.5 Delete

  ```
  DELETE /admin/sections/{id}
  ```

  Returns `422` if any users are still assigned.

  ---

  ## 10. Status & Enum Reference

  ### Document status

  | Value      | Meaning                                   |
  | ---------- | ----------------------------------------- |
  | `pending`  | In the workflow, waiting on approver(s)   |
  | `approved` | All approvers signed                      |
  | `rejected` | At least one approver rejected — terminal |

  ### Workflow step status

  | Value      | Meaning                                      |
  | ---------- | -------------------------------------------- |
  | `pending`  | Waiting on this user                         |
  | `approved` | This user approved                           |
  | `rejected` | This user rejected (terminates the document) |

  ### Workflow mode

  | Value        | Meaning                                        |
  | ------------ | ---------------------------------------------- |
  | `sequential` | Approvers act in order (`order` field matters) |
  | `parallel`   | All approvers can act at the same time         |

  ### Log actions

  | Value      | When                             |
  | ---------- | -------------------------------- |
  | `created`  | Document was first created       |
  | `sent`     | Document dispatched to approvers |
  | `approved` | An approver approved their step  |
  | `rejected` | An approver rejected             |

  ### User roles

  | Value     | Meaning            |
  | --------- | ------------------ |
  | `admin`   | Full system access |
  | `manager` | Documents only     |

  ---

  ## 11. Mobile Implementation Notes

  ### Detecting "is it my turn?"

  Don't rely on `document.status === 'pending'` alone. Instead:

  ```
  isMyTurn = document.next_pending_users.some(u => u.id === currentUser.id)
  ```

  If `isMyTurn` is true, show the Approve/Reject buttons. Otherwise show a read-only view.

  ### Inbox badge count

  Count unfinished documents the user must act on:

  ```
  GET /documents?type=inbox
  ```

  Then filter client-side where `next_pending_users` contains the current user. If you need a server-side count later, ask backend to add `?action_required=true`.

  ### Optimistic UI for approve/reject

  Both endpoints return the **full updated document**. After a successful response, replace the document in your local state with the response payload — no need for a follow-up `GET`.

  ### Handling sequential vs parallel visually

  - **Sequential:** show the workflow as a vertical stepper with order numbers
  - **Parallel:** show as a flat list of approvers with status chips

  ### File preview

  Branch on `file_mime`:

  ```
  if file_mime starts with "image/"  →  render <Image>
  if file_mime == "application/pdf"  →  open in PDF viewer / webview
  otherwise                          →  download / open externally
  ```

  ### Pagination

  Standard Laravel pagination. Use `current_page`, `last_page`, and `total` to drive infinite scroll or pager UI. Page size defaults to 15 (documents) / 20 (admin lists).

  ### Token expiry

  Sanctum tokens don't expire by default unless the backend is configured otherwise. Still, treat any `401` as a signal to clear the token and route the user back to login.

  ### Network errors vs API errors

  Distinguish in your HTTP layer:

  - **No response** (timeout, no internet) → show offline UI, allow retry
  - **Response with error code** → use the `error` field to drive the message

  ### Recommended client-side caching

  | Endpoint                                        | Cache strategy                                    |
  | ----------------------------------------------- | ------------------------------------------------- |
  | `GET /documents`                                | Short cache (~30s) — invalidate on approve/reject |
  | `GET /documents/{id}`                           | No cache — always fresh                           |
  | `GET /admin/departments`, `GET /admin/sections` | Long cache (~5 min) — they change rarely          |
  | `GET /admin/users`                              | Medium cache (~1 min)                             |

  ---

  ## Endpoint Cheat Sheet

  | Method | Endpoint                      | Who                             | Purpose                    |
  | ------ | ----------------------------- | ------------------------------- | -------------------------- |
  | GET    | `/documents?type=inbox\|sent` | All                             | List documents             |
  | GET    | `/documents/{id}`             | All (if assigned/creator/admin) | Document details           |
  | POST   | `/documents`                  | All                             | Create + send for approval |
  | POST   | `/documents/{id}/approve`     | Current approver                | Approve step               |
  | POST   | `/documents/{id}/reject`      | Current approver                | Reject document            |
  | GET    | `/admin/users`                | Admin                           | List users                 |
  | POST   | `/admin/users`                | Admin                           | Create user                |
  | GET    | `/admin/users/{id}`           | Admin                           | User details               |
  | PATCH  | `/admin/users/{id}`           | Admin                           | Update user                |
  | DELETE | `/admin/users/{id}`           | Admin                           | Soft-delete user           |
  | GET    | `/admin/departments`          | Admin                           | List departments           |
  | POST   | `/admin/departments`          | Admin                           | Create department          |
  | GET    | `/admin/departments/{id}`     | Admin                           | Department details         |
  | PATCH  | `/admin/departments/{id}`     | Admin                           | Update department          |
  | DELETE | `/admin/departments/{id}`     | Admin                           | Soft-delete department     |
  | GET    | `/admin/sections`             | Admin                           | List sections              |
  | POST   | `/admin/sections`             | Admin                           | Create section             |
  | GET    | `/admin/sections/{id}`        | Admin                           | Section details            |
  | PATCH  | `/admin/sections/{id}`        | Admin                           | Update section             |
  | DELETE | `/admin/sections/{id}`        | Admin                           | Soft-delete section        |

  ---

  **End of document.** For backend questions or to request new endpoints (e.g. push notifications, file signed URLs, action-required count), contact the backend team.

  
