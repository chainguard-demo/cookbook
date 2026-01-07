# AGENTS.md

This document describes strategies for converting Dockerfiles to use Chainguard
images.

## Clarify Instructions

If you're asked to convert a Dockerfile to Chainguard, before doing anything
else, you should check for a `chainguard-preferences.txt` file in the current
directory and ensure that it answers the following questions:

1. What is the Chainguard organization name? Each Chainguard customer has their
   own organization and it will be referred to generically as `ORGANIZATION` in
   these instructions.
2. Is FIPS required? Chainguard offers FIPS compliant images that have the
   suffix `-fips`. For instance: `python-fips`.
3. Should images be pulled directly from `cgr.dev`? Or, if images are
   hosted/proxied from another repository, what is that repository?
4. Should you try and build an image from the Dockerfile to validate the
   conversion worked?
5. Should you try and run the image to validate the conversion worked?

If the file doesn't exist or its missing answers for one or more of these
questions, you should ask the user to provide the missing details.

## Backup the Dockerfile

You should backup the old Dockerfile by prepending `old.` to it. For instance,
`Dockerfile` -> `old.Dockerfile`.

Then you can modify the original file directly.

## Converting FROM statements

You should replace images defined in `FROM` lines with the equivalent
Chainguard image.

For instance:

```
FROM python:3.12
```

Would become:

```
FROM cgr.dev/ORGANIZATION/python:3.12-dev
```

Or if FIPS images are required:

```
FROM cgr.dev/ORGANIZATION/python-fips:3.12-dev
```

Or, if Chainguard images are hosted in a custom repository:

```
FROM custom.registry.host/chainguard/ORGANIZATION/python:3.12-dev
```

### Tags

Tags for Chainguard Images will almost always follow the semantic versioning of
the upstream project.

For instance:

```
cgr.dev/ORGANIZATION/python:3.12
cgr.dev/ORGANIZATION/python:3.12-dev
cgr.dev/ORGANIZATION/php:8.3.29
cgr.dev/ORGANIZATION/php:8.3.29-dev
```

One exception are Java images which include a `openjdk-` prefix:

```
cgr.dev/ORGANIZATION/jdk:openjdk-25.0.1
cgr.dev/ORGANIZATION/jdk:openjdk-25.0.1-dev
cgr.dev/ORGANIZATION/jre:openjdk-11.0
cgr.dev/ORGANIZATION/jre:openjdk-11.0-dev
```

And maven images which include the version of Maven and the JDK version:

```
cgr.dev/ORGANIZATION/maven:3.9-jdk25
cgr.dev/ORGANIZATION/maven:3.9.12-jdk25-dev
```

### Dev Variants

Every Chainguard image tag has a corresponding `-dev` variant. So for instance,
`python:3.12` has a corresponding `python:3.12-dev` tag. You should default to
using the `-dev` tag because it has more utilities in it and is less likely to
cause issues.

One known exception is `chainguard-base` which has no `-dev` variant. You should
always use the `latest` tag.

### Versioning

You should maintain the semantic versioning of the tags in the existing
Dockerfile. For instance, `python:3.9.18-slim` would become
`cgr.dev/ORGANIZATION/python:3.9.18-dev`, using the same patch version as the
original reference.

### Digests

If the existing reference uses a digest reference (i.e
`python:3.12-slim-bookworm@sha256:a866731a6b71c4a194a845d86e06568725e430ed21821d0c52e4efb385cf6c6f`)
then you should also include a digest. Naturally, the digest will be different
for the Chainguard image. You can figure out the digest in a few ways, depending
on the available tooling:

```
# With crane (prefer this if it is available)
crane digest cgr.dev/ORGANIZATION/python:3.12-dev

# Or, with docker
docker pull cgr.dev/ORGANIZATION/python:3.12-dev
docker inspect --format='{{index .RepoDigests 0}}' cgr.dev/ORGANIZATION/python:3.12-dev
```

### Mapping Images

Generally the naming of the Chainguard image will follow the upstream image.

For instance, `php` becomes `cgr.dev/ORGANIZATION/php`.

In cases where the upstream uses subrepositories, Chainguard will typically join
the subrepositories together, replacing `/` with `-`.

For instance, `mcr.microsoft.com/dotnet/sdk` becomes `cgr.dev/ORGANIZATION/dotnet-sdk`.

If it isn't clear which Chainguard image is equivalent to the image in the
`FROM` line, you can list all the base images in the Chainguard catalog with
this query, which can be helpful in finding the appropriate image.

```
curl \
    -XPOST \
    -d '{"query":"query OrganizationImageCatalog($organization: ID!) {\n  repos(filter: {uidp: {childrenOf: $organization}}) {\n    name\n    aliases\n  catalogTier\n  }\n}","variables":{"excludeDates":true,"excludeEpochs":true,"organization":"ce2d1984a010471142503340d670612d63ffb9f6"}}' \
    -H 'Content-Type: application/json' \
    'https://data.chainguard.dev/query?id=PrivateImageCatalog' \
    | jq -r '.data.repos[] | select(.catalogTier == "BASE")'
```

In general, the Chainguard image will have the same or a similar name as the
upstream image.

The `aliases` field in the output of the curl command describes upstream images
that are equivalent or similar to the Chainguard image, so this can also be used
to infer which image to swap in.

You can also search for images at `https://images.chainguard.dev/directory`.

### Chainguard Base

Chainguard have their own Linux distribution, so they don't have equivalent
images for `alpine`, `debian`, `ubuntu` etc. 

