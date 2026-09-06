# Fuzz harness templates

`cargo fuzz add` scaffolds a new fuzz target in one command. SharpFuzz (.NET) and
Jazzer.js (TypeScript) have no equivalent scaffolding command — the QA Engineer agent
copies and adapts the checked-in template for the resolved stack instead (see
`toolchains.<stack>.fuzz_add: null` in `.tech-decisions.yml`).

The invariant is identical across every stack, regardless of scaffolding mechanism:

- Must not crash
- Must not hang
- Must not allocate unboundedly
- A typed rejection (a validation error, a parse error) is a pass

## Templates

| Stack | Template | Harness runner |
|---|---|---|
| Rust | `cargo fuzz add <target>` (built-in, no template needed) | `cargo fuzz run <target>` |
| C# / .NET | [`templates/dotnet/SharpFuzzHarness.cs.template`](templates/dotnet/SharpFuzzHarness.cs.template) | SharpFuzz (`libFuzzer` driver via `dotnet run --project fuzz/<target>`) |
| TypeScript | [`templates/typescript/jazzer.harness.ts.template`](templates/typescript/jazzer.harness.ts.template) | Jazzer.js (`npx jazzer fuzz/<target>`) |

To add a new target for a stack without a scaffolding command: copy the template into
`fuzz/<target-name>/`, rename the placeholder type/function under test, and register the
project per the stack's normal build (add the new project to the solution for .NET, add
the entry point to `package.json` scripts for TypeScript).

Crash artefacts are saved under `fuzz/artifacts/<target>/` for every stack, matching the
Rust convention, so the QA Engineer's crash-handling workflow (reproduce, write a
regression test, re-run) is identical regardless of resolved stack.
