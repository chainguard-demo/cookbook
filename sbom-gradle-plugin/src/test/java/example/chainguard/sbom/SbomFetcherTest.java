package example.chainguard.sbom;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.nio.file.Path;
import java.nio.file.Paths;

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
        Path base = Paths.get("build", "chainguard-sboms");
        Path dest = SbomFetcher.destinationFor(base,
                "org.apache.commons", "commons-compress", "1.23.0",
                "commons-compress-1.23.0.spdx.json");
        assertEquals(
                base.resolve("org").resolve("apache").resolve("commons")
                        .resolve("commons-compress").resolve("1.23.0")
                        .resolve("commons-compress-1.23.0.spdx.json"),
                dest);
    }
}
