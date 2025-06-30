provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  region           = "us-ashburn-1"
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
  
  bucket_common_tags = {
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
  freeform_tags = local.bucket_common_tags
}


# ===================================================
# Upload main HTML file (ADD THIS)
# ===================================================
resource "oci_objectstorage_object" "index_html" {
  bucket    = oci_objectstorage_bucket.static_website_bucket.name
  object    = "index.html"
  namespace = data.oci_objectstorage_namespace.ns.namespace
  source    = "${path.module}/index.html"
  content_type = "text/html"
  cache_control = "public, max-age=3600"
  
  depends_on = [oci_objectstorage_bucket.static_website_bucket]
}

# ===================================================
# CSS files (ADD THIS)
# ===================================================
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

# ===================================================
# Service Worker (ADD THIS)
# ===================================================
resource "oci_objectstorage_object" "service_worker" {
  count = fileexists("${path.module}/sw.js") ? 1 : 0
  
  bucket    = oci_objectstorage_bucket.static_website_bucket.name
  object    = "sw.js"
  namespace = data.oci_objectstorage_namespace.ns.namespace
  source    = "${path.module}/sw.js"
  content_type = "application/javascript"
  cache_control = "public, max-age=86400"
  
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

resource "oci_objectstorage_object" "image_files" {
  for_each = length(fileset("${path.module}/assets/images/", "*.{png,jpg,jpeg,gif,svg,ico}")) > 0 ? fileset("${path.module}/assets/images/", "*.{png,jpg,jpeg,gif,svg,ico}") : []

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

