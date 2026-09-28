# fragr container host. Plan-only until a priced deployment is approved.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  image_ref = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repository}/fragr-server@sha256:${var.image_sha256}"
}

resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_network" "vpc" {
  name                    = "fragr-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  depends_on              = [google_project_service.compute]
}

resource "google_compute_subnetwork" "subnet" {
  name                     = "fragr-subnet"
  ip_cidr_range            = var.network_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

# Empty source ranges create no game ingress.
resource "google_compute_firewall" "game_port_tcp" {
  count   = var.enable_external_ipv4 && length(var.game_source_ranges) > 0 ? 1 : 0
  name    = "fragr-allow-game-tcp"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["6767"]
  }

  source_ranges = var.game_source_ranges
  target_tags   = ["fragr-game-server"]
  description   = "Allow reviewed TCP WebSocket game traffic on port 6767"
}

resource "google_compute_firewall" "iap_ssh" {
  name    = "fragr-allow-iap-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["fragr-game-server"]
  description   = "Allow SSH only through Identity-Aware Proxy TCP forwarding"
}

resource "google_service_account" "game_server" {
  account_id   = "fragr-game-server"
  display_name = "fragr Game Server Service Account"
  description  = "Pulls one game image and reads one pinned join secret"
}

# The repository and image must exist before the VM is created.
resource "google_artifact_registry_repository_iam_member" "game_image_reader" {
  project    = var.project_id
  location   = var.region
  repository = var.artifact_repository
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.game_server.email}"
}

resource "google_secret_manager_secret_iam_member" "join_secret_reader" {
  project   = var.project_id
  secret_id = var.join_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.game_server.email}"
}

resource "google_compute_instance" "game_server" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["fragr-game-server"]

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
      size  = var.boot_disk_size_gb
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.subnet.id

    # Private Google Access on the subnet covers registry and secret reads.
    # A public IPv4 is opt-in and bills while the VM runs, even with no ingress.
    dynamic "access_config" {
      for_each = var.enable_external_ipv4 ? [1] : []
      content {}
    }
  }

  service_account {
    email  = google_service_account.game_server.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = templatefile("${path.module}/cos-startup.sh.tftpl", {
    image_ref           = local.image_ref
    registry_host       = "${var.region}-docker.pkg.dev"
    project_id          = var.project_id
    join_secret_id      = var.join_secret_id
    join_secret_version = var.join_secret_version
    game_source_ranges  = var.enable_external_ipv4 ? var.game_source_ranges : []
  })

  labels = var.labels

  lifecycle {
    precondition {
      condition     = var.enable_external_ipv4 == (length(var.game_source_ranges) > 0)
      error_message = "External IPv4 and reviewed game_source_ranges must be enabled together."
    }
  }

  depends_on = [
    google_project_service.compute,
    google_artifact_registry_repository_iam_member.game_image_reader,
    google_secret_manager_secret_iam_member.join_secret_reader,
  ]
}
