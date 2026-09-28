variable "project_id" {
  description = "Google Cloud project containing the preexisting image and join secret"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Use a valid Google Cloud project ID."
  }
}

variable "region" {
  description = "Region for the VM and preexisting Artifact Registry repository"
  type        = string
  default     = "us-west1"
  validation {
    condition     = contains(["us-west1", "us-central1", "us-east1"], var.region)
    error_message = "Choose us-west1, us-central1 or us-east1 for e2-micro Always Free eligibility."
  }
}

variable "zone" {
  description = "Zone within the selected region"
  type        = string
  default     = "us-west1-a"
  validation {
    condition     = startswith(var.zone, "${var.region}-")
    error_message = "The zone must belong to the selected region."
  }
}

variable "instance_name" {
  description = "Single game host name"
  type        = string
  default     = "fragr-game-server"
  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.instance_name))
    error_message = "Use a lowercase Compute Engine instance name."
  }
}

variable "machine_type" {
  description = "Host machine type; measure capacity before claiming ten-player support"
  type        = string
  default     = "e2-micro"
  validation {
    condition     = var.machine_type == "e2-micro"
    error_message = "Changing the machine type needs a new priced review."
  }
}

variable "boot_disk_size_gb" {
  description = "Standard persistent boot disk in GB"
  type        = number
  default     = 20
  validation {
    condition     = var.boot_disk_size_gb >= 10 && var.boot_disk_size_gb <= 30
    error_message = "Choose 10 to 30 GB for the current disk allowance."
  }
}

variable "artifact_repository" {
  description = "Preexisting Docker repository in the selected region"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{2,62}$", var.artifact_repository))
    error_message = "Use a valid existing Artifact Registry repository ID."
  }
}

variable "image_sha256" {
  description = "Published fragr-server image digest, exactly 64 lowercase hexadecimal characters"
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.image_sha256))
    error_message = "Set the exact published sha256 image digest, without the sha256: prefix."
  }
}

variable "join_secret_id" {
  description = "Preexisting Secret Manager secret ID; its contents never enter Terraform"
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_-]{0,254}$", var.join_secret_id))
    error_message = "Use a valid existing Secret Manager secret ID."
  }
}

variable "join_secret_version" {
  description = "Pinned enabled Secret Manager version number for FRAGR_JOIN_SECRET"
  type        = string
  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.join_secret_version))
    error_message = "Pin an enabled numeric join secret version; do not use latest."
  }
}

variable "game_source_ranges" {
  description = "At most eight distinct canonical operator IPv4 /32s permitted to reach TCP 6767"
  type        = list(string)
  default     = []
  validation {
    condition = (
      length(var.game_source_ranges) <= 8 &&
      length(distinct(var.game_source_ranges)) == length(var.game_source_ranges) &&
      alltrue([
        for cidr in var.game_source_ranges :
        endswith(cidr, "/32") &&
        !strcontains(cidr, ":") &&
        try(cidrhost(cidr, 0) == trimsuffix(cidr, "/32"), false)
      ])
    )
    error_message = "Use at most eight distinct canonical IPv4 /32 operator addresses; broad or malformed ranges are rejected."
  }
}

variable "enable_external_ipv4" {
  description = "Add a billable ephemeral public IPv4 only for a reviewed bounded test"
  type        = bool
  default     = false
}

variable "network_cidr" {
  description = "CIDR range for the dedicated VPC subnet"
  type        = string
  default     = "10.0.0.0/24"
  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "Set a valid IPv4 network CIDR."
  }
}

variable "labels" {
  description = "Resource labels"
  type        = map(string)
  default = {
    project    = "fragr"
    managed_by = "terraform"
  }
}
