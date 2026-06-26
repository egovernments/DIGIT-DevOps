# ─────────────────────────────────────────────────────────────────────────────
# CloudWatch alerts for Karpenter — unified-dev
#
# Signal sources:
#   1. Spot interruption / rebalance  → EventBridge → Spot SNS (immediate)
#   2. Spot interruption              → EventBridge → CloudWatch Logs (audit)
#   3. Karpenter disruption reasons   → Fluent Bit → CloudWatch Logs
#                                       → metric filter → alarm → EventBridge
#                                       → Karpenter SNS
#
# Enable with: enable_cloudwatch_alarms = true
# Set alert_email to receive email notifications (requires SNS confirmation).
# ─────────────────────────────────────────────────────────────────────────────


# ── 1. SNS topics ─────────────────────────────────────────────────────────────

resource "aws_sns_topic" "spot_alerts" {
  count        = var.enable_cloudwatch_alarms ? 1 : 0
  name         = "${var.cluster_name}-spot-alerts"
  display_name = "Spot Alerts | ${var.cluster_name}"
  tags = {
    KubernetesCluster = var.cluster_name
    Name              = "${var.cluster_name}-spot-alerts"
  }
}

resource "aws_sns_topic" "karpenter_alerts" {
  count        = var.enable_cloudwatch_alarms ? 1 : 0
  name         = "${var.cluster_name}-karpenter-alerts"
  display_name = "Karpenter Alerts | ${var.cluster_name}"
  tags = {
    KubernetesCluster = var.cluster_name
    Name              = "${var.cluster_name}-karpenter-alerts"
  }
}

resource "aws_sns_topic_subscription" "spot_alerts_email" {
  count     = var.enable_cloudwatch_alarms && var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.spot_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "karpenter_alerts_email" {
  count     = var.enable_cloudwatch_alarms && var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.karpenter_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_policy" "spot_alerts" {
  count  = var.enable_cloudwatch_alarms ? 1 : 0
  arn    = aws_sns_topic.spot_alerts[0].arn
  policy = data.aws_iam_policy_document.spot_alerts_topic_policy[0].json
}

resource "aws_sns_topic_policy" "karpenter_alerts" {
  count  = var.enable_cloudwatch_alarms ? 1 : 0
  arn    = aws_sns_topic.karpenter_alerts[0].arn
  policy = data.aws_iam_policy_document.karpenter_alerts_topic_policy[0].json
}

data "aws_iam_policy_document" "spot_alerts_topic_policy" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  statement {
    sid       = "AllowEventBridgePublish"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.spot_alerts[0].arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "karpenter_alerts_topic_policy" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  statement {
    sid       = "AllowEventBridgePublish"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.karpenter_alerts[0].arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}


# ── 2. CloudWatch Log Groups ──────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "karpenter" {
  count             = var.enable_cloudwatch_alarms ? 1 : 0
  name              = "/aws/eks/${var.cluster_name}/karpenter"
  retention_in_days = 30
  tags = {
    KubernetesCluster = var.cluster_name
  }
}

resource "aws_cloudwatch_log_group" "spot_interruptions" {
  count             = var.enable_cloudwatch_alarms ? 1 : 0
  name              = "/aws/eks/${var.cluster_name}/spot-interruptions"
  retention_in_days = 30
  tags = {
    KubernetesCluster = var.cluster_name
  }
}


# ── 3. IAM: CloudWatch Logs write permission on node group role ───────────────

resource "aws_iam_role_policy" "cloudwatch_logs_policy" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  name  = "cloudwatch-logs-policy"
  role  = module.eks_managed_node_group.iam_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}


# ── 4. Fluent Bit: Forward Karpenter pod logs to CloudWatch ───────────────────
# Targets only /var/log/containers/*karpenter*.log so it does not forward
# all cluster logs — keeps CloudWatch ingestion cost low.
# Tolerates all taints so it runs on both on-demand and spot nodes.

