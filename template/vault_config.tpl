listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

storage "raft" {
  path = "/vault/data"
  node_id = "raft-${node_id}"

%{ for s in jsondecode(server_count_lists) ~}
  retry_join {
    leader_api_addr = "http://vault-${s}:8200"
  }
%{ endfor ~}
}

ui = true

log_level = "info"
log_file = "/vault/logs/log.txt"
log_rotate_duration = "10m"

api_addr = "http://${node_id}:8200"
cluster_addr = "https://${node_id}:8201"