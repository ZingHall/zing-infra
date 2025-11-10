output "alb_id" {
  description = "ALB ID"
  value       = aws_alb.this.id
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_alb.this.arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_alb.this.dns_name
}

output "alb_zone_id" {
  description = "ALB Zone ID for Route53 alias records"
  value       = aws_alb.this.zone_id
}

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "https_listener_arn" {
  description = "HTTPS listener ARN"
  value       = aws_alb_listener.https.arn
}

output "http_listener_arn" {
  description = "HTTP listener ARN (empty if redirect disabled)"
  value       = var.http_redirect ? aws_alb_listener.http[0].arn : ""
}

output "target_group_arns" {
  description = "Map of service names to target group ARNs"
  value       = { for k, tg in aws_alb_target_group.services : k => tg.arn }
}

output "target_group_names" {
  description = "Map of service names to target group names"
  value       = { for k, tg in aws_alb_target_group.services : k => tg.name }
}

output "service_endpoints" {
  description = "Map of service names to their HTTPS endpoints"
  value = {
    for k, svc in var.services : k => "https://${svc.host_headers[0]}"
  }
}

