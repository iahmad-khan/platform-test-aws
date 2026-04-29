resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = "${var.name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "nodes" {
  project                  = var.project_id
  name                     = "${var.name}-nodes"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.nodes_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "${var.name}-pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "${var.name}-services"
    ip_cidr_range = var.services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_router" "router" {
  project = var.project_id
  name    = "${var.name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  project                            = var.project_id
  name                               = "${var.name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Reserved IP block for Cloud SQL Private Service Access peering
resource "google_compute_global_address" "private_service_range" {
  project       = var.project_id
  name          = "${var.name}-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

# Establishes the VPC peering that allows Cloud SQL to use a private IP
resource "google_service_networking_connection" "private_service" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
}

resource "google_compute_firewall" "allow_internal" {
  project       = var.project_id
  name          = "${var.name}-allow-internal"
  network       = google_compute_network.vpc.name
  source_ranges = [var.nodes_cidr, var.pods_cidr, var.services_cidr]

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }
}

# Allows the GKE control plane to reach kubelets and the API aggregation layer
resource "google_compute_firewall" "allow_master" {
  project       = var.project_id
  name          = "${var.name}-allow-master"
  network       = google_compute_network.vpc.name
  source_ranges = [var.master_cidr]
  target_tags   = ["gke-node"]

  allow {
    protocol = "tcp"
    ports    = ["443", "8443", "10250"]
  }
}

resource "google_compute_firewall" "allow_health_checks" {
  project       = var.project_id
  name          = "${var.name}-allow-hc"
  network       = google_compute_network.vpc.name
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["gke-node"]

  allow { protocol = "tcp" }
}
