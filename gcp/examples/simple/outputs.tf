# Networking outputs
output "network" {
  description = "Network details"
  value = {
    network_id    = module.networking.network_id
    network_name  = module.networking.network_name
    subnets_names = module.networking.subnets_names
  }
}

# Cluster outputs
output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = module.gke.cluster_name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.cluster_endpoint
}

output "gke_cluster_location" {
  description = "GKE cluster location"
  value       = module.gke.cluster_location
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.gke.cluster_ca_certificate
  sensitive   = true
}


output "service_account_email" {
  description = "Service account email for GKE nodes"
  value       = module.gke.service_account_email
}

output "workload_identity_sa_email" {
  description = "The email of the Workload Identity service account"
  value       = module.gke.workload_identity_sa_email
}

output "generic_nodepool_name" {
  description = "Name of the generic node pool"
  value       = module.generic_nodepool.node_pool_name
}

output "generic_nodepool_id" {
  description = "ID of the generic node pool"
  value       = module.generic_nodepool.node_pool_id
}

output "materialize_nodepool_name" {
  description = "Name of the Materialize node pool"
  value       = module.materialize_nodepool.node_pool_name
}

output "materialize_nodepool_id" {
  description = "ID of the Materialize node pool"
  value       = module.materialize_nodepool.node_pool_id
}

# Database outputs
output "database_instance_name" {
  description = "Cloud SQL instance name"
  value       = module.database.instance_name
}

output "database_private_ip" {
  description = "Cloud SQL instance private IP"
  value       = module.database.private_ip
}

output "database_names" {
  description = "List of database names"
  value       = module.database.database_names
}

output "database_users" {
  description = "List of database users with credentials"
  value       = module.database.users
  sensitive   = true
}

# Storage outputs
output "storage" {
  description = "GCS bucket details"
  value = {
    name      = module.storage.bucket_name
    url       = module.storage.bucket_url
    self_link = module.storage.bucket_self_link
  }
}

# Materialize component outputs
output "operator" {
  description = "Materialize operator details"
  value = {
    namespace      = module.operator.operator_namespace
    release_name   = module.operator.operator_release_name
    release_status = module.operator.operator_release_status
  }
}

output "materialize_instance_name" {
  description = "Materialize instance name"
  value       = var.install_materialize_instance ? module.materialize_instance[0].instance_name : null
}

output "materialize_instance_namespace" {
  description = "Materialize instance namespace"
  value       = var.install_materialize_instance ? module.materialize_instance[0].instance_namespace : null
}

output "materialize_instance_resource_id" {
  description = "Materialize instance resource ID"
  value       = var.install_materialize_instance ? module.materialize_instance[0].instance_resource_id : null
}

output "materialize_instance_metadata_backend_url" {
  description = "Materialize instance metadata backend URL"
  value       = var.install_materialize_instance ? module.materialize_instance[0].metadata_backend_url : null
  sensitive   = true
}

output "materialize_instance_persist_backend_url" {
  description = "Materialize instance persist backend URL"
  value       = var.install_materialize_instance ? module.materialize_instance[0].persist_backend_url : null
  sensitive   = true
}

# Load balancer outputs
output "load_balancer_details" {
  description = "Details of the Materialize instance load balancers."
  value = {
    for load_balancer in module.load_balancers : load_balancer.instance_name => {
      console_load_balancer_ip   = load_balancer.console_load_balancer_ip
      balancerd_load_balancer_ip = load_balancer.balancerd_load_balancer_ip
    }
  }
}
