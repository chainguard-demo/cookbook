package example.chainguard.sbom;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotSame;

import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.List;

import org.eclipse.aether.repository.RemoteRepository;
import org.eclipse.aether.repository.RepositoryPolicy;
import org.junit.jupiter.api.Test;

class SbomFetcherTest {

    @Test
    void coordinateOmitsEmptyClassifier() {
        assertEquals("org.apache.commons:commons-compress:1.23.0",
                SbomFetcher.coordinate("org.apache.commons", "commons-compress", null, "1.23.0"));
        assertEquals("org.apache.commons:commons-compress:1.23.0",
                SbomFetcher.coordinate("org.apache.commons", "commons-compress", "", "1.23.0"));
    }

    @Test
    void coordinateIncludesClassifierWhenPresent() {
        assertEquals("com.example:widget:sources:1.0.0",
                SbomFetcher.coordinate("com.example", "widget", "sources", "1.0.0"));
    }

    @Test
    void destinationForUsesMavenLayout() {
        Path base = Paths.get("target", "chainguard-sboms");
        Path dest = SbomFetcher.destinationFor(base,
                "org.apache.commons", "commons-compress", "1.23.0",
                "commons-compress-1.23.0.spdx.json");
        assertEquals(
                base.resolve("org").resolve("apache").resolve("commons")
                        .resolve("commons-compress").resolve("1.23.0")
                        .resolve("commons-compress-1.23.0.spdx.json"),
                dest);
    }

    @Test
    void withIgnoredChecksumsRewritesBothPolicies() {
        RemoteRepository input = new RemoteRepository.Builder("chainguard", "default", "https://libraries.cgr.dev/java/")
                .setReleasePolicy(new RepositoryPolicy(true,
                        RepositoryPolicy.UPDATE_POLICY_DAILY,
                        RepositoryPolicy.CHECKSUM_POLICY_FAIL))
                .setSnapshotPolicy(new RepositoryPolicy(false,
                        RepositoryPolicy.UPDATE_POLICY_NEVER,
                        RepositoryPolicy.CHECKSUM_POLICY_WARN))
                .build();

        List<RemoteRepository> out = SbomFetcher.withIgnoredChecksums(Arrays.asList(input));

        assertEquals(1, out.size());
        RemoteRepository relaxed = out.get(0);
        assertNotSame(input, relaxed);
        assertEquals(RepositoryPolicy.CHECKSUM_POLICY_IGNORE,
                relaxed.getPolicy(false).getChecksumPolicy());
        assertEquals(RepositoryPolicy.CHECKSUM_POLICY_IGNORE,
                relaxed.getPolicy(true).getChecksumPolicy());
        // Other policy attributes (enabled, update policy) must be preserved.
        assertEquals(true, relaxed.getPolicy(false).isEnabled());
        assertEquals(RepositoryPolicy.UPDATE_POLICY_DAILY,
                relaxed.getPolicy(false).getUpdatePolicy());
        assertEquals(false, relaxed.getPolicy(true).isEnabled());
        assertEquals(RepositoryPolicy.UPDATE_POLICY_NEVER,
                relaxed.getPolicy(true).getUpdatePolicy());
    }
}
