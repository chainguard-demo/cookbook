locals {
  remediated_name = "${var.name}-java-chainguard-remediated"
  chainguard_name = "${var.name}-java-chainguard"
  public_name     = "${var.name}-java-public"
  group_name      = "${var.name}-java-all"

  remediated_url = "${var.chainguard_libraries_url}/${var.remediated_index_path}/"
  chainguard_url = "${var.chainguard_libraries_url}/${var.chainguard_index_path}/"
}

# Proxy: Chainguard remediated Java index (highest priority).
resource "nexus_repository_maven_proxy" "remediated" {
  name   = local.remediated_name
  online = true

  storage {
    blob_store_name                = var.blob_store_name
    strict_content_type_validation = true
  }

  maven {
    version_policy = "RELEASE"
    layout_policy  = "STRICT"
  }

  proxy {
    remote_url       = local.remediated_url
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

# Proxy: Chainguard standard Java index.
resource "nexus_repository_maven_proxy" "chainguard" {
  name   = local.chainguard_name
  online = true

  storage {
    blob_store_name                = var.blob_store_name
    strict_content_type_validation = true
  }

  maven {
    version_policy = "RELEASE"
    layout_policy  = "STRICT"
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

# Proxy: Upstream Maven Central (fallback for artifacts not in Chainguard).
resource "nexus_repository_maven_proxy" "public" {
  name   = local.public_name
  online = true

  storage {
    blob_store_name                = var.blob_store_name
    strict_content_type_validation = true
  }

  maven {
    version_policy = "RELEASE"
    layout_policy  = "STRICT"
  }

  proxy {
    remote_url       = var.maven_central_url
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

# Group: aggregates the three proxies with the requested fallback order.
resource "nexus_repository_maven_group" "all" {
  name   = local.group_name
  online = true

  storage {
    blob_store_name                = var.blob_store_name
    strict_content_type_validation = true
  }

  group {
    member_names = [
      nexus_repository_maven_proxy.remediated.name,
      nexus_repository_maven_proxy.chainguard.name,
      nexus_repository_maven_proxy.public.name,
    ]
  }
}
