# Nucleus CloudKit schema

SwiftData syncs to container `iCloud.net.suherman.nucleus` in the **Production** environment for release builds and **Development** for Debug builds.

Canonical schema file: [`nucleus-development.ckdb`](nucleus-development.ckdb)

## When to update Production

Deploy a schema change to Production whenever a `@Model` field is added or changed, for example:

If Production is missing a field or record type, CloudKit export fails with **`CKError partialFailure (code 2)`** and synced data (bills, calendar, etc.) stops syncing.

| App change | CloudKit change |
|------------|-----------------|
| Calendar sync (v0.11.0+) | `CD_CalendarEventRecord` (new record type) |
| Multi-currency bills (v0.5.9+) | `CD_BillRecord.CD_currencyCode` (STRING) |

## Update Production (recommended workflow)

### 1. Import the updated schema into Development

**Option A — CLI** (needs a Management Token from CloudKit Console → Settings → API Access):

```bash
CLOUDKIT_MANAGEMENT_TOKEN=... bash scripts/seed-cloudkit-development.sh
```

**Option B — Console**

1. Open [CloudKit Console](https://icloud.developer.apple.com/dashboard/database/teams/Q3TXW887NM/containers/iCloud.net.suherman.nucleus)
2. Select **Development** (left sidebar)
3. Footer → **Import Schema…**
4. Choose `cloudkit/nucleus-development.ckdb`
5. Confirm import

### 2. Verify Development has the new field

In **Development → Schema → Record Types**, confirm **CD_CalendarEventRecord** exists (calendar) and **CD_BillRecord** includes **CD_currencyCode** (String).

### 3. Deploy Development → Production

Apple only allows Production schema deploy through the console:

1. Stay in CloudKit Console for `iCloud.net.suherman.nucleus`
2. Footer → **Deploy Schema Changes…**
3. Review the diff (should show `CD_CalendarEventRecord` added and/or `CD_currencyCode` added to `CD_BillRecord`)
4. Deploy to **Production**

Schema deploys are **additive only** — existing records keep working; new exports include calendar events and bill currency.

### 4. Verify Production

```bash
CLOUDKIT_MANAGEMENT_TOKEN=... bash scripts/diagnose-cloudkit-schema.sh
```

Or in Console: **Production → Schema** → confirm **CD_CalendarEventRecord** and **CD_BillRecord.CD_currencyCode** exist.

### 5. Retry sync on the Mac

1. Quit and reopen Nucleus (release build)
2. **Settings → iCloud → Sync to iCloud** (or open **Calendar** and refresh, then sync)
3. Check the iCloud sync log — export should finish without `partialFailure`

## Helper scripts

| Script | Purpose |
|--------|---------|
| `scripts/seed-cloudkit-development.sh` | Import `nucleus-development.ckdb` into Development |
| `scripts/deploy-cloudkit-production-schema.sh` | Import Development + compare Production record types/fields |
| `scripts/diagnose-cloudkit-schema.sh` | Export and diff Development vs Production |
| `scripts/initialize-cloudkit-schema.sh` | Regenerate schema from a Debug Nucleus launch (optional) |

## Required record types (Production)

- `CD_NoteRecord`
- `CD_GoogleAccountRecord`
- `CD_SyncedSettingsRecord`
- `CD_ClipboardItemRecord`
- `CD_BillRecord` (includes `CD_currencyCode`)
- `CD_BillPaymentRecord`
- `CD_CalendarEventRecord`
- `CD_DashboardAnalysisRecord`

Synced data lives in private zone `com.apple.coredata.cloudkit.zone`.
