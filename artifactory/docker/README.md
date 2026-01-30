# Artifactory Repository Metadata Retrieval

This repository contains scripts to export Docker/OCI image metadata from JFrog
Artifactory as CSV

## Prerequisites

**API Token**: Obtain an API token with appropriate permissions to access
Artifactory resources.

### Generate repo list to query

#### Export your API Token and Artifactory URL

```bash
export token="YOUR_AUTH_TOKEN_HERE"
export artifactory_url="https://foo.jfrog.io/artifactory"
```

#### Give the fetch-oci-and-docker-repos script execute permissions and then run it

```bash
./fetch_repositories.sh repositories.txt
```

#### Manually inspect repo list and remove any repositories that you do not wish to query

### Generate CSV

#### Give the generate-repo-csv script execute permissions and then run it

```bash
./generate-repo-csv.sh
```
