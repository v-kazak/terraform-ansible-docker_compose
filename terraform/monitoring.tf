resource "yandex_vpc_security_group" "monitoring_sg" {
  name        = "monitoring-security-group"
  description = "Security group for monitoring host"
  folder_id   = var.folder_id
  network_id  = yandex_vpc_network.test.id

  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    port           = 3000
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    port           = 9090
    v4_cidr_blocks = ["10.10.0.0/24"]
  }

  ingress {
    protocol       = "TCP"
    port           = 9093
    v4_cidr_blocks = ["10.10.0.0/24"]
  }

  ingress {
    protocol       = "TCP"
    port           = 9100
    v4_cidr_blocks = ["10.10.0.0/24"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_compute_instance" "monitoring" {
  name        = "monitoring-server"
  platform_id = var.platform_type
  zone        = var.zone
  folder_id   = var.folder_id

  resources {
    cores         = 2
    memory        = 4
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
      type     = var.disc_type
      size     = 20
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.test.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.monitoring_sg.id]
  }

  metadata = {
    user-data = <<-EOF
			#cloud-config
			users:
				- name: ${var.ssh_user}
					groups: sudo
					shell: /bin/bash
					sudo: ['ALL=(ALL) NOPASSWD:ALL']
					ssh_authorized_keys:
						- ${trimspace(file(var.ssh_public_key_path))}
		EOF
  }

  scheduling_policy {
    preemptible = var.preemptible
  }
}

resource "local_file" "monitoring_inventory" {
  content  = "${yandex_compute_instance.monitoring.network_interface[0].nat_ip_address} ansible_user=${var.ssh_user}"
  filename = "${path.module}/../ansible/inventory_monitoring.ini"
}

output "monitoring_public_ip" {
  description = "Public IP address of monitoring instance"
  value       = yandex_compute_instance.monitoring.network_interface[0].nat_ip_address
}

output "monitoring_private_ip" {
  description = "Private IP address of monitoring instance"
  value       = yandex_compute_instance.monitoring.network_interface[0].ip_address
}
