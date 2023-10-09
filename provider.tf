terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
    checkmate = {
      source  = "tetratelabs/checkmate"
      version = "1.5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.9.1"
    }
  }
}