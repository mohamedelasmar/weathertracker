provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
}

# ===================================================
# OCI Object Storage Static Website Hosting
# Weather Tracker Frontend Infrastructure
# ===================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }
}


# ===================================================
# Locals
# ===================================================

locals {
  bucket_name = var.bucket_name != "" ? var.bucket_name : "${var.project_name}-${var.environment}-frontend"
  
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Component   = "static-website"
    ManagedBy   = "terraform"
  }
}

resource "oci_objectstorage_bucket" "static_website_bucket" {
  compartment_id = var.compartment_ocid
  name           = local.bucket_name
  namespace      = data.oci_objectstorage_namespace.ns.namespace

  # Enable public access for static website hosting
  access_type = "ObjectRead"

  # Enable versioning for backup purposes
  versioning = "Enabled"

  # Auto-tiering for cost optimization
  auto_tiering = "InfrequentAccess"

  # Storage tier
  storage_tier = "Standard"

  # Metadata
  metadata = {
    "purpose"     = "static-website-hosting"
    "application" = "weather-tracker"
    "created-by"  = "terraform"
  }

  # Tags
  freeform_tags = local.common_tags
}

# ===================================================
# PAR (Pre-Authenticated Request) for Public Access
# ===================================================

resource "oci_objectstorage_preauthrequest" "static_website_par" {
  access_type  = "ObjectRead"
  bucket       = oci_objectstorage_bucket.static_website_bucket.name
  name         = "${local.bucket_name}-public-read"
  namespace    = data.oci_objectstorage_namespace.ns.namespace
  time_expires = timeadd(timestamp(), "8760h") # 1 year from now

  # Allow access to all objects in the bucket
  object_name = "*"
}
## CSS file (if you want to separate CSS)
resource "oci_objectstorage_object" "css_files" {
  for_each = fileset("${path.module}/assets/css/", "*.css")

  bucket    = oci_objectstorage_bucket.static_website_bucket.name
  object    = "css/${each.value}"
  namespace = data.oci_objectstorage_namespace.ns.namespace
  source    = "${path.module}/assets/css/${each.value}"

  content_type  = "text/css"
  cache_control = "public, max-age=86400" # 24 hours

  depends_on = [oci_objectstorage_bucket.static_website_bucket]
}

# JavaScript files (if you want to separate JS)
resource "oci_objectstorage_object" "js_files" {
  for_each = fileset("${path.module}/assets/js/", "*.js")

  bucket    = oci_objectstorage_bucket.static_website_bucket.name
  object    = "js/${each.value}"
  namespace = data.oci_objectstorage_namespace.ns.namespace
  source    = "${path.module}/assets/js/${each.value}"

  content_type  = "application/javascript"
  cache_control = "public, max-age=86400" # 24 hours

  depends_on = [oci_objectstorage_bucket.static_website_bucket]
}

# Images and other assets
resource "oci_objectstorage_object" "image_files" {
  for_each = fileset("${path.module}/assets/images/", "*.{png,jpg,jpeg,gif,svg,ico}")

  bucket    = oci_objectstorage_bucket.static_website_bucket.name
  object    = "images/${each.value}"
  namespace = data.oci_objectstorage_namespace.ns.namespace
  source    = "${path.module}/assets/images/${each.value}"

  content_type = lookup({
    "png"  = "image/png"
    "jpg"  = "image/jpeg"
    "jpeg" = "image/jpeg"
    "gif"  = "image/gif"
    "svg"  = "image/svg+xml"
    "ico"  = "image/x-icon"
  }, split(".", each.value)[length(split(".", each.value)) - 1], "application/octet-stream")

  cache_control = "public, max-age=2592000" # 30 days

  depends_on = [oci_objectstorage_bucket.static_website_bucket]
}

# ===================================================
# Outputs
# ===================================================

output "bucket_name" {
  description = "Name of the created Object Storage bucket"
  value       = oci_objectstorage_bucket.static_website_bucket.name
}

output "bucket_namespace" {
  description = "Namespace of the Object Storage bucket"
  value       = data.oci_objectstorage_namespace.ns.namespace
}

output "bucket_url" {
  description = "Direct URL to access the bucket"
  value       = "https://objectstorage.${data.oci_identity_region_subscriptions.home_region_subscriptions.region_subscriptions[0].region_name}.oraclecloud.com/n/${data.oci_objectstorage_namespace.ns.namespace}/b/${oci_objectstorage_bucket.static_website_bucket.name}/o/"
}

output "website_url" {
  description = "URL to access the static website"
  value       = "${oci_objectstorage_preauthrequest.static_website_par.access_uri}index.html"
}

output "par_access_uri" {
  description = "Pre-authenticated request URI for public access"
  value       = oci_objectstorage_preauthrequest.static_website_par.access_uri
  sensitive   = true
}

output "par_expires" {
  description = "When the pre-authenticated request expires"
  value       = oci_objectstorage_preauthrequest.static_website_par.time_expires
}