# Contributing

## Setup

The project uses [mise](https://mise.jdx.dev) for its tools and tasks. `mise install` installs Pkl,
`talosctl`, `actionlint` and `zizmor` at the versions [mise.toml](mise.toml) pins; the end-to-end
tests install the `talosctl` release of the package they test. The tasks are Bash scripts, which mise
runs with Git Bash on Windows.

```console
$ mise install
$ mise run test            # generate the package for $TALOS_VERSION and run every test
$ mise tasks               # list the tasks
```

`TALOS_VERSION` (set in mise.toml) chooses the Talos release that `mise run generate` and the tests
use. To work on another line:

```console
$ TALOS_VERSION=1.12.12 mise run test
```

Editors resolve `@talos/...` in `tests/` and `examples/` to the package in `build/talos`, so run
`mise run generate` first, then sync the Pkl projects in your editor.

## Layout

| Path                     | Contents                                                                       |
| ------------------------ | ------------------------------------------------------------------------------ |
| `generator/generate.pkl` | Writes the package for one Talos release: `pkl eval -m build/talos generator/generate.pkl -p talosVersion=1.14.4` |
| `generator/plan.pkl`     | Plans the releases (see below)                                                 |
| `generator/src/`         | The generator, its upstream schema fixes and the release planner               |
| `generator/tests/`       | Unit tests of the generator, on [a small schema](generator/tests/fixtures/schema.json) |
| `package/`               | Hand-written modules that every package ships                                  |
| `tests/package/v<line>/` | Pkl tests of the generated package, for Talos `<line>` and later               |
| `tests/e2e/v<line>/`     | End-to-end scenarios, for Talos `<line>` and later                             |
| `examples/`              | Examples, which `mise run test:examples` renders and validates                 |
| `mise-tasks/`            | The mise tasks                                                                 |

The generated package goes to `build/talos`, which is not committed: CI and releases generate it.

## Tests

- `mise run test:generator` runs the unit tests of the generator and the planner. The
  `*.pkl-expected.pcf` files next to them hold the expected output of `examples`; when a change to
  the output is intended, delete the file and run the tests again to write it.
- `mise run test:package` runs the tests in `tests/package/v*/` whose line is at most the package's.
- `mise run test:e2e` runs each scenario in `tests/e2e/v*/*/` whose line is at most the package's:
  it renders `setup.pkl` (optional) and `patch.pkl`, applies them in that order to a control plane
  configuration from `talosctl gen config`, validates the result and checks it with
  `verify_test.pkl`.
- `mise run test:examples` renders the examples and validates them with `talosctl`.
- `mise run lint` checks the formatting of the Pkl sources (`mise run fmt` fixes it) and lints the
  workflows.

CI runs all of them for the newest release of every Talos line, and the package tests with the
oldest Pkl release the package supports.

## Fixing the upstream schema

When the Talos schema describes a setting differently from how Talos reads it, add a fix to
[generator/src/fixes.pkl](generator/src/fixes.pkl). A fix checks that the schema still has the
error, so it stops applying once Talos corrects it. Add the case to the
[test schema](generator/tests/fixtures/schema.json), and report the error to
[Talos](https://github.com/siderolabs/talos/issues).

The generator fails on schema constructs it does not know, rather than generating something
wrong; extend `knownKeywords` in [generator/src/Generator.pkl](generator/src/Generator.pkl) and the
type mapping when Talos starts using one.

## Releases

Releases are automatic. The [release workflow](.github/workflows/release.yml) runs daily, on pushes
to `main` that change the generator or the package sources, and on demand. It plans with
`mise run release:plan`: for every Talos line from 1.8 on, it generates the package of the line's
newest release and compares its digest with the one recorded in the notes of the line's latest
release. A line whose package changed gets the next version, `talos@<line>.<n+1>`, or
`talos@<line>.0` for a new line. Each package is built and tested on its own, then published as an
immutable GitHub release with a build provenance attestation.

A manual run can limit the lines (`1.13,1.14`), include lines that only have Talos pre-releases (as
`talos@<line>.0-pre.<n>`), or only plan and build (`dry-run`).

To see what the next run would publish:

```console
$ mise run release:plan
```

### Publishing from a new repository

The package URIs follow the repository that publishes them, so a fork publishes its own packages.

1. Create the repository on GitHub, public so that Pkl can download the releases without
   credentials, and push `main`. The push starts the release workflow, which publishes a package
   for every Talos line; start it from the Actions tab with `dry-run` first if you'd rather check
   the plan.
2. In the repository settings, enable release immutability (Settings → General → Releases), so that
   GitHub refuses to change a published package. The workflow already publishes each release as a
   draft first and only makes it public once every file is attached.
3. Keep "Read repository contents" as the default workflow permission: the release job asks for
   `contents: write` itself.
