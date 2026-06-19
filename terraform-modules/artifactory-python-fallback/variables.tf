variable "name" {
  description = "Prefix used for the three remote repositories and the virtual repository. The module appends a `-py-` infix to disambiguate Python repos from other ecosystems. For example, name = \"corp\" yields corp-py-chainguard-remediated, corp-py-chainguard, corp-py-public, and corp-py-all."
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

variable "description" {
  description = "Optional description applied to the created repositories."
  type        = string
  default     = "Chainguard Libraries for Python"
}

variable "project_key" {
  description = "Optional Artifactory project key to assign the repositories to."
  type        = string
  default     = ""
}

variable "default_deployment_repo" {
  description = "Optional key of a local repository to use as the default deployment target on the virtual repository. Leave empty to disable deployments through the virtual."
  type        = string
  default     = ""
}