Where the Dockerfile is using one of these generic bases, you should swap it
to use `chainguard-base` (or `chainguard-base-fips` for FIPS). You should
always use the `latest` tag with `chainguard-base`. There is no `latest-dev`
tag for `chainguard-base`, so don't 1use that.

## Multi Stage Builds

### Dev Variants

Where there are multiple `FROM` lines in a Dockerfile, you should try to use a
non-dev variant (i.e `cgr.dev/ORGANIZATION/python:3.12`) for the final stage
unless there are any `RUN` lines that follow it (in which case you need a shell,
and therefore a `-dev` image).

### COPY Permissions

A common issue with multi stage builds is that files are created in the first
stage by the `root` user, which are then not accessible to the `65532` user in
the final stage. You can mitigate this by ensuring files copied into the final
stage belong to the `65532` user:

```
COPY --from=build --chown=65532:65532 /app .
```

## Adding Packages with `apk`

Unlike other Linux distributions that may use `apt`, `yum` or `dnf` to install
packages, Chainguard images use `apk` to manage packages.

This means that you should convert instances of `apt`, `yum` and `dnf` to `apk`
in `RUN` lines.

For instance, for `apt`, lines like this:

```
RUN apt-get update \
    && apt-get install -y software-properties-common=0.99.22.9 \
    && add-apt-repository ppa:libreoffice/libreoffice-still \
    && apt-get install -y libreoffice \
    && apt-get clean
```

Should become:

```
RUN apk --no-cache add libreoffice
```

And lines like this:

```
RUN yum update -y && \
    yum -y install httpd php php-cli php-common && \
    yum clean all && \
    rm -rf /var/cache/yum/*

RUN dnf update -y && \
    dnf -y install httpd php php-cli php-common && \
    dnf clean all

RUN microdnf update -y && \
    microdnf -y install httpd php php-cli php-common && \
    microdnf clean all
```

Should become:

```
RUN apk add --no-cache httpd php php-cli php-common
```

### Root Permissions

Chainguard images typically run as a non root user with the UID `65532`, rather
than `root`. You will need to switch to `root` before running `apk add` and
then revert back to `65532` after.

```
USER root
RUN apk add --no-cache httpd php php-cli php-common
USER 65532
```

## Users

As mentioned above, Chainguard images typically run as a non root user with the
UID `65532`, rather than `root`. Commonly, this user is called `nonroot`, but
not always. For instance, in the `node` image the user is called `node`.

To be safe, always prefer the UID when issuing `USER` statements or changing
the permissions of files.

You should switch to the `root` user with `USER root` before running privileged
commands (like `npm`) and then use `USER 65532` after to return to the non root
user.

You can figure out which user the image is configured to use by querying the
image configuration. How you do that depends on the tools you have available:

```
# With crane.
crane config cgr.dev/chainguard/python | jq -r '.config.User'

# With docker.
docker inspect --format='{{ .Config.User }}' cgr.dev/chainguard/python
```

You can also find this information in the Specifications tab of the Chainguard
Image Directory:

```
https://images.chainguard.dev/directory/image/python/specifications
```

## Entrypoints

Unlike upstream images, the entrypoint for Chainguard base images is typically
the runtime interpreter for the given language (i.e `java`, `python`, `php`)
rather than a shell like `sh` or `bash`.

This means that a `CMD` like `CMD ["python", "app.py"]` will cause an error in a
Chainguard images because it translates to running `python python app.py`.

We should prefer to use explicit entrypoints like:

```
ENTRYPOINT ["python", "app.py"]
```

## PHP

It's common in Dockerfiles that build PHP applications to install composer in
this way:

```
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer
```

This is unnecessary when using the Chainguard `php` image because `composer` is
already included in the `-dev` tags. Therefore, you can remove any lines that
install composer.

## Testing

Here's how to test your conversion:

1. After you've modified the Dockerfile, try to build it, assuming the user
indicated you should.
2. Troubleshoot any failures you find.
3. Once the image is built, try to run it and confirm it behaves as expected. 
   - If you aren't sure how to validate that the image performs correctly, ask
     the user to give you some direction on the best way.
4. Troubleshoot any failures (refer to Troubleshooting below)

## Troubleshooting

### Missing Shell

If you get errors complaining about a missing `sh` or `bash`, then ensure you
are using a `-dev` image, which provides a shell.

### Permission Denied

If you get errors complaining about permissions, then it's probably to
do with the non root user. Switch to `USER root` temporarily and then switch
back to `USER 65532` once you've completed the privileged operation.

### Package Not Found

If you find that a package name doesn't exist in Chainguard's repositories, you
can drop into a `-dev` image and use `apk search` to find the equivalent based
on naming:

```
docker run -it --rm --entrypoint bash -u root cgr.dev/ORGANIZATION/python:3.12-dev

# apk update
# apk search -q <package name or substring>
# apk search -q cmd:<specific command name>
```

Another thing you may consider trying is seeing which files are provided by the
upstream:

```
docker run -it --rm debian:bookworm-slim

# apt update
# apt install mariadb-client
# dpkg -L mariadb-client
```

And then you can try and find packages that provide those files:

```
docker run -it --rm --entrypoint bash -u root cgr.dev/ORGANIZATION/python:3.12-dev

# apk update
# apk search -q cmd:mysqlshow
```

### Check the Overview page

The Overview page for the Chainguard image typically includes information that
is helpful when performing a migration.

```
https://images.chainguard.dev/directory/image/<image-name>/overview
```

If you run into issues, it is worth checking this page for guidance.

