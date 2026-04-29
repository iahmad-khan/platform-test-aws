resource "google_container_cluster" "cluster" {
  provider = google-beta

  project  = var.project_id
  name     = "${var.name}-cluster"
  location = var.region

  network    = var.network_self_link
  subnetwork = var.subnetwork_self_link

  # Immediately replaced by the managed system node pool below
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection

  # VPC-native (alias IP) networking required for private clusters
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Private nodes (no external IPs); master remains publicly reachable but
  # is locked to the CIDRs in master_authorized_networks_config below.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Dataplane V2 (eBPF / Cilium) — replaces kube-proxy and network policy
  # controller; incompatible with network_policy.enabled = true.
  datapath_provider = "ADVANCED_DATAPATH"

  network_policy {
    enabled  = false
    provider = "PROVIDER_UNSPECIFIED"
  }

  # ── Node Auto Provisioning ────────────────────────────────────────────────
  # NAP automatically creates node pools for workloads it can't schedule.
  # ARM64: NAP provisions T2A nodes when pods request kubernetes.io/arch=arm64.
  # GPU:   NAP provisions GPU nodes when pods request nvidia.com/gpu.
  #        GKE auto-installs NVIDIA drivers on GPU nodes via a managed DaemonSet.

  cluster_autoscaling {
    enabled = true

    resource_limits {
      resource_type = "cpu"
      minimum       = var.cpu_min
      maximum       = var.cpu_max # capped at 1000 vCPUs cluster-wide
    }

    resource_limits {
      resource_type = "memory"
      minimum       = var.memory_min
      maximum       = var.memory_max # capped at 1024 GiB cluster-wide
    }

    # GPU resource limits — NAP will provision nodes with these accelerators
    # when workloads request resources.limits["nvidia.com/gpu"].
    resource_limits {
      resource_type = "nvidia-tesla-t4"
      minimum       = 0
      maximum       = var.gpu_t4_max
    }

    resource_limits {
      resource_type = "nvidia-tesla-a100"
      minimum       = 0
      maximum       = var.gpu_a100_max
    }

    resource_limits {
      resource_type = "nvidia-l4"
      minimum       = 0
      maximum       = var.gpu_l4_max
    }

    auto_provisioning_defaults {
      service_account = var.node_service_account_email
      oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

      management {
        auto_repair  = true
        auto_upgrade = true
      }

      shielded_instance_config {
        enable_secure_boot          = true
        enable_integrity_monitoring = true
      }

      disk_size  = 100
      disk_type  = "pd-ssd"
      image_type = "COS_CONTAINERD"

      upgrade_settings {
        strategy        = "SURGE"
        max_surge       = 1
        max_unavailable = 0
      }
    }
  }

  release_channel {
    channel = var.release_channel
  }

  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]

    managed_prometheus {
      enabled = true
    }
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }

    horizontal_pod_autoscaling {
      disabled = false
    }

    gce_persistent_disk_csi_driver_config {
      enabled = true
    }

    dns_cache_config {
      enabled = true
    }
  }

  # Enables VPC flow logs between pods on the same node (otherwise invisible)
  enable_intranode_visibility = true

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = var.maintenance_end_time
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  resource_labels = var.labels
}

# ── System node pool ──────────────────────────────────────────────────────────
# Hosts kube-system workloads. Tainted so that application pods don't land here.
# NAP provisions separate pools for application workloads automatically.

resource "google_container_node_pool" "system" {
  project  = var.project_id
  name     = "${var.name}-system"
  location = var.region
  cluster  = google_container_cluster.cluster.name

  initial_node_count = var.system_node_count

  autoscaling {
    min_node_count = var.system_node_count
    max_node_count = var.system_node_count * 2
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.system_node_machine_type
    service_account = var.node_service_account_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    image_type      = "COS_CONTAINERD"
    disk_size_gb    = 50
    disk_type       = "pd-ssd"

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = merge(var.labels, { "node-pool" = "system" })
    tags   = ["gke-node"]

    taint {
      key    = "node-pool"
      value  = "system"
      effect = "NO_SCHEDULE"
    }
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }
}
