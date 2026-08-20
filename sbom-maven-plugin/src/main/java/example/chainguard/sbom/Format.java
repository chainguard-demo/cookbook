package example.chainguard.sbom;

/**
 * Sidecar file types published alongside Chainguard-built jars. Both use a
 * compound extension with no classifier ({@code foo-1.0.spdx.json},
 * {@code foo-1.0.slsa-attestation.json}). Each kind records both so callers
 * can build a Maven {@code Artifact} coordinate that resolves to the right URL.
 */
public enum Format {

    SPDX_JSON("", "spdx.json"),
    SLSA_ATTESTATION("", "slsa-attestation.json");

    private final String classifierSuffix;
    private final String extension;

    Format(String classifierSuffix, String extension) {
        this.classifierSuffix = classifierSuffix;
        this.extension = extension;
    }

    public String extension() {
        return extension;
    }

    /**
     * Compose the effective Maven classifier for this sidecar given an
     * artifact's own classifier. When the artifact has no classifier, the
     * sidecar's classifier suffix is used verbatim (or empty). Otherwise the
     * two are joined with a dash, following Maven's usual convention.
     */
    public String classifierFor(String artifactClassifier) {
        String base = artifactClassifier == null ? "" : artifactClassifier;
        if (classifierSuffix.isEmpty()) return base;
        return base.isEmpty() ? classifierSuffix : base + "-" + classifierSuffix;
    }
}
