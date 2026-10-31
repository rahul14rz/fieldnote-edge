# Contracts

The JSON Schema files in `schema/` are the single source for data shared between the Flutter app and the Mac gateway. [quicktype](https://github.com/glideapps/quicktype) 26.0.0 generates the types from them:

- TypeScript: `generated/ts/index.ts`
- Dart: `dart/lib/fieldnote_contracts.dart` (package `fieldnote_contracts`)

Do not edit the generated files. [ADR 0003](../../docs/decisions/0003-contracts-generator.md) explains why quicktype was chosen.

## Commands

Run these from the repository root:

```bash
pnpm --filter @fieldnote/contracts generate
pnpm --filter @fieldnote/contracts check
pnpm --filter @fieldnote/contracts test
```

`check` regenerates the files in memory and exits with code 1 if the committed output differs from it. CI runs this check. Both `generate` and `check` also exit with code 1 if any object property is missing from `required`. If a value can be absent, make it nullable (`"type": ["string", "null"]`) instead of optional, because quicktype's Dart `toJson` writes an absent optional property as `null`, and the schema would reject that.

The Dart tests parse the same fixtures that the TypeScript tests validate with Ajv:

```bash
cd packages/contracts/dart
dart test
```
