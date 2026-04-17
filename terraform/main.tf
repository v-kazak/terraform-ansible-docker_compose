terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  token    = var.token
  cloud_id = var.cloud_id
  zone     = var.zone
}

resource "yandex_compute_instance" "default" {
  name        = "${var.name}-${count.index}"
  platform_id = var.platform_type
  zone        = var.zone
  folder_id   = var.folder_id
  count       = var.vps_count


  resources {
    cores         = var.cores_count
    memory        = var.memory_count
    core_fraction = var.core_fraction
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
      type     = var.disc_type
      size     = var.disc_size
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.test.id
    nat       = var.nat
  }

  metadata = {
    ssh-keys = "debian:${file("~/.ssh/id_ed25519.pub")}"
  }

  scheduling_policy {
    preemptible = var.preemptible
  }

}

resource "yandex_vpc_network" "test" {
  name      = "test"
  folder_id = var.folder_id
}

resource "yandex_vpc_subnet" "test" {
  zone           = var.zone
  network_id     = resource.yandex_vpc_network.test.id
  v4_cidr_blocks = ["10.10.0.0/24"]
  folder_id      = var.folder_id
}

resource "yandex_lb_target_group" "my_blns" {
  name      = "my-target-group"
  region_id = var.blns_zone
  folder_id = var.folder_id

  dynamic "target" {
    for_each = yandex_compute_instance.default
    content {
      subnet_id = yandex_vpc_subnet.test.id
      address   = target.value.network_interface.0.ip_address
    }
  }
}


resource "yandex_lb_network_load_balancer" "my_nlb" {
  name      = "my-network-load-balancer"
  folder_id = var.folder_id

  listener {
    name = "my-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.my_blns.id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/health"
      }
    }
  }
}


resource "local_file" "inventory" {
  content  = join("\n", [for instance in yandex_compute_instance.default : "${instance.network_interface[0].nat_ip_address} ansible_user=debian"])
  filename = "${path.module}/../ansible/inventory.ini"
}

resource "yandex_vpc_security_group" "sg1" {
  name        = "my_security_group"
  description = "description for my security group"
  folder_id = var.folder_id
  network_id  = resource.yandex_vpc_network.test.id

  labels = {
    my-label = "my-label-value"
  }

  dynamic "ingress" {
    for_each = flatten(local.service_ports)
    content {
      protocol       = "TCP"
      port           = ingress.value
      v4_cidr_blocks = ["0.0.0.0/0"]
    }
  }
}