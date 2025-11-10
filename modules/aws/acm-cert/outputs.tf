output "cert_arn" {
  description = "arn of acm certificate"
  value       = aws_acm_certificate.this.arn
}

output "domain_name" {
  description = "Domain name of the certificate"
  value       = aws_acm_certificate.this.domain_name
}

output "dns_validation_record" {
  description = "record which is used to validate acm certificate"
  value       = aws_route53_record.this.name
}
