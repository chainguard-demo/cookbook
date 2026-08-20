package example.chainguard.sbom;

import java.io.File;
import java.util.Arrays;
import java.util.List;

import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugins.annotations.Component;
import org.apache.maven.plugins.annotations.Parameter;
import org.apache.maven.project.MavenProject;
import org.eclipse.aether.RepositorySystem;
import org.eclipse.aether.RepositorySystemSession;

/**
 * Shared configuration and Maven/Aether wiring for the SBOM mojo.
 */
public abstract class AbstractSbomMojo extends AbstractMojo {

    @Parameter(defaultValue = "${project}", readonly = true, required = true)
    protected MavenProject project;

    @Parameter(defaultValue = "${repositorySystemSession}", readonly = true, required = true)
    protected RepositorySystemSession repoSession;

    @Component
    protected RepositorySystem repoSystem;

    /**
     * Directory to write collected SBOMs into.
     */
    @Parameter(defaultValue = "${project.build.directory}/chainguard-sboms", property = "chainguard.sbom.outputDirectory")
    protected File outputDirectory;

    /**
     * Sidecar formats to download for each dependency. When unset, all known
     * formats are fetched ({@code SPDX_JSON}, {@code SLSA_ATTESTATION}). Set
     * an explicit list to restrict.
     */
    @Parameter(property = "chainguard.sbom.formats")
    protected List<Format> formats;

    protected List<Format> effectiveFormats() {
        return formats == null || formats.isEmpty()
                ? Arrays.asList(Format.values())
                : formats;
    }

    /**
     * Maven scopes to include when walking the resolved dependency graph.
     */
    @Parameter(defaultValue = "compile,runtime", property = "chainguard.sbom.includeScope")
    protected String includeScope;

    /**
     * Number of concurrent SBOM fetches.
     */
    @Parameter(defaultValue = "8", property = "chainguard.sbom.parallelism")
    protected int parallelism;

    /**
     * Skip the goal entirely.
     */
    @Parameter(defaultValue = "false", property = "chainguard.sbom.skip")
    protected boolean skip;
}
