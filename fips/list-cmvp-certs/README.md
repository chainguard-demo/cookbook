# FIPS: List CMVP Certificates

This script lists the CMVP certificates that apply to a Chainguard FIPS image
by finding CMVP numbers in the image's SBOM.

The inclusion of CMVP certificates in Chainguard's SBOMs [began on Jan
7th
2026](https://www.chainguard.dev/unchained/chainguard-fips-enters-2026-with-openssl-3-1-2-and-better-cmvp-visibility).
In order to support images from before this date, the script also hardcodes the
SBOM indicators that were present on the [FIPS commitment
page](https://www.chainguard.dev/legal/fips-commitment) before the change.

## Usage

Run the script, providing the target image as the first argument.

```sh
./fips-list-cmvp-certs.sh cgr.dev/ORGANIZATION/python-fips
```

The output should look like this:

```
NIST-CMVP-5102  https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/5102
NIST-ESV-191    https://csrc.nist.gov/projects/cryptographic-module-validation-program/entropy-validations/certificate/191
```

For the purposes of fetching CMVP numbers, the platform of the image shouldn't
matter, but you can, optionally, specify a specific platform by providing it
as the second argument.

```sh
./fips-list-cmvp-certs.sh cgr.dev/ORGANIZATION/python-fips linux/arm64
```
