locals {
  remediated_name = "${var.name}-py-chainguard-remediated"
  chainguard_name = "${var.name}-py-chainguard"
  public_name     = "${var.name}-py-public"
  group_name      = "${var.name}-py-all"

  remediated_url = "${var.chainguard_libraries_url}/${var.remediated_index_path}/"
  chainguard_url = "${var.chainguard_libraries_url}/${var.chainguard_index_path}/"
}

# Proxy: Chainguard remediated Python index (highest priority).
#
# Known issue (Nexus 3.92.1): wheel downloads through this proxy currently
# return 404. Upstream's 302 Location encodes the `+` in `+cgr.N` versions
# as `%2B`; the AWS SigV4 signature on the Cloudflare R2 pre-signed URL is
# computed over the encoded form. Apache HttpClient inside Nexus decodes
# `%2B` -> `+` when following the redirect, R2 rejects with
# SignatureDoesNotMatch, and Nexus surfaces a 404 to the client. The
# simple-index responses and the (no-`+`) standard Chainguard proxy below
# work end-to-end. No exposed Nexus config knob avoids the redirect-target
# URL normalization.
resource "nexus_repository_pypi_proxy" "remediated" {
  name   = local.remediated_name
  online = true

  storage {
    blob_store_name                = var.blob_store_name
    strict_content_type_validation = false
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

# Proxy: Chainguard standard Python index.
resource "nexus_repository_pypi_proxy" "chainguard" {
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

# Proxy: Upstream public PyPI (fallback for packages not in Chainguard).
resource "nexus_repository_pypi_proxy" "public" {
  name   = local.public_name
  online = true

  storage {
    blob_store_name                = var.blob_store_name
    strict_content_type_validation = false
  }

  proxy {
    remote_url       = var.pypi_url
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
resource "nexus_repository_pypi_group" "all" {
  name   = local.group_name
  online = true

  storage {
    blob_store_name                = var.blob_store_name
    strict_content_type_validation = false
  }

  group {
    member_names = [
      nexus_repository_pypi_proxy.remediated.name,
      nexus_repository_pypi_proxy.chainguard.name,
      nexus_repository_pypi_proxy.public.name,
    ]
  }
}
