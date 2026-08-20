package example.chainguard.sbom;

/**
 * Outcome of attempting to resolve one sidecar for one artifact.
 */
public final class FetchResult {

    public enum Status { FETCHED, NOT_AVAILABLE, ERROR }

    private final String coordinate;
    private final Format kind;
    private final Status status;
    private final String errorMessage;

    private FetchResult(String coordinate, Format kind, Status status, String errorMessage) {
        this.coordinate = coordinate;
        this.kind = kind;
        this.status = status;
        this.errorMessage = errorMessage;
    }

    public static FetchResult fetched(String coordinate, Format kind) {
        return new FetchResult(coordinate, kind, Status.FETCHED, null);
    }

    public static FetchResult notAvailable(String coordinate, Format kind) {
        return new FetchResult(coordinate, kind, Status.NOT_AVAILABLE, null);
    }

    public static FetchResult error(String coordinate, Format kind, String message) {
        return new FetchResult(coordinate, kind, Status.ERROR, message);
    }

    public String coordinate() { return coordinate; }
    public Format kind() { return kind; }
    public Status status() { return status; }
    public String errorMessage() { return errorMessage; }
}
