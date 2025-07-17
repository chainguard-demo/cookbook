# latest-tags-by-package

This is a Python script that finds the latest tags in a repository, aggregated
by the main package version.

It uses the `dev.chainguard.package.main` annotation to identify the main
package and `org.opencontainers.image.created` to sort the tags. As such, this
only works for Chainguard images.

Some tags are filtered out of the results:

- `-dev` tags
- Revision tags like `3.10.18-r0`
- The `latest` tag

The script will return results for all packages, even those that are EOL and
out of support. Please only use tags for versions that are supported.

## Usage

Run the script with the target repository as the first argument.

The script doesn't handle the authentication flow, so in this example we're
generating a token with `crane` and passing it in.

```
export REPO=cgr.dev/your.org/python

python3 -m venv .
source bin/activate
pip3 install -r requirements.txt

./main.py --token $(crane auth token ${REPO} | jq -r .token) ${REPO}
```

The output will look like this:

```
cgr.dev/your.org/python (python-3.13)
        3
        3.13
        3.13.5
        3.13.4
        3.13.3
cgr.dev/your.org/python (python-3.10)
        3.10
        3.10.18
        3.10.17
        3.10.16
cgr.dev/your.org/python (python-3.11)
        3.11
        3.11.13
        3.11.12
        3.11.11
cgr.dev/your.org/python (python-3.12)
        3.12
        3.12.11
        3.12.10
        3.12.9
        3.12.8
cgr.dev/your.org/python (python-3.9)
        3.9
        3.9.23
        3.9.22
        3.9.21
```
