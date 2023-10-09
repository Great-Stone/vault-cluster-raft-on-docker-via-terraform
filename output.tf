output "vault_unseal_keys" {
  depends_on = [local_file.vault_unseal]
  value      = jsondecode(local_file.vault_unseal.content).keys
}

output "vault_root_token" {
  depends_on = [local_file.vault_unseal]
  value      = jsondecode(local_file.vault_unseal.content).root_token
}

output "vault_health" {
  value = {
    initialized = jsondecode(data.http.vault_health.response_body).initialized
    sealed      = jsondecode(data.http.vault_health.response_body).sealed
    version     = jsondecode(data.http.vault_health.response_body).version
  }
}

output "vault_addr" {
  value = [for vault in docker_container.vault : "http://127.0.0.1:${vault.ports[0].external}"]
}