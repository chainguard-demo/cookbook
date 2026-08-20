package example.chainguard.sbom;

import java.io.File;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import org.gradle.api.DefaultTask;
import org.gradle.api.GradleException;
import org.gradle.api.artifacts.Configuration;
import org.gradle.api.artifacts.ResolvedArtifact;
import org.gradle.api.provider.ListProperty;
import org.gradle.api.provider.Property;
import org.gradle.api.tasks.Input;
import org.gradle.api.tasks.OutputDirectory;
import org.gradle.api.tasks.TaskAction;

/**
 * Walks a resolved Gradle configuration and downloads every available Chainguard
 * sidecar (SPDX SBOM, CycloneDX SBOM, SLSA attestation) into the configured
 * output directory. Dependencies without a Chainguard build are reported as
 * "not available" in the final summary — the plugin only fetches what it can.
 */
public abstract class CollectSbomsTask extends DefaultTask {

    @OutputDirectory
    public abstract Property<File> getOutputDirectory();

    @Input
    public abstract ListProperty<Format> getFormats();

    @Input
    public abstract Property<String> getConfigurationName();

    @Input
    public abstract Property<Boolean> getSkip();

    @TaskAction
    public void collect() {
        if (getSkip().get()) {
            getLogger().lifecycle("collectSboms skipped by configuration.");
            return;
        }

        String configName = getConfigurationName().get();
        Configuration config = getProject().getConfigurations().findByName(configName);
        if (config == null) {
            throw new GradleException("No configuration named '" + configName + "' found on this project.");
        }
        if (!config.isCanBeResolved()) {
            throw new GradleException("Configuration '" + configName + "' is not resolvable.");
        }

        List<ResolvedArtifact> artifacts = collectTargets(config);
        if (artifacts.isEmpty()) {
            getLogger().lifecycle("No dependencies in configuration '" + configName + "' to collect SBOMs for.");
            return;
        }

        if (getProject().getRepositories().isEmpty()) {
            throw new GradleException(
                    "No repositories configured to resolve SBOMs. "
                    + "Configure Chainguard Libraries as a repository (see "
                    + "https://edu.chainguard.dev/chainguard/libraries/java/build-configuration/).");
        }
        getLogger().lifecycle("Resolving SBOMs for " + artifacts.size() + " dependencies via "
                + getProject().getRepositories().size() + " configured repositories.");

        Path outputBase = getOutputDirectory().get().toPath();
        SbomFetcher fetcher = new SbomFetcher(getProject(), outputBase, getLogger());

        List<Format> formats = effectiveFormats();
        List<FetchResult> results = new ArrayList<>();
        for (ResolvedArtifact a : artifacts) {
            for (Format format : formats) {
                results.add(fetcher.fetch(
                        a.getModuleVersion().getId().getGroup(),
                        a.getModuleVersion().getId().getName(),
                        a.getModuleVersion().getId().getVersion(),
                        a.getClassifier(),
                        format));
            }
        }
        summarize(results);

        long errored = results.stream().filter(r -> r.status() == FetchResult.Status.ERROR).count();
        if (errored > 0) {
            throw new GradleException(errored + " SBOM fetch(es) errored (see warnings above). "
                    + "Missing sidecars (not-available) do not fail the build; only unexpected errors do.");
        }
    }

    private List<ResolvedArtifact> collectTargets(Configuration config) {
        List<ResolvedArtifact> targets = new ArrayList<>();
        for (ResolvedArtifact a : config.getResolvedConfiguration().getResolvedArtifacts()) {
            if (!"jar".equals(a.getType())) continue;
            targets.add(a);
        }
        return targets;
    }

    private List<Format> effectiveFormats() {
        List<Format> f = getFormats().get();
        return f == null || f.isEmpty() ? Arrays.asList(Format.values()) : f;
    }

    private void summarize(List<FetchResult> results) {
        long fetched = results.stream().filter(r -> r.status() == FetchResult.Status.FETCHED).count();
        long missing = results.stream().filter(r -> r.status() == FetchResult.Status.NOT_AVAILABLE).count();
        long errored = results.stream().filter(r -> r.status() == FetchResult.Status.ERROR).count();
        getLogger().lifecycle("Chainguard SBOMs: " + fetched + " fetched, "
                + missing + " not available, " + errored + " errored.");
        for (FetchResult r : results) {
            if (r.status() == FetchResult.Status.ERROR) {
                getLogger().warn(r.coordinate() + " [" + r.kind() + "]: " + r.errorMessage());
            }
        }
    }
}
