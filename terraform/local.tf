locals {
  service_ports = [
    [22],     #SSH
    [80, 443] #HTTP, HTTPS
  ]
}