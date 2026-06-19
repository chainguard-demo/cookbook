locals {
  chainguard_name = "${var.name}-js-chainguard"
  public_name     = "${var.name}-js-public"
  group_name      = "${var.name}-js-all"

  chainguard_url = "${var.chainguard_libraries_url}/${var.chainguard_index_path}/"
}

# Proxy: Chainguard npm index (highest priority).
resource "nexus_repository_npm_proxy" "chainguard" {
  name   = local.chainguard_name
  online = true

  storage {
    blob_store_name                = var.blob_store_name
    strict_content_type_validation = false
  }

  proxy {
    remote_url       = local.chainguard_url
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

    authentication {
      type     = "username"
      username = var.chainguard_username
      password = var.chainguard_password
    }
  }
}

# Proxy: Upstream public npm registry (fallback for packages not in Chainguard).
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
  }
}

# Group: aggregates the two proxies with Chainguard first, public npm fallback.
resource "nexus_repository_npm_group" "all" {
  name   = local.group_name
  online = true

  storage {
    blob_store_name                = var.blob_store_name
    strict_content_type_validation = false
  }

  group {
    member_names = [
      nexus_repository_npm_proxy.chainguard.name,
      nexus_repository_npm_proxy.public.name,
    ]
  }
}
