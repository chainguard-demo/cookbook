# Artifactory Virtual Repository Java Downloads Retrieval

This repository contains scripts to export recently used JARs from JFrog Artifactory as CSV

## Prerequisites

**API Token**: Obtain an API token with appropriate permissions to access
Artifactory resources.

### Generate repo list to query

#### Export your API Bearer Token (JFrog calls this a Reference Token) and Artifactory URL

```bash
export token="YOUR_BEARER_TOKEN_HERE"
export artifactory_url="https://foo.jfrog.io/artifactory"
export repo="MavenCentral-Group"
```

#### Give the generate-repo-csv script execute permissions and then run it


DAYS=180 by default
BASE_PATH="org/springframework" by default

```bash
./generate-spring-packages-list-csv.sh
```
```bash
DAYS=360 ./generate-spring-packages-list-csv.sh
```
```bash
DAYS=360 BASE_PATH="org/springframework" ./generate-spring-packages-list-csv.sh
```
