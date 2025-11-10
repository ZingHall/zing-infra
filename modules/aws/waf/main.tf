resource "aws_wafv2_ip_set" "dynamic_sets" {
  for_each = var.ip_sets_definition

  name               = "${var.name}-${each.key}-ip-set"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = each.value
  tags               = { Name = "${var.name}-${each.key}-ip-set" }
}

resource "aws_wafv2_web_acl" "web_acl" {
  name        = "${var.name}-web-acl"
  scope       = "REGIONAL"
  description = "WAF for allow rules"

  default_action {
    block {}
  }

  dynamic "rule" {
    for_each = var.allow_rules
    content {
      name     = rule.value.name
      priority = rule.key + 1
      action {
        allow {}
      }

      //only take effect if either ip_set_key or header_names is not null (because and_statement does not support single statement)
      dynamic "statement" {
        for_each = rule.value.ip_set_key != null || rule.value.header_names != null ? [1] : []
        content {
          and_statement {
            statement {
              byte_match_statement {
                search_string = rule.value.path
                field_to_match {
                  uri_path {}
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
                positional_constraint = "STARTS_WITH"
              }
            }

            dynamic "statement" {
              for_each = rule.value.ip_set_key != null ? [1] : []
              content {
                ip_set_reference_statement {
                  arn = aws_wafv2_ip_set.dynamic_sets[rule.value.ip_set_key].arn
                }
              }
            }

            dynamic "statement" {
              for_each = rule.value.header_names != null ? rule.value.header_names : []
              content {
                size_constraint_statement {
                  field_to_match {
                    single_header {
                      name = statement.value
                    }
                  }
                  comparison_operator = "GT"
                  size                = 0
                  text_transformation {
                    priority = 0
                    type     = "NONE"
                  }
                }
              }
            }
          }
        }
      }

      //only take effect if ip_set_key and header_names are null
      dynamic "statement" {
        for_each = rule.value.ip_set_key == null && rule.value.header_names == null ? [1] : []
        content {
          byte_match_statement {
            search_string = rule.value.path
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
            positional_constraint = "STARTS_WITH"
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = rule.value.metric_name != null ? true : false
        metric_name                = rule.value.metric_name != null ? rule.value.metric_name : "${var.name}-allow-rule-${rule.key + 1}"
        sampled_requests_enabled   = rule.value.metric_name != null ? true : false
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${var.name}-web-acl" }
}

resource "aws_cloudwatch_log_group" "waf_logs" {
  name              = "aws-waf-logs-${var.name}-webacl" //this log group must start with aws-waf-logs-
  retention_in_days = 30

  tags = {
    Name = "${var.name}-waf-logs"
  }
}

resource "aws_wafv2_web_acl_association" "web_acl_association" {
  resource_arn = var.resource_to_protect_arn
  web_acl_arn  = aws_wafv2_web_acl.web_acl.arn
}

resource "aws_wafv2_web_acl_logging_configuration" "waf_logs" {
  depends_on              = [aws_cloudwatch_log_group.waf_logs]
  log_destination_configs = [aws_cloudwatch_log_group.waf_logs.arn]
  resource_arn            = aws_wafv2_web_acl.web_acl.arn
}
