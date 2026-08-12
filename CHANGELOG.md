# Changelog

## [0.1.1] - 2026-08-12

### Added

- Added a task-manager sample that demonstrates `ExParamsSchema.Handler` and JSON Schema validation in a Phoenix application.
- Added `ExParamsSchema.ValidationError.to_form_errors/1`, which groups detailed validation-error reasons by field path for convenient form rendering.
- Added `prek`-based pre-commit checks and development guides for running them locally.

### Changed

- `parse_detailed/1` and `parse_detailed/2` now return all casting, missing required-value, and strict-mode unknown-key errors across fields, nested objects, and array items. Unknown keys are reported with the `:additional_properties` keyword.
- Translated the published module, type, function, and macro documentation to English.
- Updated the supported Elixir version to 1.18 and expanded the CI matrix for Elixir and OTP versions.

## [0.1.0] - 2026-08-11

### Added

- First release
