####
## Route53
####

resource "aws_route53_zone" "hosted_zone" {
  name = "staging.zing.you"
}
