provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
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