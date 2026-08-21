package example.chainguard.sbom;

import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

import org.apache.maven.artifact.Artifact;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugin.MojoFailureException;
import org.apache.maven.plugins.annotations.LifecyclePhase;
import org.apache.maven.plugins.annotations.Mojo;
import org.apache.maven.plugins.annotations.ResolutionScope;
import org.eclipse.aether.repository.RemoteRepository;

/**
 * Walks the resolved dependency graph and downloads every available Chainguard
 * sidecar (SPDX SBOM, CycloneDX SBOM, SLSA attestation) into the configured
 * output directory. Dependencies without a Chainguard build are skipped
 * silently — the plugin only fetches what it can.
 */
@Mojo(name = "collect",
      defaultPhase = LifecyclePhase.VERIFY,
      requiresDependencyResolution = ResolutionScope.RUNTIME,
      threadSafe = true)
public class CollectSbomMojo extends AbstractSbomMojo {

    @Override
    public void execute() throws MojoExecutionException, MojoFailureException {
        if (skip) {
            getLog().info("sbom:collect skipped by configuration.");
            return;
        }

        Set<String> scopes = parseScopes(includeScope);
        List<Artifact> targets = collectTargets(scopes);

        if (targets.isEmpty()) {
            getLog().info("No dependencies in scope " + scopes + " to collect SBOMs for.");
            return;
        }

        List<RemoteRepository> repos = project.getRemoteProjectRepositories();
        if (repos == null || repos.isEmpty()) {
            throw new MojoFailureException(
                    "No remote repositories are available to resolve SBOMs. "
                    + "Configure Chainguard Libraries as a repository (see "
                    + "https://edu.chainguard.dev/chainguard/libraries/java/build-configuration/).");
        }
        getLog().info("Resolving SBOMs for " + targets.size() + " dependencies via "
                + repos.size() + " configured repositories.");

        Path outputBase = outputDirectory.toPath();
        SbomFetcher fetcher = new SbomFetcher(repoSystem, repoSession, repos, outputBase, getLog());

        List<Format> formats = effectiveFormats();
        List<FetchResult> results = fetchAll(targets, formats, fetcher);
        summarize(results);

        long errored = results.stream().filter(r -> r.status() == FetchResult.Status.ERROR).count();
        if (errored > 0) {
            throw new MojoFailureException(errored + " SBOM fetch(es) errored (see warnings above). "
                    + "Missing sidecars (not-available) do not fail the build; only unexpected errors do.");
        }
    }

    private List<Artifact> collectTargets(Set<String> scopes) {
        List<Artifact> targets = new ArrayList<>();
        Collection<Artifact> deps = project.getArtifacts();
        if (deps != null) {
            for (Artifact a : deps) {
                if (!scopes.contains(a.getScope())) continue;
                if (!"jar".equals(a.getType())) continue;
                targets.add(a);
            }
        }
        return targets;
    }

    private List<FetchResult> fetchAll(List<Artifact> targets, List<Format> formats, SbomFetcher fetcher)
            throws MojoExecutionException, MojoFailureException {
        int threads = Math.max(1, parallelism);
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        try {
            List<CompletableFuture<FetchResult>> futures = new ArrayList<>();
            for (Artifact a : targets) {
                for (Format format : formats) {
                    futures.add(CompletableFuture.supplyAsync(
                            () -> fetcher.fetch(a.getGroupId(), a.getArtifactId(), a.getVersion(),
                                    a.getClassifier(), format),
                            pool));
                }
            }
            List<FetchResult> results = new ArrayList<>(futures.size());
            try {
                for (CompletableFuture<FetchResult> f : futures) {
                    results.add(f.get());
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                futures.forEach(f -> f.cancel(true));
                throw new MojoFailureException("Interrupted while resolving SBOMs", e);
            } catch (ExecutionException e) {
                // SbomFetcher.fetch catches everything it throws, so this only fires
                // for a truly unexpected failure (JVM error, task cancellation, etc.).
                throw new MojoExecutionException("Unexpected failure resolving SBOM", e.getCause());
            }
            return results;
        } finally {
            pool.shutdown();
            try {
                if (!pool.awaitTermination(10, TimeUnit.SECONDS)) {
                    pool.shutdownNow();
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                pool.shutdownNow();
            }
        }
    }

    private void summarize(List<FetchResult> results) {
        long fetched = results.stream().filter(r -> r.status() == FetchResult.Status.FETCHED).count();
        long missing = results.stream().filter(r -> r.status() == FetchResult.Status.NOT_AVAILABLE).count();
        long errored = results.stream().filter(r -> r.status() == FetchResult.Status.ERROR).count();
        getLog().info("Chainguard SBOMs: " + fetched + " fetched, "
                + missing + " not available, " + errored + " errored.");
        for (FetchResult r : results) {
            if (r.status() == FetchResult.Status.ERROR) {
                getLog().warn(r.coordinate() + " [" + r.kind() + "]: " + r.errorMessage());
            }
        }
    }

    private static Set<String> parseScopes(String value) {
        if (value == null || value.isEmpty()) {
            return new HashSet<>(Arrays.asList("compile", "runtime"));
        }
        return Arrays.stream(value.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .map(s -> s.toLowerCase(java.util.Locale.ROOT))
                .collect(Collectors.toCollection(HashSet::new));
    }
}
