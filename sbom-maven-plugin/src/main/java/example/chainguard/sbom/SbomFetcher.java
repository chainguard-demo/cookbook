package example.chainguard.sbom;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.List;
import java.util.stream.Collectors;

import org.apache.maven.plugin.logging.Log;
import org.eclipse.aether.RepositorySystem;
import org.eclipse.aether.RepositorySystemSession;
import org.eclipse.aether.artifact.Artifact;
import org.eclipse.aether.artifact.DefaultArtifact;
import org.eclipse.aether.repository.RemoteRepository;
import org.eclipse.aether.repository.RepositoryPolicy;
import org.eclipse.aether.resolution.ArtifactRequest;
import org.eclipse.aether.resolution.ArtifactResolutionException;
import org.eclipse.aether.resolution.ArtifactResult;

/**
 * Resolves Chainguard sidecar files (SPDX SBOMs, SLSA attestations) using the
 * project's already-configured remote repositories. Because we go through Aether,
 * mirrors, proxies, and {@code <server>} credentials from settings.xml transfer
 * automatically — the plugin never needs to know about libraries.cgr.dev directly.
 */
public final class SbomFetcher {

    private final RepositorySystem repoSystem;
    private final RepositorySystemSession session;
    private final List<RemoteRepository> repositories;
    private final Path outputDirectory;
    private final Log log;

    public SbomFetcher(RepositorySystem repoSystem,
                       RepositorySystemSession session,
                       List<RemoteRepository> repositories,
                       Path outputDirectory,
                       Log log) {
        this.repoSystem = repoSystem;
        this.session = session;
        this.repositories = withIgnoredChecksums(repositories);
        this.outputDirectory = outputDirectory;
        this.log = log;
    }

    public FetchResult fetch(String groupId, String artifactId, String version,
                             String classifier, Format kind) {
        String coord = coordinate(groupId, artifactId, classifier, version);
        Artifact sidecar = new DefaultArtifact(
                groupId,
                artifactId,
                kind.classifierFor(classifier),
                kind.extension(),
                version);

        ArtifactRequest request = new ArtifactRequest(sidecar, repositories, null);

        try {
            ArtifactResult result = repoSystem.resolveArtifact(session, request);
            Path resolved = result.getArtifact().getFile().toPath();
            Path dest = destinationFor(outputDirectory, groupId, artifactId, version, resolved.getFileName().toString());
            Files.createDirectories(dest.getParent());
            Files.copy(resolved, dest, StandardCopyOption.REPLACE_EXISTING);
            return FetchResult.fetched(coord, kind);
        } catch (ArtifactResolutionException e) {
            // Any repo could have served it; none did. Treat as "no Chainguard SBOM
            // exists for this dep" rather than a build failure.
            if (log.isDebugEnabled()) {
                log.debug("No " + kind + " for " + coord + ": " + e.getMessage());
            }
            return FetchResult.notAvailable(coord, kind);
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

    /**
     * Sidecar files may not have {@code .sha1}/{@code .md5} companions published
     * alongside them (unlike jars). Force checksum policy to {@code ignore} so we
     * don't emit spurious warnings on every resolution — the sidecar's authenticity
     * is established by cosign signature verification, not by Maven checksums.
     */
    static List<RemoteRepository> withIgnoredChecksums(List<RemoteRepository> repos) {
        return repos.stream()
                .map(SbomFetcher::relaxChecksums)
                .collect(Collectors.toList());
    }

    private static RemoteRepository relaxChecksums(RemoteRepository repo) {
        RepositoryPolicy releases = repo.getPolicy(false);
        RepositoryPolicy snapshots = repo.getPolicy(true);
        return new RemoteRepository.Builder(repo)
                .setReleasePolicy(new RepositoryPolicy(
                        releases.isEnabled(),
                        releases.getUpdatePolicy(),
                        RepositoryPolicy.CHECKSUM_POLICY_IGNORE))
                .setSnapshotPolicy(new RepositoryPolicy(
                        snapshots.isEnabled(),
                        snapshots.getUpdatePolicy(),
                        RepositoryPolicy.CHECKSUM_POLICY_IGNORE))
                .build();
    }
}
