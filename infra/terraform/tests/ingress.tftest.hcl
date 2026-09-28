mock_provider "google" {}

variables {
  project_id          = "example-proj"
  region              = "us-west1"
  zone                = "us-west1-a"
  artifact_repository = "fragr-images"
  image_sha256        = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  join_secret_id      = "fragr-join-secret"
  join_secret_version = "1"
}

run "default_has_no_game_ingress" {
  command = plan

  assert {
    condition     = length(google_compute_firewall.game_port_tcp) == 0
    error_message = "The default must create no game firewall rule."
  }
}

run "two_operator_addresses" {
  command = plan
  variables {
    enable_external_ipv4 = true
    game_source_ranges   = ["203.0.113.4/32", "198.51.100.8/32"]
  }

  assert {
    condition     = length(google_compute_firewall.game_port_tcp) == 1
    error_message = "A reviewed operator test must create one TCP firewall rule."
  }
}

run "host_prefix_zero_is_rejected" {
  command = plan
  variables {
    game_source_ranges = ["1.2.3.4/0"]
  }
  expect_failures = [var.game_source_ranges]
}

run "first_half_internet_is_rejected" {
  command = plan
  variables {
    game_source_ranges = ["0.0.0.0/1"]
  }
  expect_failures = [var.game_source_ranges]
}

run "two_halves_are_rejected" {
  command = plan
  variables {
    game_source_ranges = ["0.0.0.0/1", "128.0.0.0/1"]
  }
  expect_failures = [var.game_source_ranges]
}

run "noncanonical_host_prefix_is_rejected" {
  command = plan
  variables {
    game_source_ranges = ["203.0.113.4/24"]
  }
  expect_failures = [var.game_source_ranges]
}

run "noncanonical_ipv4_text_is_rejected" {
  command = plan
  variables {
    game_source_ranges = ["203.0.113.004/32"]
  }
  expect_failures = [var.game_source_ranges]
}

run "more_than_eight_is_rejected" {
  command = plan
  variables {
    game_source_ranges = [
      "203.0.113.1/32", "203.0.113.2/32", "203.0.113.3/32",
      "203.0.113.4/32", "203.0.113.5/32", "203.0.113.6/32",
      "203.0.113.7/32", "203.0.113.8/32", "203.0.113.9/32",
    ]
  }
  expect_failures = [var.game_source_ranges]
}

run "duplicate_operator_address_is_rejected" {
  command = plan
  variables {
    game_source_ranges = ["203.0.113.4/32", "203.0.113.4/32"]
  }
  expect_failures = [var.game_source_ranges]
}

run "public_ip_without_operator_is_rejected" {
  command = plan
  variables {
    enable_external_ipv4 = true
  }
  expect_failures = [google_compute_instance.game_server]
}

run "operator_without_public_ip_is_rejected" {
  command = plan
  variables {
    game_source_ranges = ["203.0.113.4/32"]
  }
  expect_failures = [google_compute_instance.game_server]
}
