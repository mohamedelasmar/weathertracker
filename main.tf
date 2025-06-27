provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

resource "oci_objectstorage_bucket" "my_bucket" {
  compartment_id = var.compartment_ocid
  name           = "demo-tf-bucket"
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  storage_tier   = "Standard"
  public_access_type = "NoPublicAccess"
  versioning {
    enabled = false
  }
}

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_ocid
}