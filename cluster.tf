# ===================================================
# Data Sources
# ===================================================


data "oci_core_images" "node_images" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  state                    = "AVAILABLE"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
  
  # Filter for images compatible with OKE
  filter {
    name   = "display_name"
    values = ["Oracle-Linux-8.*-OKE-.*"]
    regex  = true
  }
}

data "oci_containerengine_cluster_option" "cluster_option" {
  cluster_option_id = "all"
}

data "oci_containerengine_node_pool_option" "node_pool_option" {
  node_pool_option_id = "all"
}

# ===================================================
# Locals
# ===================================================

locals {
  cluster_name = "${var.project_name}-${var.environment}-cluster"
  
  # Network CIDR blocks - Non-overlapping ranges
  vcn_cidr               = "10.0.0.0/16"      # VCN: 10.0.0.0 - 10.0.255.255
  control_plane_subnet_cidr = "10.0.1.0/24"  # Control plane: 10.0.1.0 - 10.0.1.255
  worker_subnet_cidr     = "10.0.2.0/24"     # Workers: 10.0.2.0 - 10.0.2.255
  lb_subnet_cidr         = "10.0.3.0/24"     # Load balancer: 10.0.3.0 - 10.0.3.255
  pod_subnet_cidr        = "10.0.64.0/18"    # Pod subnet: 10.0.64.0 - 10.0.127.255 (within VCN)
  service_lb_cidr        = "192.168.0.0/20"  # Services: 192.168.0.0 - 192.168.15.255 (separate range)
  
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Component   = "oke-cluster"
    ManagedBy   = "terraform"
  }
  
  # Get first 3 ADs (or all if less than 3)
  availability_domains = slice(data.oci_identity_availability_domains.ads.availability_domains, 0, min(3, length(data.oci_identity_availability_domains.ads.availability_domains)))
}

# ===================================================
# VCN (Virtual Cloud Network)
# ===================================================

resource "oci_core_vcn" "oke_vcn" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.cluster_name}-vcn"
  cidr_blocks    = [local.vcn_cidr]
  dns_label      = "okevcn"
  
  freeform_tags = local.common_tags
}

# ===================================================
# Internet Gateway
# ===================================================

resource "oci_core_internet_gateway" "oke_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${local.cluster_name}-igw"
  enabled        = true
  
  freeform_tags = local.common_tags
}

# ===================================================
# NAT Gateway
# ===================================================

resource "oci_core_nat_gateway" "oke_nat_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${local.cluster_name}-nat-gateway"
  
  freeform_tags = local.common_tags
}

# ===================================================
# Service Gateway
# ===================================================

data "oci_core_services" "all_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_service_gateway" "oke_service_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${local.cluster_name}-service-gateway"
  
  services {
    service_id = data.oci_core_services.all_services.services[0]["id"]
  }
  
  freeform_tags = local.common_tags
}

# ===================================================
# Route Tables
# ===================================================

# Public Route Table (for Load Balancer subnet)
resource "oci_core_route_table" "public_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${local.cluster_name}-public-rt"
  
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.oke_igw.id
  }
  
  freeform_tags = local.common_tags
}

# Private Route Table (for worker nodes and control plane)
resource "oci_core_route_table" "private_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${local.cluster_name}-private-rt"
  
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.oke_nat_gateway.id
  }
  
  route_rules {
    destination       = data.oci_core_services.all_services.services[0]["cidr_block"]
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.oke_service_gateway.id
  }
  
  freeform_tags = local.common_tags
}

# ===================================================
# Security Lists
# ===================================================

# Control Plane Security List
resource "oci_core_security_list" "control_plane_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${local.cluster_name}-control-plane-sl"
  
  # Ingress rules
  ingress_security_rules {
    protocol = "6" # TCP
    source   = local.worker_subnet_cidr
    
    tcp_options {
      min = 6443
      max = 6443
    }
  }
  
  ingress_security_rules {
    protocol = "6" # TCP
    source   = local.worker_subnet_cidr
    
    tcp_options {
      min = 12250
      max = 12250
    }
  }
  
  # Egress rules
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
  
  freeform_tags = local.common_tags
}

# Worker Node Security List
resource "oci_core_security_list" "worker_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${local.cluster_name}-worker-sl"
  
  # Ingress rules
  ingress_security_rules {
    protocol = "all"
    source   = local.worker_subnet_cidr
  }
  
  ingress_security_rules {
    protocol = "all"
    source   = local.control_plane_subnet_cidr
  }
  
  ingress_security_rules {
    protocol = "all"
    source   = local.pod_subnet_cidr
  }
  
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    
    tcp_options {
      min = 22
      max = 22
    }
  }
  
  # NodePort services
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    
    tcp_options {
      min = 30000
      max = 32767
    }
  }
  
  # Egress rules
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
  
  freeform_tags = local.common_tags
}

