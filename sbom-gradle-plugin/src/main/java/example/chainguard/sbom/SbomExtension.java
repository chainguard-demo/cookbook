package example.chainguard.sbom;

import java.io.File;

import org.gradle.api.provider.ListProperty;
import org.gradle.api.provider.Property;

/**
 * Shared configuration for the SBOM plugin. Mirrors the parameter surface of
 * the Maven plugin's {@code AbstractSbomMojo}.
 * <p>
 * Note: Gradle's own dependency resolver handles fetch parallelism internally,
 * so there is no {@code parallelism} setting equivalent to the Maven side.
 */
public abstract class SbomExtension {

    /** Directory to write collected SBOMs into. */
    public abstract Property<File> getOutputDirectory();

    /**
     * Sidecar formats to download for each dependency. When empty, all known
     * formats are fetched ({@code SPDX_JSON}, {@code SLSA_ATTESTATION}).
     */
    public abstract ListProperty<Format> getFormats();

    /**
     * Name of the resolvable {@link org.gradle.api.artifacts.Configuration} to
     * walk. Defaults to {@code runtimeClasspath}, analogous to the Maven
     * plugin's default {@code compile,runtime} scope filter.
     */
    public abstract Property<String> getConfiguration();

    /** Skip the task entirely. */
    public abstract Property<Boolean> getSkip();
}
