locals {
  public_name = "${var.name}-js-public"
  needs_auth  = var.username != "" && var.password != ""
}

# Proxy: npm registry (defaults to upstream Chainguard; can point at any npm registry).
resource "nexus_repository_npm_proxy" "public" {
  name   = local.public_name
  online = true

  storage {
    blob_store_name                = var.blob_store_name
    strict_content_type_validation = false
  }

  proxy {
    remote_url       = var.npm_registry_url
    content_max_age  = 1440
    metadata_max_age = 1440
  }

  negative_cache {
    enabled = true
    ttl     = 1440
  }

  http_client {
    blocked    = false
    auto_block = true

    dynamic "authentication" {
      for_each = local.needs_auth ? [1] : []
      content {
        type     = "username"
        username = var.username
        password = var.password
      }
    }
  }
}
