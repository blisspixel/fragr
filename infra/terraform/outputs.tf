output "instance_name" {
  description = "Container host instance name"
  value       = google_compute_instance.game_server.name
}

output "external_ip" {
  description = "Optional billable ephemeral IPv4 address; null by default"
  value       = try(google_compute_instance.game_server.network_interface[0].access_config[0].nat_ip, null)
}

output "game_server_address" {
  description = "Optional TCP address reachable only from reviewed game_source_ranges"
  value       = var.enable_external_ipv4 ? "${google_compute_instance.game_server.network_interface[0].access_config[0].nat_ip}:6767" : null
}

output "image_ref" {
  description = "Pinned server image deployed at next host replacement"
  value       = local.image_ref
}

output "ssh_command" {
  description = "Break-glass IAP SSH command, subject to operator IAM"
  value       = "gcloud compute ssh ${google_compute_instance.game_server.name} --zone=${var.zone} --tunnel-through-iap"
}

output "cost_warning" {
  description = "Billing review required before apply"
  value       = "External IPv4 is off by default. If enabled, it bills while the VM runs even with game ingress closed. VM, disk, image storage and egress can also bill. Budget alerts do not cap charges."
}