# Load Balancer Security List
resource "oci_core_security_list" "lb_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${local.cluster_name}-lb-sl"
  
  # Ingress rules
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    
    tcp_options {
      min = 80
      max = 80
    }
  }
  
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    
    tcp_options {
      min = 443
      max = 443
    }
  }
  
  # Egress rules
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
  
  freeform_tags = local.common_tags
}

# ===================================================
# Subnets
# ===================================================

# Control Plane Subnet (Regional)
resource "oci_core_subnet" "control_plane_subnet" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${local.cluster_name}-control-plane-subnet"
  cidr_block     = local.control_plane_subnet_cidr
  dns_label      = "controlplane"
  
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private_rt.id
  security_list_ids          = [oci_core_security_list.control_plane_sl.id]
  
  freeform_tags = local.common_tags
}

# Worker Node Subnet (Regional)
resource "oci_core_subnet" "worker_subnet" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${local.cluster_name}-worker-subnet"
  cidr_block     = local.worker_subnet_cidr
  dns_label      = "workers"
  
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private_rt.id
  security_list_ids          = [oci_core_security_list.worker_sl.id]
  
  freeform_tags = local.common_tags
}

# Load Balancer Subnet (Regional)
resource "oci_core_subnet" "lb_subnet" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${local.cluster_name}-lb-subnet"
  cidr_block     = local.lb_subnet_cidr
  dns_label      = "loadbalancer"
  
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.public_rt.id
  security_list_ids          = [oci_core_security_list.lb_sl.id]
  
  freeform_tags = local.common_tags
}

# Pod Subnet (Regional) - for OCI_VCN_IP_NATIVE
resource "oci_core_subnet" "pod_subnet" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${local.cluster_name}-pod-subnet"
  cidr_block     = local.pod_subnet_cidr
  dns_label      = "pods"
  
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private_rt.id
  security_list_ids          = [oci_core_security_list.worker_sl.id]  # Use same security list as workers
  
  freeform_tags = local.common_tags
}

# ===================================================
# OKE Cluster
# ===================================================

resource "oci_containerengine_cluster" "oke_cluster" {
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.kubernetes_version
  name               = local.cluster_name
  vcn_id             = oci_core_vcn.oke_vcn.id
  
  cluster_pod_network_options {
    cni_type = "OCI_VCN_IP_NATIVE"
  }
  
  endpoint_config {
    is_public_ip_enabled = false
    subnet_id            = oci_core_subnet.control_plane_subnet.id
    nsg_ids              = [oci_core_network_security_group.control_plane_nsg.id]
  }
  
  options {
    service_lb_subnet_ids = [oci_core_subnet.lb_subnet.id]
    
    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }
    
    admission_controller_options {
      is_pod_security_policy_enabled = false
    }
    
    kubernetes_network_config {
      pods_cidr     = local.pod_subnet_cidr
      services_cidr = local.service_lb_cidr
    }
    
    persistent_volume_config {
      freeform_tags = local.common_tags
    }
    
    service_lb_config {
      freeform_tags = local.common_tags
    }
  }
  
  freeform_tags = local.common_tags
  
  depends_on = [
    oci_core_subnet.control_plane_subnet,
    oci_core_subnet.lb_subnet
  ]
}

# ===================================================
# Network Security Groups
# ===================================================

# Control Plane NSG
resource "oci_core_network_security_group" "control_plane_nsg" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${local.cluster_name}-control-plane-nsg"
  
  freeform_tags = local.common_tags
}

# Worker Node NSG
resource "oci_core_network_security_group" "worker_nsg" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${local.cluster_name}-worker-nsg"
  
  freeform_tags = local.common_tags
}

# Pod NSG for OCI_VCN_IP_NATIVE
resource "oci_core_network_security_group" "pod_nsg" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.oke_vcn.id
  display_name   = "${local.cluster_name}-pod-nsg"
  
  freeform_tags = local.common_tags
}

# NSG Rules for Control Plane
resource "oci_core_network_security_group_security_rule" "control_plane_ingress" {
  network_security_group_id = oci_core_network_security_group.control_plane_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = oci_core_network_security_group.worker_nsg.id
  source_type               = "NETWORK_SECURITY_GROUP"
  
  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}

# NSG Rules for Worker Nodes
resource "oci_core_network_security_group_security_rule" "worker_ingress_from_control_plane" {
  network_security_group_id = oci_core_network_security_group.worker_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = oci_core_network_security_group.control_plane_nsg.id
  source_type               = "NETWORK_SECURITY_GROUP"
  
  tcp_options {
    destination_port_range {
      min = 10250
      max = 10250
    }
  }
}

