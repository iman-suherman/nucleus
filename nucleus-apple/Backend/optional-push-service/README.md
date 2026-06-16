# Optional Push Service (Phase 4)

Backend service for Gmail watch → APNs delivery.

## Architecture

```
Gmail API (users.watch)
        │
        ▼
Cloud Pub/Sub or webhook
        │
        ▼
nucleus-push-service (Node/Go)
        │
        ├── Lookup device tokens (per account)
        ├── Fetch message metadata (Gmail API)
        └── Send APNs (HTTP/2)
                │
                ▼
         Nucleus iOS app
```

## Responsibilities

- Register Gmail `watch` per connected OAuth account
- Store APNs device tokens keyed by Google account ID
- Renew watches before expiry (~7 days)
- Respect per-account notification preferences synced via CloudKit
- **Do not** poll Gmail from the device in background

## iOS constraints

- Background tasks are system-scheduled; use push for new mail
- Calendar reminders use **local** `UNUserNotificationCenter` after event sync
- Meeting join action on 1-minute reminder (implemented in `MeetingReminderScheduler`)

## Deployment

Suggested stack: GCP Cloud Run + Firestore (consistent with `services/registry-api`).

Not implemented in Phase 1 — this directory documents the planned integration point.
