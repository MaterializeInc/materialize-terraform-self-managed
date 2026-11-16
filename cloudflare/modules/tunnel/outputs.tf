output "tunnel_id" {
  description = "ID of the Cloudflare tunnel."
  value       = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

output "tunnel_token" {
  description = "Token cloudflared connectors use to run the tunnel."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.this.token
  sensitive   = true
}

output "console_url" {
  description = "URL of the Materialize console."
  value       = "https://${var.console_hostname}"
}

output "sql_hostname" {
  description = "Hostname to pass to `cloudflared access tcp --hostname` for pgwire, or null."
  value       = var.sql_hostname
}

output "service_token" {
  description = "Access service token for machine clients, sent as the `CF-Access-Client-Id` and `CF-Access-Client-Secret` headers, or with `cloudflared access tcp --service-token-id/--service-token-secret`. Null unless `create_service_token` is set."
  value = var.create_service_token ? {
    client_id     = cloudflare_zero_trust_access_service_token.this[0].client_id
    client_secret = cloudflare_zero_trust_access_service_token.this[0].client_secret
  } : null
  sensitive = true
}
