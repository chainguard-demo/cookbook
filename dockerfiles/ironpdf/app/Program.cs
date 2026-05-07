using IronPdf;
using IronPdf.Engines.Chrome;

if (Environment.GetEnvironmentVariable("IRONPDF_LICENSE_KEY") is { Length: > 0 } key)
{
    License.LicenseKey = key;
}

Installation.LinuxAndDockerDependenciesAutoConfig = false;
Installation.ChromeGpuMode = ChromeGpuModes.Disabled;

var output = Environment.GetEnvironmentVariable("OUTPUT_PATH") ?? "/out/hello.pdf";
var pdf = new ChromePdfRenderer().RenderHtmlAsPdf("<h1>hello from IronPDF on Chainguard</h1>");
pdf.SaveAs(output);
Console.WriteLine($"Wrote {output} ({new FileInfo(output).Length} bytes)");
