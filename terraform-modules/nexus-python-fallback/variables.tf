variable "name" {
  description = "Prefix used for the three proxy repositories and the group repository. The module appends a `-py-` infix to disambiguate Python repos from other ecosystems. For example, name = \"corp\" yields corp-py-chainguard-remediated, corp-py-chainguard, corp-py-public, and corp-py-all."
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

variable "remediated_index_path" {
  description = "Path segment for the Chainguard remediated Python index, appended to chainguard_libraries_url."
  type        = string
  default     = "python-remediated"
}

variable "chainguard_index_path" {
  description = "Path segment for the Chainguard standard Python index, appended to chainguard_libraries_url."
  type        = string
  default     = "python"
}

variable "pypi_url" {
  description = "URL of the upstream public PyPI used as fallback."
  type        = string
  default     = "https://pypi.org/"
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
