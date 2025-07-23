# Overview

Example Azuzure DevOps task to pull & push an organization's cgr.dev private registry to a target ACR repository

* Uses crane only to list tags.
* Uses docker pull to pull each image.
* Re-tags each image.
* Pushes them to an Azure Container Registry (ACR).

### Configuring Chainguard Auth

Please see the following documentation for generating a Pull Token in cgr.dev through the console, or through the chainctl CLI.

https://edu.chainguard.dev/chainguard/chainguard-images/chainguard-registry/authenticating/#authenticating-with-a-pull-token 

1. Generate a Pull Token
2. Set PULL_TOKEN_SECRET securely in the AzureDevops pipeline.

### Configuring Azure ACR Auth

This uses az acr login, which works if your build agent is logged in to Azure or using a managed identity.

Alternatively, you can do docker login $ACR_REGISTRY with a service principal and password if needed.




