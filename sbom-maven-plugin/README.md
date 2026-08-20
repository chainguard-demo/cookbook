# SBOM Maven Plugin

An example Maven plugin that collects the SBOMs provided by [Chainguard's Java
Libraries](https://edu.chainguard.dev/chainguard/libraries/java/overview/) for a
given project.

For each dependency in the resolved graph, the plugin fetches the SBOMs into
`target/chainguard-sboms/`.

See [Example](#example) for an example that demonstrates how the plugin works.

## Usage

To use this plugin you must either build it locally, or host it yourself in your
own `pluginRepository` (Artifactory, Nexus etc).

```
mvn test         # unit tests
mvn install      # install to ~/.m2/repository
```

Then, you can add it to your `pom.xml` like:

```xml
<plugin>
    <groupId>example.chainguard</groupId>
    <artifactId>sbom-maven-plugin</artifactId>
    <version>0.1.0-SNAPSHOT</version>
    <configuration>
        <formats>
            <format>SPDX_JSON</format>
            <format>SLSA_ATTESTATION</format>
        </formats>
    </configuration>
    <executions>
        <execution>
            <goals><goal>collect</goal></goals>
        </execution>
    </executions>
</plugin>
```

If you omit the `formats`, it collects everything. These are the supported
formats:

- `SPDX_JSON` — SPDX SBOM (`<artifact>-<version>.spdx.json`)
- `SLSA_ATTESTATION` — SLSA provenance (`<artifact>-<version>.slsa-attestation.json`)

The `collect` goal binds to the `verify` phase by default, so `mvn verify`
will emit the SBOMs. It can also be run ad-hoc with `mvn sbom:collect`.

Collected files land under `target/chainguard-sboms` in a Maven-style
directory layout — see the [example](#example) below for a full tree.

## Example

There is an [example project](./example) in this repository that demonstrates
the plugin in action.

### Prerequisites

- JDK 11 or newer.
- Maven 3.9+.

### Steps

Follow these steps from this plugin's root directory (`sbom-maven-plugin/`).

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

The example's `settings.xml` reads them from there.

**2. Build and install the plugin into your local Maven cache.**

```
mvn install
```

**3. Change into the example project and run the plugin.**

```
cd example
mvn -s settings.xml sbom:collect
```

You should see something like:

```
[INFO] --- sbom:0.1.0-SNAPSHOT:collect ---
[INFO] Resolving SBOMs for 5 dependencies via 2 configured repositories.
[INFO] Downloading from chainguard: https://libraries.cgr.dev/java/org/apache/commons/commons-compress/1.23.0/commons-compress-1.23.0.spdx.json
...
[INFO] Chainguard SBOMs: 10 fetched, 0 not available, 0 errored.
```

(Five deps because Jackson pulls in two transitives; two repositories
because Maven adds Central by default alongside the Chainguard one
declared in `pom.xml`.)

**4. Inspect the output.**

Each dependency directory holds an SPDX SBOM and a SLSA provenance
attestation:

```
target/chainguard-sboms
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

### Parameters

| Parameter | Default | Purpose |
|---|---|---|
| `outputDirectory` | `${project.build.directory}/chainguard-sboms` | Where SBOMs land. |
| `formats` | *(all)* | Formats to fetch. Values: `SPDX_JSON`, `SLSA_ATTESTATION`. When unset, both are fetched. |
| `includeScope` | `compile,runtime` | Maven scopes to walk. |
| `parallelism` | `8` | Concurrent SBOM resolutions. |
| `skip` | `false` | Skip the goal entirely. |

Every parameter is also exposed as a system property under the
`chainguard.sbom.*` namespace (e.g. `-Dchainguard.sbom.parallelism=16`).
