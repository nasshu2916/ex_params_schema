# Changelog

## [Unreleased]

### Added

- Added a sample project using `ExParamsSchema.Handler` and JSON Schema validation.
- Added `ExParamsSchema.ValidationError.to_form_errors/1` to group detailed validation errors by field path for form rendering.

### Changed

- Translated published module, type, function, and macro documentation to English.
- `parse_detailed/1` and `parse_detailed/2` now collect conversion, missing-value, and strict-mode unknown-key errors from all fields.

## [0.1.0] - 2026-08-11

### Added

- First release
