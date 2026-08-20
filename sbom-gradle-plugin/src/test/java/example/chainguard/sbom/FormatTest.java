package example.chainguard.sbom;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class FormatTest {

    @Test
    void spdxHasExtensionOnlyNoClassifier() {
        assertEquals("spdx.json", Format.SPDX_JSON.extension());
        assertEquals("", Format.SPDX_JSON.classifierFor(null));
        assertEquals("", Format.SPDX_JSON.classifierFor(""));
    }

    @Test
    void slsaAttestation() {
        assertEquals("slsa-attestation.json", Format.SLSA_ATTESTATION.extension());
        assertEquals("", Format.SLSA_ATTESTATION.classifierFor(""));
    }

    @Test
    void classifierPassesThroughExistingArtifactClassifier() {
        // Neither current sidecar has a classifier suffix, so an artifact
        // classifier passes through verbatim.
        assertEquals("sources", Format.SPDX_JSON.classifierFor("sources"));
        assertEquals("sources", Format.SLSA_ATTESTATION.classifierFor("sources"));
    }
}