resource "helm_release" "fluent_bit" {
  count      = var.enable_cloudwatch_alarms ? 1 : 0
  depends_on = [module.eks_managed_node_group, aws_cloudwatch_log_group.karpenter, aws_iam_role_policy.cloudwatch_logs_policy]

  namespace        = "kube-system"
  name             = "fluent-bit"
  repository       = "https://fluent.github.io/helm-charts"
  chart            = "fluent-bit"
  version          = "0.47.10"
  create_namespace = false
  wait             = true

  values = [
    <<-EOT
    config:
      inputs: |
        [INPUT]
            Name              tail
            Path              /var/log/containers/*karpenter*.log
            multiline.parser  cri
            Tag               karpenter.*
            Refresh_Interval  5
            Skip_Long_Lines   Off
            DB                /var/log/flb_karpenter.db

      filters: |
        [FILTER]
            Name              kubernetes
            Match             karpenter.*
            Merge_Log         On
            Keep_Log          Off
            K8S-Logging.Parser On
            K8S-Logging.Exclude On

      outputs: |
        [OUTPUT]
            Name                cloudwatch_logs
            Match               karpenter.*
            region              ap-south-1
            log_group_name      /aws/eks/${var.cluster_name}/karpenter
            log_stream_prefix   karpenter-
            auto_create_group   false

    tolerations:
      - operator: Exists
    EOT
  ]
}


# ── 5. EventBridge: Spot interruption → SNS (immediate) + Logs (audit) ───────

resource "aws_cloudwatch_log_resource_policy" "spot_interruptions" {
  count       = var.enable_cloudwatch_alarms ? 1 : 0
  policy_name = "${var.cluster_name}-spot-interruptions-policy"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = ["events.amazonaws.com", "delivery.logs.amazonaws.com"] }
        Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource  = "${aws_cloudwatch_log_group.spot_interruptions[0].arn}:*"
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  count       = var.enable_cloudwatch_alarms ? 1 : 0
  name        = "${var.cluster_name}-spot-interruption"
  description = "EC2 Spot Instance Interruption Warnings for ${var.cluster_name}"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
  tags = { KubernetesCluster = var.cluster_name }
}

resource "aws_cloudwatch_event_target" "spot_interruption_sns" {
  count     = var.enable_cloudwatch_alarms ? 1 : 0
  rule      = aws_cloudwatch_event_rule.spot_interruption[0].name
  target_id = "spot-interruption-sns"
  arn       = aws_sns_topic.spot_alerts[0].arn

  input_transformer {
    input_paths = {
      instance_action = "$.detail.instance-action"
      instance_id     = "$.detail.instance-id"
      region          = "$.region"
      time            = "$.time"
    }

    input_template = <<-EOT
      "EC2 Spot Interruption Warning"
      "Cluster: ${var.cluster_name}"
      "Description: AWS expects this Spot instance to be interrupted soon. Karpenter or the workload controller should replace affected capacity before interruption if possible."
      "Instance action: <instance_action>"
      "Region: <region>"
      "Event time: <time>"
      "Instance ID: <instance_id>"
    EOT
  }
}

resource "aws_cloudwatch_event_target" "spot_interruption_logs" {
  count     = var.enable_cloudwatch_alarms ? 1 : 0
  rule      = aws_cloudwatch_event_rule.spot_interruption[0].name
  target_id = "spot-interruption-logs"
  arn       = aws_cloudwatch_log_group.spot_interruptions[0].arn
}

resource "aws_cloudwatch_event_rule" "spot_rebalance" {
  count       = var.enable_cloudwatch_alarms ? 1 : 0
  name        = "${var.cluster_name}-spot-rebalance"
  description = "EC2 Spot Instance Rebalance Recommendations for ${var.cluster_name}"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })
  tags = { KubernetesCluster = var.cluster_name }
}

resource "aws_cloudwatch_event_target" "spot_rebalance_sns" {
  count     = var.enable_cloudwatch_alarms ? 1 : 0
  rule      = aws_cloudwatch_event_rule.spot_rebalance[0].name
  target_id = "spot-rebalance-sns"
  arn       = aws_sns_topic.spot_alerts[0].arn

  input_transformer {
    input_paths = {
      instance_id   = "$.detail.instance-id"
      instance_type = "$.detail.instance-type"
      region        = "$.region"
      time          = "$.time"
    }

    input_template = <<-EOT
      "EC2 Spot Rebalance Recommendation"
      "Cluster: ${var.cluster_name}"
      "Description: AWS recommends proactively replacing this Spot instance because it has an elevated risk of interruption."
      "Instance ID: <instance_id>"
      "Instance type: <instance_type>"
      "Region: <region>"
      "Event time: <time>"
    EOT
  }
}


# ── 6. Metric filters: Karpenter disruption reasons ──────────────────────────
# Karpenter v1.x logs structured JSON. The disruption controller emits:
#   {"level":"info","logger":"controller.disruption","reason":"Empty",...}
#   {"level":"info","logger":"controller.disruption","reason":"Underutilized",...}
#   {"level":"info","logger":"controller.disruption","reason":"Drifted",...}

resource "aws_cloudwatch_log_metric_filter" "karpenter_node_launched" {
  count          = var.enable_cloudwatch_alarms ? 1 : 0
  name           = "${var.cluster_name}-karpenter-node-launched"
  log_group_name = aws_cloudwatch_log_group.karpenter[0].name
  # Karpenter v1.x structured log emitted by controller.nodeclaim.lifecycle
  pattern = "{ $.msg = \"launched nodeclaim\" }"
  metric_transformation {
    name      = "KarpenterNodeLaunched"
    namespace = "Karpenter/${var.cluster_name}"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "karpenter_disruption_empty" {
  count          = var.enable_cloudwatch_alarms ? 1 : 0
  name           = "${var.cluster_name}-karpenter-disruption-empty"
  log_group_name = aws_cloudwatch_log_group.karpenter[0].name
  pattern        = "{ $.reason = \"Empty\" }"
  metric_transformation {
    name      = "KarpenterDisruptionEmpty"
    namespace = "Karpenter/${var.cluster_name}"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "karpenter_disruption_underutilized" {
  count          = var.enable_cloudwatch_alarms ? 1 : 0
  name           = "${var.cluster_name}-karpenter-disruption-underutilized"
  log_group_name = aws_cloudwatch_log_group.karpenter[0].name
  pattern        = "{ $.reason = \"Underutilized\" }"
  metric_transformation {
    name      = "KarpenterDisruptionUnderutilized"
    namespace = "Karpenter/${var.cluster_name}"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "karpenter_disruption_drifted" {
  count          = var.enable_cloudwatch_alarms ? 1 : 0
  name           = "${var.cluster_name}-karpenter-disruption-drifted"
  log_group_name = aws_cloudwatch_log_group.karpenter[0].name
  pattern        = "{ $.reason = \"Drifted\" }"
  metric_transformation {
    name      = "KarpenterDisruptionDrifted"
    namespace = "Karpenter/${var.cluster_name}"
    value     = "1"
    unit      = "Count"
  }
}


# ── 7. CloudWatch Alarms ─────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "karpenter_node_launched" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.cluster_name}-karpenter-node-launched"
  alarm_description   = "Karpenter launched a new node (NodeClaim) in cluster ${var.cluster_name}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "KarpenterNodeLaunched"
  namespace           = "Karpenter/${var.cluster_name}"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  tags                = { KubernetesCluster = var.cluster_name }
}

resource "aws_cloudwatch_metric_alarm" "karpenter_disruption_empty" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.cluster_name}-karpenter-disruption-empty"
  alarm_description   = "Karpenter removed a node with reason=Empty in cluster ${var.cluster_name}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "KarpenterDisruptionEmpty"
  namespace           = "Karpenter/${var.cluster_name}"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  tags                = { KubernetesCluster = var.cluster_name }
}

resource "aws_cloudwatch_metric_alarm" "karpenter_disruption_underutilized" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.cluster_name}-karpenter-disruption-underutilized"
  alarm_description   = "Karpenter removed a node with reason=Underutilized in cluster ${var.cluster_name}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "KarpenterDisruptionUnderutilized"
  namespace           = "Karpenter/${var.cluster_name}"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  tags                = { KubernetesCluster = var.cluster_name }
}

resource "aws_cloudwatch_metric_alarm" "karpenter_disruption_drifted" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.cluster_name}-karpenter-disruption-drifted"
  alarm_description   = "Karpenter removed a node with reason=Drifted in cluster ${var.cluster_name}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "KarpenterDisruptionDrifted"
  namespace           = "Karpenter/${var.cluster_name}"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  tags                = { KubernetesCluster = var.cluster_name }
}


# ── 8. EventBridge: Karpenter alarms → SNS (human readable) ──────────────────

resource "aws_cloudwatch_event_rule" "karpenter_node_launched_alarm" {
  count       = var.enable_cloudwatch_alarms ? 1 : 0
  name        = "${var.cluster_name}-karpenter-node-launched-alarm"
  description = "Karpenter node launch alarm state changes for ${var.cluster_name}"
  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [aws_cloudwatch_metric_alarm.karpenter_node_launched[0].alarm_name]
      state = {
        value = ["ALARM"]
      }
    }
  })
  tags = { KubernetesCluster = var.cluster_name }
}

resource "aws_cloudwatch_event_target" "karpenter_node_launched_sns" {
  count     = var.enable_cloudwatch_alarms ? 1 : 0
  rule      = aws_cloudwatch_event_rule.karpenter_node_launched_alarm[0].name
  target_id = "karpenter-node-launched-sns"
  arn       = aws_sns_topic.karpenter_alerts[0].arn

  input_transformer {
    input_paths = {
      alarm_name     = "$.detail.alarmName"
      current_state  = "$.detail.state.value"
      event_time     = "$.time"
      previous_state = "$.detail.previousState.value"
      region         = "$.region"
    }

    input_template = <<-EOT
      "Karpenter Node Launched"
      "Cluster: ${var.cluster_name}"
      "Description: Karpenter launched a new node (NodeClaim) to satisfy pending pod capacity."
      "Alarm name: <alarm_name>"
      "State: <previous_state> -> <current_state>"
      "Region: <region>"
      "Event time: <event_time>"
    EOT
  }
}

resource "aws_cloudwatch_event_rule" "karpenter_disruption_empty_alarm" {
  count       = var.enable_cloudwatch_alarms ? 1 : 0
  name        = "${var.cluster_name}-karpenter-empty-alarm"
  description = "Karpenter Empty disruption alarm state changes for ${var.cluster_name}"
  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [aws_cloudwatch_metric_alarm.karpenter_disruption_empty[0].alarm_name]
      state = {
        value = ["ALARM"]
      }
    }
  })
  tags = { KubernetesCluster = var.cluster_name }
}

resource "aws_cloudwatch_event_target" "karpenter_disruption_empty_sns" {
  count     = var.enable_cloudwatch_alarms ? 1 : 0
  rule      = aws_cloudwatch_event_rule.karpenter_disruption_empty_alarm[0].name
  target_id = "karpenter-empty-sns"
  arn       = aws_sns_topic.karpenter_alerts[0].arn

  input_transformer {
    input_paths = {
      alarm_name     = "$.detail.alarmName"
      current_state  = "$.detail.state.value"
      event_time     = "$.time"
      previous_state = "$.detail.previousState.value"
      reason         = "$.detail.state.reason"
      region         = "$.region"
    }

    input_template = <<-EOT
      "Karpenter Node Disruption Alert"
      "Cluster: ${var.cluster_name}"
      "Description: Karpenter removed or started removing a node because it was Empty."
      "Disruption reason: Empty"
      "Alarm name: <alarm_name>"
      "State: <previous_state> -> <current_state>"
      "Region: <region>"
      "Event time: <event_time>"
      "CloudWatch reason: <reason>"
    EOT
  }
}

resource "aws_cloudwatch_event_rule" "karpenter_disruption_underutilized_alarm" {
  count       = var.enable_cloudwatch_alarms ? 1 : 0
  name        = "${var.cluster_name}-karpenter-underutilized-alarm"
  description = "Karpenter Underutilized disruption alarm state changes for ${var.cluster_name}"
  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [aws_cloudwatch_metric_alarm.karpenter_disruption_underutilized[0].alarm_name]
      state = {
        value = ["ALARM"]
      }
    }
  })
  tags = { KubernetesCluster = var.cluster_name }
}

resource "aws_cloudwatch_event_target" "karpenter_disruption_underutilized_sns" {
  count     = var.enable_cloudwatch_alarms ? 1 : 0
  rule      = aws_cloudwatch_event_rule.karpenter_disruption_underutilized_alarm[0].name
  target_id = "karpenter-underutilized-sns"
  arn       = aws_sns_topic.karpenter_alerts[0].arn

  input_transformer {
    input_paths = {
      alarm_name     = "$.detail.alarmName"
      current_state  = "$.detail.state.value"
      event_time     = "$.time"
      previous_state = "$.detail.previousState.value"
      reason         = "$.detail.state.reason"
      region         = "$.region"
    }

    input_template = <<-EOT
      "Karpenter Node Disruption Alert"
      "Cluster: ${var.cluster_name}"
      "Description: Karpenter removed or started removing a node because it was Underutilized."
      "Disruption reason: Underutilized"
      "Alarm name: <alarm_name>"
      "State: <previous_state> -> <current_state>"
      "Region: <region>"
      "Event time: <event_time>"
      "CloudWatch reason: <reason>"
    EOT
  }
}

resource "aws_cloudwatch_event_rule" "karpenter_disruption_drifted_alarm" {
  count       = var.enable_cloudwatch_alarms ? 1 : 0
  name        = "${var.cluster_name}-karpenter-drifted-alarm"
  description = "Karpenter Drifted disruption alarm state changes for ${var.cluster_name}"
  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [aws_cloudwatch_metric_alarm.karpenter_disruption_drifted[0].alarm_name]
      state = {
        value = ["ALARM"]
      }
    }
  })
  tags = { KubernetesCluster = var.cluster_name }
}

resource "aws_cloudwatch_event_target" "karpenter_disruption_drifted_sns" {
  count     = var.enable_cloudwatch_alarms ? 1 : 0
  rule      = aws_cloudwatch_event_rule.karpenter_disruption_drifted_alarm[0].name
  target_id = "karpenter-drifted-sns"
  arn       = aws_sns_topic.karpenter_alerts[0].arn

  input_transformer {
    input_paths = {
      alarm_name     = "$.detail.alarmName"
      current_state  = "$.detail.state.value"
      event_time     = "$.time"
      previous_state = "$.detail.previousState.value"
      reason         = "$.detail.state.reason"
      region         = "$.region"
    }

    input_template = <<-EOT
      "Karpenter Node Disruption Alert"
      "Cluster: ${var.cluster_name}"
      "Description: Karpenter removed or started removing a node because it was Drifted."
      "Disruption reason: Drifted"
      "Alarm name: <alarm_name>"
      "State: <previous_state> -> <current_state>"
      "Region: <region>"
      "Event time: <event_time>"
      "CloudWatch reason: <reason>"
    EOT
  }
}
