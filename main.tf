locals {
  is_windows         = substr(pathexpand("~"), 0, 1) == "/" ? false : true
  server_count       = 3
  server_count_lists = [for i in range(local.server_count) : tostring(i)]

  init_file = "${path.module}/init.json"

  powershell = "Remove-Item -Recurse -Force ${path.module}/volumes"
  unixshell  = "rm -rf ${path.module}/volumes"
}

provider "docker" {}

# Create Network
resource "docker_network" "local" {
  name = "vault-net"
}

# Pulls the image
resource "docker_image" "vault" {
  name = "vault:${var.vault_version_tag}"
}

data "template_file" "vault_config" {
  count    = local.server_count
  template = file("${path.module}/template/vault_config.tpl")

  vars = {
    node_id            = "vault-${count.index}"
    server_count_lists = jsonencode(local.server_count_lists)
  }
}

resource "local_file" "vault_config" {
  count    = local.server_count
  content  = data.template_file.vault_config[count.index].rendered
  filename = "${abspath(path.root)}/volumes/vault-${count.index}/config/config.hcl"
}

resource "local_file" "vault_data" {
  count    = local.server_count
  content  = data.template_file.vault_config[count.index].rendered
  filename = "${abspath(path.root)}/volumes/vault-${count.index}/data/tmp.txt"
}

resource "local_file" "vault_logs" {
  count    = local.server_count
  content  = data.template_file.vault_config[count.index].rendered
  filename = "${abspath(path.root)}/volumes/vault-${count.index}/logs/tmp.txt"
}

# Create a container
resource "docker_container" "vault" {
  count = local.server_count
  image = docker_image.vault.image_id
  name  = "vault-${count.index}"

  networks_advanced {
    name = docker_network.local.name
  }

  capabilities {
    add = ["IPC_LOCK"]
  }

  ports {
    internal = 8200
    external = 8200 + count.index
  }

  volumes {
    container_path = "/vault/config"
    host_path      = trimsuffix(local_file.vault_config[count.index].filename, "/config.hcl")
    read_only      = false
  }

  volumes {
    container_path = "/vault/data"
    host_path      = trimsuffix(local_file.vault_data[count.index].filename, "/tmp.txt")
    read_only      = false
  }

  volumes {
    container_path = "/vault/logs"
    host_path      = trimsuffix(local_file.vault_logs[count.index].filename, "/tmp.txt")
    read_only      = false
  }

  env = [
    "SKIP_CHOWN=true"
  ]

  command = ["server"]
}

// Vault Init
resource "checkmate_http_health" "vault_status" {
  count                 = local.server_count
  url                   = "http://127.0.0.1:${docker_container.vault[count.index].ports[0].external}/v1/sys/init"
  request_timeout       = 1000
  method                = "GET"
  interval              = 1
  status_code           = "200-599"
  consecutive_successes = 3
}

data "http" "vault_init" {
  depends_on = [checkmate_http_health.vault_status]

  url    = checkmate_http_health.vault_status[0].url
  method = "POST"

  request_headers = {
    Accept = "application/json"
  }

  request_body = jsonencode({
    secret_shares    = 1
    secret_threshold = 1
  })
}

resource "local_file" "vault_unseal" {
  depends_on = [data.http.vault_init]
  content    = fileexists(local.init_file) ? file(local.init_file) : data.http.vault_init.response_body
  filename   = local.init_file
}

data "http" "vault_unseal_1" {
  for_each = toset(["0"])

  url    = "http://127.0.0.1:${docker_container.vault[each.key].ports[0].external}/v1/sys/unseal"
  method = "POST"

  request_headers = {
    Accept = "application/json"
  }

  request_body = jsonencode({
    key = jsondecode(local_file.vault_unseal.content).keys[0]
  })
}

resource "time_sleep" "wait_sync_seconds" {
  depends_on      = [data.http.vault_unseal_1]
  create_duration = "5s"
}

data "http" "vault_unseal_2_3" {
  depends_on = [time_sleep.wait_sync_seconds]

  for_each = toset(["1", "2"])

  url    = "http://127.0.0.1:${docker_container.vault[each.key].ports[0].external}/v1/sys/unseal"
  method = "POST"

  request_headers = {
    Accept = "application/json"
  }

  request_body = jsonencode({
    key = jsondecode(local_file.vault_unseal.content).keys[0]
  })
}

data "http" "vault_health" {
  depends_on = [data.http.vault_unseal_2_3]

  url    = "http://127.0.0.1:${docker_container.vault[0].ports[0].external}/v1/sys/health"
  method = "GET"
  retry {
    attempts     = 10
    max_delay_ms = 500
  }

  request_headers = {
    Accept = "application/json"
  }
}

resource "terraform_data" "delete_directory" {
  input = {
    interpreter = local.is_windows ? ["PowerShell", "-Command"] : []
    command     = local.is_windows ? local.powershell : local.unixshell
  }
  provisioner "local-exec" {
    when        = destroy
    interpreter = self.input.interpreter
    command     = self.input.command
  }
}