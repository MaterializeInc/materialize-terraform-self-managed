output "gke_cluster" {
  description = "GKE cluster details"
  value = {
    name           = google_container_cluster.primary.name
    endpoint       = google_container_cluster.primary.endpoint
    location       = google_container_cluster.primary.location
    ca_certificate = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  }
  sensitive = true
}

output "network" {
  description = "Network details"
  value = {
    network_id   = google_compute_network.vpc.id
    network_name = google_compute_network.vpc.name
    subnet_name  = google_compute_subnetwork.subnet.name
  }
}

output "database" {
  description = "Cloud SQL instance details"
  value = {
    name       = google_sql_database_instance.materialize.name
    private_ip = google_sql_database_instance.materialize.private_ip_address
  }
  sensitive = true
}

output "storage" {
  description = "GCS bucket details"
  value = {
    name      = module.storage.bucket_name
    url       = module.storage.bucket_url
    self_link = module.storage.bucket_self_link
  }
}

output "service_accounts" {
  description = "Service account details"
  value = {
    gke_sa         = google_service_account.gke_sa.email
    materialize_sa = google_service_account.workload_identity_sa.email
  }
}

output "connection_strings" {
  description = "Formatted connection strings for Materialize"
  value = {
    metadata_backend_url = local.metadata_backend_url
    persist_backend_url  = local.persist_backend_url
  }
  sensitive = true
}

output "operator" {
  description = "Materialize operator details"
  value = {
    namespace      = module.operator.operator_namespace
    release_name   = module.operator.operator_release_name
    release_status = module.operator.operator_release_status
  }
}

output "materialize_instance" {
  description = "Materialize instance details"
  value = {
    name        = module.materialize_instance.instance_name
    namespace   = module.materialize_instance.instance_namespace
    resource_id = module.materialize_instance.instance_resource_id
  }
}

output "load_balancer_details" {
  description = "Load balancer IP addresses"
  value = {
    console_ip   = module.load_balancers.console_load_balancer_ip
    balancerd_ip = module.load_balancers.balancerd_load_balancer_ip
  }
}