resource "oci_core_network_security_group_security_rule" "worker_ingress_internal" {
  network_security_group_id = oci_core_network_security_group.worker_nsg.id
  direction                 = "INGRESS"
  protocol                  = "all"
  source                    = oci_core_network_security_group.worker_nsg.id
  source_type               = "NETWORK_SECURITY_GROUP"
}

# Pod NSG Rules
resource "oci_core_network_security_group_security_rule" "pod_ingress_from_workers" {
  network_security_group_id = oci_core_network_security_group.pod_nsg.id
  direction                 = "INGRESS"
  protocol                  = "all"
  source                    = oci_core_network_security_group.worker_nsg.id
  source_type               = "NETWORK_SECURITY_GROUP"
}

resource "oci_core_network_security_group_security_rule" "pod_ingress_internal" {
  network_security_group_id = oci_core_network_security_group.pod_nsg.id
  direction                 = "INGRESS"
  protocol                  = "all"
  source                    = oci_core_network_security_group.pod_nsg.id
  source_type               = "NETWORK_SECURITY_GROUP"
}

resource "oci_core_network_security_group_security_rule" "pod_egress_all" {
  network_security_group_id = oci_core_network_security_group.pod_nsg.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}

# ===================================================
# Node Pool
# ===================================================

resource "oci_containerengine_node_pool" "oke_node_pool" {
  cluster_id         = oci_containerengine_cluster.oke_cluster.id
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.kubernetes_version
  name               = "${local.cluster_name}-node-pool"
  
  node_config_details {
    placement_configs {
      availability_domain = local.availability_domains[0].name
      subnet_id           = oci_core_subnet.worker_subnet.id
    }
    
    dynamic "placement_configs" {
      for_each = length(local.availability_domains) > 1 ? [local.availability_domains[1]] : []
      content {
        availability_domain = placement_configs.value.name
        subnet_id           = oci_core_subnet.worker_subnet.id
      }
    }
    
    dynamic "placement_configs" {
      for_each = length(local.availability_domains) > 2 ? [local.availability_domains[2]] : []
      content {
        availability_domain = placement_configs.value.name
        subnet_id           = oci_core_subnet.worker_subnet.id
      }
    }
    
    size = var.node_count * length(local.availability_domains)
    
    nsg_ids = [oci_core_network_security_group.worker_nsg.id]
    
    freeform_tags = local.common_tags
  }
  
  # Add pod network configuration to match cluster
  node_pool_pod_network_option_details {
    cni_type = "OCI_VCN_IP_NATIVE"
    
    pod_nsg_ids = [oci_core_network_security_group.pod_nsg.id]
    pod_subnet_ids = [oci_core_subnet.pod_subnet.id]
  }
  
  node_shape = var.node_shape
  
  # Only include shape config for flexible shapes
  dynamic "node_shape_config" {
    for_each = length(regexall("Flex", var.node_shape)) > 0 ? [1] : []
    content {
      ocpus         = var.node_ocpus
      memory_in_gbs = var.node_memory_gb
    }
  }
  
  node_source_details {
    image_id    = data.oci_core_images.node_images.images[0].id
    source_type = "IMAGE"
    
    boot_volume_size_in_gbs = 100
  }
  
  ssh_public_key = var.ssh_public_key
  
  initial_node_labels {
    key   = "environment"
    value = var.environment
  }
  
  initial_node_labels {
    key   = "project"
    value = var.project_name
  }
  
  freeform_tags = local.common_tags
}

# ===================================================
# Outputs
# ===================================================

output "cluster_id" {
  description = "ID of the OKE cluster"
  value       = oci_containerengine_cluster.oke_cluster.id
}

output "cluster_name" {
  description = "Name of the OKE cluster"
  value       = oci_containerengine_cluster.oke_cluster.name
}

output "cluster_kubernetes_version" {
  description = "Kubernetes version of the cluster"
  value       = oci_containerengine_cluster.oke_cluster.kubernetes_version
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = oci_containerengine_cluster.oke_cluster.endpoints[0].private_endpoint
  sensitive   = true
}

output "vcn_id" {
  description = "ID of the VCN"
  value       = oci_core_vcn.oke_vcn.id
}

output "worker_subnet_id" {
  description = "ID of the worker subnet"
  value       = oci_core_subnet.worker_subnet.id
}

output "lb_subnet_id" {
  description = "ID of the load balancer subnet"
  value       = oci_core_subnet.lb_subnet.id
}

output "node_pool_id" {
  description = "ID of the node pool"
  value       = oci_containerengine_node_pool.oke_node_pool.id
}

output "kubeconfig_command" {
  description = "Command to get kubeconfig"
  value       = "oci ce cluster create-kubeconfig --cluster-id ${oci_containerengine_cluster.oke_cluster.id} --file ~/.kube/config --region ${var.region} --token-version 2.0.0 --kube-endpoint PRIVATE_ENDPOINT"
}
