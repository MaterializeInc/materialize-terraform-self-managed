resource "aws_route53_record" "balancerd" {
  zone_id = var.hosted_zone_id
  name    = var.balancerd_domain_name
  type    = "A"

  alias {
    name                   = var.nlb_dns_name
    zone_id                = var.nlb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "console" {
  zone_id = var.hosted_zone_id
  name    = var.console_domain_name
  type    = "A"

  alias {
    name                   = var.nlb_dns_name
    zone_id                = var.nlb_zone_id
    evaluate_target_health = true
  }
}
