# pkl-talos

Typed [Pkl](https://pkl-lang.org) modules for [Talos Linux](https://www.talos.dev) machine
configuration, generated from the configuration schema that ships with Talos. Write configuration
patches for `talosctl`, including `$patch: delete`, or complete machine configurations, and let Pkl
check them before Talos sees them.

```pkl
amends "@talos/ConfigPatch.pkl"

import "@talos/network/LinkConfig.pkl"
import "@talos/patch.pkl"
import "@talos/v1alpha1/Config.pkl"

documents {
  new Config {
    machine {
      certSANs { "k8s.example.com" }
    }
  }
  new LinkConfig {
    name = "eth0"
    mtu = 9000
    addresses {
      new { address = "10.0.0.2/24" }
    }
    routes = patch.deleted
  }
}
```

```console
$ pkl eval patch.pkl -o patch.yaml
$ talosctl machineconfig patch controlplane.yaml --patch @patch.yaml -o cp-1.yaml
```

Like [pkl-k8s](https://github.com/apple/pkl-k8s) does for Kubernetes, every Talos configuration
document is a module you can amend or instantiate. A scheduled workflow generates, tests and
publishes a package for every Talos line from 1.8 on, the first release that accepts
`$patch: delete`.

## Installing

Pick the package of your Talos line and add it to your `PklProject`:

```pkl
amends "pkl:Project"

dependencies {
  ["talos"] {
    uri = "package://github.com/EnzoAlbornoz/pkl-talos/releases/download/talos@1.14.0/talos@1.14.0"
  }
}
```

Then run `pkl project resolve`. Modules import the package as `@talos/...`. Outside a project, use
the full URI instead: `package://github.com/EnzoAlbornoz/pkl-talos/releases/download/talos@1.14.0/talos@1.14.0#/ConfigPatch.pkl`.

The package needs Pkl 0.30 or later.

### Versions

Each Talos minor line has its own packages, `talos@<major>.<minor>.<n>`. The package follows the
newest Talos release of its line, and `<n>` counts the packages of the line: it goes up when Talos
releases a new patch version or when the generator changes. So `talos@1.14.n` is for Talos 1.14,
and the newest one is the best one, but `n` is not the Talos patch version. The notes of each
[release](https://github.com/EnzoAlbornoz/pkl-talos/releases) name the Talos version it was
generated from, and so does the package itself:

```pkl
import "@talos/runtime/UnattendedInstallConfig.pkl"
import "@talos/version.pkl"

documents {
  new UnattendedInstallConfig {
    installer {
      image = "ghcr.io/siderolabs/installer:v\(version.talos)"
    }
  }
}
```

A published version never changes: releases only ever add versions, so the checksums in your
`PklProject.deps.json` stay valid.

## Writing patches

`ConfigPatch.pkl` renders its `documents` as a multi-document YAML stream, which every `talosctl`
command that takes patches accepts:

```console
$ talosctl gen config garden https://k8s.example.com:6443 --config-patch @patch.yaml
$ talosctl machineconfig patch controlplane.yaml --patch @patch.yaml -o cp-1.yaml
$ talosctl patch machineconfig --nodes 10.0.0.11 --patch @patch.yaml
```

### Documents

Each document kind is a module named after the group of its Go package and its `kind`:

| Talos                                                | Pkl                                              |
| ---------------------------------------------------- | ------------------------------------------------ |
| `kind: LinkConfig`                                   | `@talos/network/LinkConfig.pkl`                  |
| `kind: KubeletConfig`                                | `@talos/k8s/KubeletConfig.pkl`                   |
| `kind: UserVolumeConfig`                             | `@talos/block/UserVolumeConfig.pkl`              |
| the legacy `version: v1alpha1` document              | `@talos/v1alpha1/Config.pkl`                     |
| a type that documents use, such as `AddressConfig`   | a class of `@talos/network.pkl`                  |

Documents set their `apiVersion` and `kind` themselves. Documents that Talos tells apart by name
require `name`; every other property is optional, because a patch is partial.

To describe a single document, amend its module:

```pkl
amends "@talos/network/HostnameConfig.pkl"

hostname = "worker-1"
```

Pkl checks the types, enum values and patterns of the schema:

```
–– Pkl Error ––
Expected value of type `"controlplane" | "worker" | patch.Delete`, but got type `String`.
Value: "router"
```

Durations take Pkl durations as well as Go duration strings: `bootTimeout = 2.min` renders as `2m`.
Free-form fields, such as Kubernetes manifests, take a `Dynamic`, a `Mapping` or any typed object,
including [pkl-k8s](https://github.com/apple/pkl-k8s) resources.

### Deleting with `$patch`

Talos deletes whatever a patch marks with `$patch: delete`:

| To delete                                | Write                                                       | Renders as                                   |
| ---------------------------------------- | ----------------------------------------------------------- | -------------------------------------------- |
| a field, a map entry or a whole list     | ``mtu = patch.deleted``                                     | `mtu: {$patch: delete}`                      |
| a list item                              | ``new { address = "10.0.0.3/24"; `$patch` = "delete" }``    | `- {address: 10.0.0.3/24, $patch: delete}`   |
| a whole document                         | ``new LinkConfig { name = "eth0"; `$patch` = "delete" }``   | `apiVersion`, `kind`, `name`, `$patch`       |

`patch.deleted` comes from `@talos/patch.pkl`; `delete` is a keyword in Pkl. Talos has rules for
deleting that YAML can't express, and `ConfigPatch.pkl` checks them before rendering:

- Talos matches a list item on its first property, so a list item to delete sets exactly one.
- Talos can't delete a key inside a list item.
- An object or document marked with `$patch` is deleted whole, so it sets nothing else (apart from
  the `name` that finds a document).
- Talos 1.8 to 1.11 can't delete list items at all; their packages report it.

It reports every problem at once:

```
–– Pkl Error ––
Invalid machine configuration patch:
- documents[1] (NetworkRuleConfig "ingress").ingress[0]: a list item to delete must set exactly one property, which Talos matches items on, but it sets `subnet`, `except`
```

Talos also fails a patch that deletes something that isn't there.

### Settings the schema doesn't describe

The schema leaves out settings that Talos deprecated, such as `machine.install` and
`machine.network` from Talos 1.14 on. A `Dynamic` document is rendered as it is, without checks:

```pkl
documents {
  new Dynamic {
    machine {
      install {
        disk = "/dev/sda"
      }
    }
  }
}
```

### One patch per node

Pkl can render several files at once. [examples/patches/nodes.pkl](examples/patches/nodes.pkl)
writes a patch per node from a list of nodes:

```console
$ pkl eval -m out examples/patches/nodes.pkl
out/cp-1.yaml
out/cp-2.yaml
out/cp-3.yaml
```

## Writing complete configurations

`MachineConfig.pkl` renders complete machine configurations. On top of the type checks, it reports
properties that Talos requires but the configuration leaves out (they are marked
`@schema.Required`), documents that appear more than once, and any `$patch`.
[examples/complete/controlplane.pkl](examples/complete/controlplane.pkl) builds a control plane
configuration from the secrets bundle of `talosctl gen secrets`:

```console
$ talosctl gen secrets -o examples/complete/secrets.yaml
$ pkl eval examples/complete/controlplane.pkl -o controlplane.yaml
$ talosctl validate --config controlplane.yaml --mode metal
controlplane.yaml is valid for metal mode
```

Talos checks the rest when it loads the configuration, so validate it with `talosctl validate`.

## Package contents

| Module                         | Contents                                                                    |
| ------------------------------ | --------------------------------------------------------------------------- |
| `ConfigPatch.pkl`              | A machine configuration patch: `documents`, checked and rendered as YAML    |
| `MachineConfig.pkl`            | A complete machine configuration                                            |
| `patch.pkl`                    | `deleted`, the `Delete` class, and the `Patchable<T>` type alias            |
| `<group>/<Kind>.pkl`           | One module per document kind, such as `network/LinkConfig.pkl`              |
| `<group>.pkl`                  | The classes that a group's documents use, such as `network.AddressConfig`   |
| `schema.pkl`                   | `@Required`, `GoDuration`, `Unstructured`, and the YAML converters          |
| `version.pkl`                  | The Talos version and schema URL that the package was generated from        |
| `Document.pkl`                 | The base module of every document                                           |

## How it works

[generator/](generator) is a Pkl program that reads Talos's
[`config.schema.json`](https://github.com/siderolabs/talos/tree/main/pkg/machinery/config/schemas)
at a release tag and writes a package: a module per document, a module of classes per group, and the
hand-written modules of [package/](package). [generator/src/fixes.pkl](generator/src/fixes.pkl)
corrects known errors of the upstream schema, for example `acceptedCAs`, which the schema
declares as an object although Talos reads a list. Each fix stops applying once Talos fixes its
schema, and the release notes list the fixes a package needed.

The [release workflow](.github/workflows/release.yml) runs every day and on changes to the
generator. For each Talos line, it generates the package of the line's newest release and compares
its digest with the one that the line's latest release recorded. If they differ, it tests the new
package and publishes the next version. Before publishing, every package passes:

- the Pkl tests in [tests/package](tests/package), which render documents and check the errors;
- the end-to-end tests in [tests/e2e](tests/e2e), which apply rendered patches with the matching
  `talosctl machineconfig patch`, validate the result with `talosctl validate`, and check it;
- the [examples](examples), rendered and validated with `talosctl`.

[CONTRIBUTING.md](CONTRIBUTING.md) explains how to work on the generator.

## License

[MPL-2.0](LICENSE), the license of Talos, whose documentation the generated modules carry.
