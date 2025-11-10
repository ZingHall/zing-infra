terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

locals {
  domain_validation_options = tolist(aws_acm_certificate.this.domain_validation_options)[0]
}

data "aws_route53_zone" "zone" {
  name         = var.hosted_zone_name
  private_zone = "false"
}


resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true # 這確保在更新憑證時，新的憑證會先創建，
    # 然後再替換舊的，避免服務中斷。
  }

  tags = {
    name        = var.domain_name
    description = var.description
  }
}

resource "aws_route53_record" "this" {
  name    = local.domain_validation_options.resource_record_name
  type    = local.domain_validation_options.resource_record_type
  zone_id = data.aws_route53_zone.zone.id
  records = [local.domain_validation_options.resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "dns_validation" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [aws_route53_record.this.fqdn]
}
