# SBOM Gradle Plugin

An example Gradle plugin that collects the SBOMs provided by [Chainguard's Java
Libraries](https://edu.chainguard.dev/chainguard/libraries/java/overview/) for a
given project.

For each dependency in the resolved graph, the plugin fetches the SBOMs into
`build/chainguard-sboms/`.

See [Example](#example) for an example that demonstrates how the plugin works.

## Usage

To use this plugin you must either build it locally, or host it yourself in your
own plugin repository (Artifactory, Nexus etc).

Export a Chainguard pull token (see [Prerequisites](#prerequisites)), then:

```
gradle -I init.gradle test                # unit tests
gradle -I init.gradle publishToMavenLocal # install to ~/.m2/repository so mavenLocal() finds it
```

Then, apply it in your `build.gradle` like:

```groovy
plugins {
    id 'example.chainguard.sbom' version '0.1.0-SNAPSHOT'
}

chainguardSbom {
    formats = ['SPDX_JSON', 'SLSA_ATTESTATION']
}
```

If you omit `formats`, it collects everything. These are the supported
formats:

- `SPDX_JSON` — SPDX SBOM (`<artifact>-<version>.spdx.json`)
- `SLSA_ATTESTATION` — SLSA provenance (`<artifact>-<version>.slsa-attestation.json`)

The plugin registers a `collectSboms` task in the `verification` group. It
does not bind to `check` or `build` by default — invoke it explicitly with
`gradle collectSboms`, or wire it into another task with `dependsOn` /
`finalizedBy`.

Collected files land under `build/chainguard-sboms` in a Maven-style
directory layout — see the [example](#example) below for a full tree.

## Example

There is an [example project](./example) in this repository that demonstrates
the plugin in action.

### Prerequisites

- JDK 11 or newer.
- Gradle 8+.

### Steps

Follow these steps from this plugin's root directory (`sbom-gradle-plugin/`).

**1. Mint a Chainguard Libraries pull token and export it into your shell.**

Export credentials for `libraries.cgr.dev` as `CHAINGUARD_JAVA_IDENTITY_ID` and
`CHAINGUARD_JAVA_TOKEN`.

For a long-lived credential:

```
eval "$(chainctl auth pull-token create --output=env --repository=java --ttl=720h)"
```

For a short-lived credential scoped to your local Chainguard credentials:

```
export CHAINGUARD_JAVA_IDENTITY_ID=_token
export CHAINGUARD_JAVA_TOKEN=$(chainctl auth token --audience=libraries.cgr.dev)
```

The example's `build.gradle` reads them from there.

**2. Build and publish the plugin into your local Maven cache.**

```
gradle -I init.gradle publishToMavenLocal
```

**3. Change into the example project and run the plugin.**

```
cd example
gradle collectSboms
```

You should see something like:

```
> Task :collectSboms
Resolving SBOMs for 5 dependencies via 1 configured repositories.
Chainguard SBOMs: 10 fetched, 0 not available, 0 errored.
```

(Five deps because Jackson pulls in two transitives.)

**4. Inspect the output.**

Each dependency directory holds an SPDX SBOM and a SLSA provenance
attestation:

```
build/chainguard-sboms
├── com/fasterxml/jackson/core/jackson-annotations/2.17.2/
│   ├── jackson-annotations-2.17.2.slsa-attestation.json
│   └── jackson-annotations-2.17.2.spdx.json
├── com/fasterxml/jackson/core/jackson-core/2.17.2/
│   ├── jackson-core-2.17.2.slsa-attestation.json
│   └── jackson-core-2.17.2.spdx.json
├── com/fasterxml/jackson/core/jackson-databind/2.17.2/
│   ├── jackson-databind-2.17.2.slsa-attestation.json
│   └── jackson-databind-2.17.2.spdx.json
├── org/apache/commons/commons-compress/1.23.0/
│   ├── commons-compress-1.23.0.slsa-attestation.json
│   └── commons-compress-1.23.0.spdx.json
└── org/slf4j/slf4j-api/2.0.13/
    ├── slf4j-api-2.0.13.slsa-attestation.json
    └── slf4j-api-2.0.13.spdx.json
```

Dependencies without a Chainguard build are reported as "not available"
in the final summary — the plugin only fetches what it can, and does not
fail the build when a sidecar simply isn't published.

## Configuration

### Extension properties

Configure via the `chainguardSbom { ... }` block:

| Property | Default | Purpose |
|---|---|---|
| `outputDirectory` | `${buildDir}/chainguard-sboms` | Where SBOMs land. |
| `formats` | *(all)* | Formats to fetch. Values: `SPDX_JSON`, `SLSA_ATTESTATION`. When empty, both are fetched. |
| `configuration` | `runtimeClasspath` | Name of the resolvable Gradle configuration to walk. |
| `skip` | `false` | Skip the task entirely. |

Unlike the Maven equivalent, there is no `parallelism` setting — Gradle's own
dependency resolver batches artifact downloads internally.
