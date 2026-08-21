package example.chainguard.sbom;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;

import org.gradle.api.Project;
import org.gradle.api.artifacts.Configuration;
import org.gradle.api.artifacts.Dependency;
import org.gradle.api.artifacts.LenientConfiguration;
import org.gradle.api.artifacts.ResolvedArtifact;
import org.gradle.api.logging.Logger;

/**
 * Resolves Chainguard sidecar files (SPDX SBOMs, SLSA attestations) using the
 * project's already-configured repositories. Because we go through Gradle's own
 * dependency resolver via a detached configuration, credentials configured on
 * {@code MavenArtifactRepository} transfer automatically — the plugin never
 * needs to know about {@code libraries.cgr.dev} directly.
 */
public final class SbomFetcher {

    private final Project project;
    private final Path outputDirectory;
    private final Logger log;

    public SbomFetcher(Project project, Path outputDirectory, Logger log) {
        this.project = project;
        this.outputDirectory = outputDirectory;
        this.log = log;
    }

    public FetchResult fetch(String groupId, String artifactId, String version,
                             String classifier, Format kind) {
        String coord = coordinate(groupId, artifactId, classifier, version);

        Map<String, Object> notation = new HashMap<>();
        notation.put("group", groupId);
        notation.put("name", artifactId);
        notation.put("version", version);
        String effectiveClassifier = kind.classifierFor(classifier);
        if (!effectiveClassifier.isEmpty()) {
            notation.put("classifier", effectiveClassifier);
        }
        notation.put("ext", kind.extension());

        try {
            Dependency dep = project.getDependencies().create(notation);
            Configuration cfg = project.getConfigurations().detachedConfiguration(dep);
            cfg.setTransitive(false);
            // Lenient resolution: unresolved sidecars come back as "unresolved
            // dependencies" rather than throwing, so we can distinguish
            // "Chainguard didn't publish this" from real transport/IO errors.
            LenientConfiguration lenient = cfg.getResolvedConfiguration().getLenientConfiguration();
            if (!lenient.getUnresolvedModuleDependencies().isEmpty()) {
                if (log.isDebugEnabled()) {
                    log.debug("No " + kind + " for " + coord);
                }
                return FetchResult.notAvailable(coord, kind);
            }
            Set<ResolvedArtifact> resolved = lenient.getArtifacts();
            if (resolved.isEmpty()) {
                return FetchResult.notAvailable(coord, kind);
            }
            File file = resolved.iterator().next().getFile();
            Path dest = destinationFor(outputDirectory, groupId, artifactId, version, file.getName());
            Files.createDirectories(dest.getParent());
            Files.copy(file.toPath(), dest, StandardCopyOption.REPLACE_EXISTING);
            return FetchResult.fetched(coord, kind);
        } catch (IOException e) {
            return FetchResult.error(coord, kind,
                    "failed to write sidecar to " + outputDirectory + ": " + e.getMessage());
        } catch (RuntimeException e) {
            return FetchResult.error(coord, kind,
                    "unexpected error resolving sidecar: " + e.getClass().getSimpleName()
                    + ": " + e.getMessage());
        }
    }

    static String coordinate(String groupId, String artifactId, String classifier, String version) {
        StringBuilder sb = new StringBuilder(groupId).append(':').append(artifactId);
        if (classifier != null && !classifier.isEmpty()) {
            sb.append(':').append(classifier);
        }
        return sb.append(':').append(version).toString();
    }

    static Path destinationFor(Path outputDirectory, String groupId, String artifactId,
                               String version, String filename) {
        return outputDirectory
                .resolve(groupId.replace('.', '/'))
                .resolve(artifactId)
                .resolve(version)
                .resolve(filename);
    }
}
