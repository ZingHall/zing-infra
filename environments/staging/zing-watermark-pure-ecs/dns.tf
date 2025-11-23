# Optional: Route53 Record for NLB
# Note: NLB doesn't support Route53 alias records, so we can use the NLB DNS name directly
# This is optional - TEE can connect directly to NLB DNS name

# For internal services, using NLB DNS name directly is recommended
# If you need a custom DNS name, you can create a CNAME record (not alias)

# Uncomment if you want a custom DNS name via CNAME
resource "aws_route53_record" "watermark_nlb" {
  zone_id = data.terraform_remote_state.network.outputs.hosted_zone_id
  name    = "watermark.internal.staging.zing.you"
  type    = "CNAME"
  ttl     = 300
  records = [aws_lb.watermark_nlb.dns_name]
}

# Note: For mTLS connections, TEE should use the NLB DNS name directly:
# - NLB DNS: <nlb-dns-name>.elb.ap-northeast-1.amazonaws.com
# - Or use the output: nlb_dns_name

