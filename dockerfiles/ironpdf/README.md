# IronPDF on Chainguard Images

A reference Dockerfile that runs [IronPDF](https://ironpdf.com/get-started/ironpdf-docker/) on Chainguard Images instead of `mcr.microsoft.com/dotnet/*`. The included demo app renders one HTML page to PDF as a smoke test.

## Layout

```text
.
├── Dockerfile          # chainguard/dotnet-sdk → chainguard/wolfi-base
├── Makefile            # `make build`, `make run`, `make smoke`, `make clean`
├── app/
│   ├── IronPdfPoc.csproj
│   └── Program.cs          # Renders one HTML page to /out/hello.pdf
└── .github/workflows/generate-pdf.yml  # CI: builds the image and uploads hello.pdf as an artefact
```

## Quick start

You'll need an IronPDF licence key (a 30-day trial is at <https://ironpdf.com/#trial-license>).

```sh
export IRONPDF_LICENSE_KEY="..."
make smoke   # build, run, and verify out/hello.pdf is a real PDF
```

## CI

The `Generate PDF` workflow runs on push, on PR, and on demand (Actions tab → **Run workflow**). It needs an `IRONPDF_LICENSE_KEY` repo secret. Each run uploads the rendered `hello.pdf` to Github artifacts.

## IronPDF Config

IronPDF's standard .NET package is built on a very outdated version of `glibc` and Chromium, which makes it incompatible with Chainguard's base images. To make things happy, we use IronPDF's [`IronPDF.UpdatedChrome.Linux` package](https://ironpdf.com/troubleshooting/ironpdf-native-updated-chrome/) instead, which is built with a more modern version of Chromium. 

The `UpdatedChrome` version has a few constraints, as listed in IronPDF's docs:
> * SingleProcess is not available.
> * Windows Server 2012 is not supported.
> * 32-bit processes are no longer supported.

We also tell IronPDF not to install its own dependencies at runtime (since we pull them in via Chainguard APKs instead), and we disable GPU rendering:

  ```csharp
  Installation.LinuxAndDockerDependenciesAutoConfig = false;
  Installation.ChromeGpuMode = ChromeGpuModes.Disabled;
  ```

## Adapting this to a real app

1. Replace `app/Program.cs` and `app/IronPdfPoc.csproj` with your own project.
2. Keep the two `Installation.*` lines somewhere on the startup path.
3. Keep the `IronPdf.UpdatedChrome.Linux` package reference (rather than `IronPdf.Linux`).
4. Keep the `apk add` list — it is the IronPDF dep set, not anything project-specific.
5. If you target a different .NET version, swap to the appropriate tag (`9`, `8` etc) and update `<TargetFramework>` accordingly.
