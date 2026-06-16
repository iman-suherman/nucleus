# Notification Service Extension (Phase 4)

Planned capability: enrich Gmail push notifications before delivery.

## Flow

1. Backend sends APNs payload with `mutable-content: 1`
2. Notification Service Extension downloads Gmail metadata
3. Extension rewrites title/body (sender, subject snippet)
4. Badge count updated on main app via silent push or background fetch

## Requirements

- Notification Service Extension target
- Shared Keychain access for device token registration
- Backend push service (see `Backend/optional-push-service`)
