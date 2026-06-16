# NucleusMac

The macOS Nucleus app lives at [`../../app/`](../../app/) today.

Future migration path:

1. Move `app/Nucleus/` → `Apps/NucleusMac/NucleusMac/`
2. Replace app-local web session helpers with `NucleusCore/WebWorkspace`
3. Share `SettingsSync` and notification modules from `NucleusCore`

The existing Xcode project is generated from `app/project.yml` via XcodeGen.
