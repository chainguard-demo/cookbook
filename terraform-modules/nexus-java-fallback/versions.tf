terraform {
  required_version = ">= 1.5.0"

  required_providers {
    nexus = {
      source  = "datadrivers/nexus"
      version = ">= 2.4.0"
    }
  }
}
