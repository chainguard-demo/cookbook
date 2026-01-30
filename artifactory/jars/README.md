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

#### Example Output Data

| groupId             | artifactId | version                               | downloads | downloaded                  |
|---------------------|------------|----------------------------------------|-----------|-----------------------------|
| org.springframework | boot       | spring-boot                            | 21        | 2025-09-08T17:02:19.768Z    |
| org.springframework | boot       | spring-boot-actuator                  | 21        | 2025-09-08T17:02:27.967Z    |
| org.springframework | boot       | spring-boot-actuator-autoconfigure    | 21        | 2025-09-08T17:02:27.930Z    |
| org.springframework | boot       | spring-boot-autoconfigure             | 21        | 2025-09-08T17:02:19.650Z    |
| org.springframework | boot       | spring-boot-devtools                  | 21        | 2025-09-08T17:02:38.570Z    |
| org.springframework | boot       | spring-boot-starter                   | 21        | 2025-09-08T17:02:19.463Z    |
| org.springframework | boot       | spring-boot-starter-actuator          | 21        | 2025-09-08T17:02:27.838Z    |
| org.springframework | boot       | spring-boot-starter-cache             | 21        | 2025-09-08T17:02:19.368Z    |
| org.springframework | boot       | spring-boot-starter-jdbc              | 21        | 2025-09-08T17:02:19.465Z    |

