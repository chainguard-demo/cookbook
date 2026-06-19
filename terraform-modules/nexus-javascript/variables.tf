variable "name" {
  description = "Prefix used for the proxy repository. The module appends a `-js-` infix to disambiguate JavaScript repos from other ecosystems. For example, name = \"corp\" yields corp-js-public."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.name))
    error_message = "name must be lowercase alphanumeric with optional hyphens, and must start with a letter or digit."
  }
}

variable "npm_registry_url" {
  description = "URL of the upstream npm registry to proxy. Defaults to the Chainguard JavaScript index."
  type        = string
  default     = "https://libraries.cgr.dev/javascript/"
}

variable "username" {
  description = "Username for authenticating to the upstream registry (the Chainguard identity ID for the default upstream). Leave empty for unauthenticated upstreams."
  type        = string
  default     = ""
  sensitive   = true
}

variable "password" {
  description = "Password/token for authenticating to the upstream registry."
  type        = string
  default     = ""
  sensitive   = true
}

variable "blob_store_name" {
  description = "Name of an existing Nexus blob store to use for storing cached artifacts."
  type        = string
  default     = "default"
}
