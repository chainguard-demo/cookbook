variable "name" {
  description = "Prefix used for the two proxy repositories and the group repository. The module appends a `-js-` infix to disambiguate JavaScript repos from other ecosystems. For example, name = \"corp\" yields corp-js-chainguard, corp-js-public, and corp-js-all."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.name))
    error_message = "name must be lowercase alphanumeric with optional hyphens, and must start with a letter or digit."
  }
}

variable "chainguard_libraries_url" {
  description = "Base URL of the Chainguard Libraries service (no trailing slash)."
  type        = string
  default     = "https://libraries.cgr.dev"

  validation {
    condition     = can(regex("^https?://[^/]+$", var.chainguard_libraries_url))
    error_message = "chainguard_libraries_url must be a scheme + host with no path or trailing slash, e.g. https://libraries.cgr.dev."
  }
}

variable "chainguard_index_path" {
  description = "Path segment for the Chainguard JavaScript index, appended to chainguard_libraries_url."
  type        = string
  default     = "javascript"
}

variable "npm_registry_url" {
  description = "URL of the upstream npm registry used as fallback."
  type        = string
  default     = "https://registry.npmjs.org"
}

variable "chainguard_username" {
  description = "Username (identity ID) used to authenticate to the Chainguard Libraries service. Retrieve with chainctl auth."
  type        = string
  sensitive   = true
}

variable "chainguard_password" {
  description = "Password (token) used to authenticate to the Chainguard Libraries service. Retrieve with chainctl auth."
  type        = string
  sensitive   = true
}

variable "blob_store_name" {
  description = "Name of an existing Nexus blob store to use for storing cached artifacts."
  type        = string
  default     = "default"
}
