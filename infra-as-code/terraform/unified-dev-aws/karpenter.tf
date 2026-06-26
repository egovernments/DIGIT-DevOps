# ─────────────────────────────────────────────────────────────────────────────
# Karpenter autoscaler — unified-dev
#
# Aligned with master branch (infra-as-code/terraform/aws/main.tf) with the
# following adaptations for unified-dev:
#   • ARM64 Graviton architecture (existing nodes: t4g.xlarge / t4g.2xlarge)
#   • Two NodePools: on-demand (stateful/PVC) + spot (stateless) — 40/60 split
#   • al2023@latest alias for AMI selection (avoids AMI ID staleness on ARM64)
#   • Fixed EC2NodeClass YAML interpolation bugs present in master template
#   • Fixed NodePool: removed invalid `values` on `Exists` operator
#
# MIGRATION ORDER (must follow exactly):
#   Step 1 → set enable_ClusterAutoscaler=false, run terraform apply
#   Step 2 → set enable_karpenter=true,          run terraform apply
#
# WORKLOAD ROUTING:
#   Stateful / PVC-bound pods  → on-demand NodePool
#     Add to pod spec:
#       nodeSelector:
#         karpenter.sh/capacity-type: on-demand
#       tolerations:
#         - key: workload-type
#           value: stateful
#           effect: NoSchedule
#
#   Stateless / restart-tolerant pods → spot NodePool (default, no changes needed)
# ─────────────────────────────────────────────────────────────────────────────


# ── 1. Additional IAM permissions on node group role for Karpenter ────────────
# Mirrors master branch karpenter_policy. Grants EC2/IAM permissions needed
# by the Karpenter controller (controller uses this role via Pod Identity
# through the karpenter module's association).

resource "aws_iam_role_policy" "karpenter_policy" {
  count      = var.enable_karpenter ? 1 : 0
  depends_on = [module.eks_managed_node_group]
  name       = "karpenter-policy"
  role       = module.eks_managed_node_group.iam_role_name
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:DescribeSpotPriceHistory",
          "pricing:GetProducts",
          "ec2:DescribeInstanceTypeOfferings",
          "iam:CreateInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "ec2:DescribeImages",
          "iam:PassRole",
          "ec2:DescribeLaunchTemplates",
          "ec2:CreateLaunchTemplate",
          "iam:GetInstanceProfile",
          "iam:TagInstanceProfile",
          "ec2:CreateTags",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:DeleteLaunchTemplate",
          "ec2:TerminateInstances",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile"
        ],
        "Resource" : "*"
      }
    ]
  })
}


# ── 2. Karpenter module — reuses existing node group role, no new access entry ─
# Version pinned to 21.3.1 to match master branch.
# create_node_iam_role=false : reuses the managed node group's IAM role for
#   Karpenter-provisioned nodes (role is already registered in EKS access entries).
# create_access_entry=false  : no duplicate access entry for the node group role.

module "karpenter" {
  count      = var.enable_karpenter ? 1 : 0
  source     = "terraform-aws-modules/eks/aws//modules/karpenter"
  version    = "21.3.1"
  cluster_name = module.eks.cluster_name

  create_node_iam_role = false
  node_iam_role_arn    = module.eks_managed_node_group.iam_role_arn
  create_access_entry  = false

  tags = {
    Environment       = var.cluster_name
    Terraform         = "true"
    KubernetesCluster = var.cluster_name
  }
}


# ── 3. Install Karpenter CRDs first (separate chart, wait=true) ───────────────
# Matches master pattern: CRDs installed before the controller to avoid
# race conditions on first apply.

resource "helm_release" "karpenter_crd" {
  count      = var.enable_karpenter ? 1 : 0
  namespace  = "kube-system"
  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = "1.8.1"
  wait       = true
  values     = []
}


# ── 4. Deploy Karpenter controller via Helm (skip_crds=true) ─────────────────
# Uses Pod Identity (no IRSA annotation on serviceAccount) — requires the
# eks-pod-identity-agent addon added to main.tf.

resource "helm_release" "karpenter" {
  count      = var.enable_karpenter ? 1 : 0
  depends_on = [helm_release.karpenter_crd]
  namespace  = "kube-system"
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.8.1"
  wait       = false
  skip_crds  = true

  values = [
    <<-EOT
    logLevel: info
    serviceAccount:
      name: ${var.enable_karpenter ? module.karpenter[0].service_account : ""}
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${var.enable_karpenter ? module.karpenter[0].queue_name : ""}
    # Tolerate the managed node group taint so Karpenter can schedule there.
    # The affinity keeps Karpenter off Karpenter-provisioned nodes (bootstrap safety).
    tolerations:
      - key: dedicated
        value: Karpenter
        effect: NoSchedule
      - key: CriticalAddonsOnly
        operator: Exists
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: karpenter.sh/nodepool
                  operator: DoesNotExist
    EOT
  ]
}


# ── 5. EC2NodeClass — ARM64 AL2023 with 100 GiB encrypted gp3 EBS ────────────
# Fixes from master template:
#   • amiFamily uses proper Terraform interpolation (${var.ami_family.name})
#   • amiSelectorTerms uses alias: al2023@latest (avoids AMI ID staleness on ARM64;
#     Karpenter resolves the correct ARM64 AMI for K8s 1.33 automatically)
#   • Removed the invalid status: block (read-only field; cannot be set in spec)
# Subnets and security groups are auto-discovered via karpenter.sh/discovery tags
# already present on both resources (set in the network module).

resource "kubectl_manifest" "karpenter_node_class" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = <<-YAML
  apiVersion: karpenter.k8s.aws/v1
  kind: EC2NodeClass
  metadata:
    name: default
  spec:
    amiFamily: ${var.ami_family.name}
    amiSelectorTerms:
      - alias: al2023@latest
    role: ${module.eks_managed_node_group.iam_role_name}
    subnetSelectorTerms:
      - tags:
          karpenter.sh/discovery: ${module.eks.cluster_name}
    securityGroupSelectorTerms:
      - tags:
          karpenter.sh/discovery: ${module.eks.cluster_name}
    blockDeviceMappings:
      - deviceName: /dev/xvda
        ebs:
          volumeSize: 100Gi
          volumeType: gp3
          encrypted: true
          deleteOnTermination: true
    tags:
      karpenter.sh/discovery: ${module.eks.cluster_name}
      KubernetesCluster: ${module.eks.cluster_name}
  YAML

  depends_on = [helm_release.karpenter]
}


# ── 6. NodePool: on-demand — stateful / PVC-bound workloads (≈40% capacity) ──
# Instance families with <5% spot interruption frequency in ap-south-1 (ARM64):
#   m6g  Graviton2 general-purpose  (best availability / lowest interruption)
#   m7g  Graviton3 general-purpose  (best availability / lowest interruption)
#   r6g  Graviton2 memory-optimized (good for JVM services, databases)
#
# Taint ensures only explicitly-annotated pods land here. Pods must add:
#   nodeSelector: { karpenter.sh/capacity-type: on-demand }
#   tolerations:  [{ key: workload-type, value: stateful, effect: NoSchedule }]
#
# limits: cpu=80, memory=320Gi ≈ 5 × m6g.xlarge  →  ~40% of combined capacity

resource "kubectl_manifest" "karpenter_node_pool_on_demand" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = <<-YAML
  apiVersion: karpenter.sh/v1
  kind: NodePool
  metadata:
    name: on-demand
  spec:
    weight: 100
    template:
      metadata:
        labels:
          workload-type: stateful
      spec:
        nodeClassRef:
          name: default
          group: karpenter.k8s.aws
          kind: EC2NodeClass
        taints:
          - key: workload-type
            value: stateful
            effect: NoSchedule
        kubelet:
          maxPods: 50
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["arm64"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["r6g", "r7g", "m6g", "m7g"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: ["2", "4"]
          - key: "karpenter.k8s.aws/instance-memory"
            operator: In
            values: ["16384", "32768"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["5"]
          - key: "topology.kubernetes.io/zone"
            operator: In
            values: ["ap-south-1a", "ap-south-1b"]
    limits:
      cpu: "80"
      memory: 320Gi
    disruption:
      consolidationPolicy: WhenEmptyOrUnderutilized
      consolidateAfter: 60s
      budgets:
        - nodes: "20%"
          reasons:
            - "Empty"
            - "Drifted"
        - nodes: "20%"
          reasons:
            - "Underutilized"
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class]
}


# ── 7. NodePool: spot — stateless / restart-tolerant workloads (≈60% capacity) ─
# Default pool — no pod changes required.
# Pods that do NOT tolerate the on-demand taint land here automatically.
# Spot interruptions are handled gracefully via the SQS interruption queue.
#
# Instance families (ap-south-1, ARM64, <5% spot interruption frequency):
#   m6g / m7g  Graviton general-purpose  (lowest interruption, best availability)
#   r6g        Graviton memory-optimized  (good for JVM / in-memory caches)
#   c6g / c7g  Graviton compute-optimized (good for CPU-bound services)
# t4g is excluded — burstable family sees 10–15% interruption vs <5% above.
#
# limits: cpu=120, memory=480Gi ≈ 7–8 × m6g.xlarge → ~60% of combined capacity
# budgets.nodes="20%" prevents Karpenter from evicting more than 20% of spot
# nodes simultaneously during consolidation.

resource "kubectl_manifest" "karpenter_node_pool_spot" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = <<-YAML
  apiVersion: karpenter.sh/v1
  kind: NodePool
  metadata:
    name: spot
  spec:
    weight: 50
    template:
      metadata:
        labels:
          workload-type: stateless
      spec:
        nodeClassRef:
          name: default
          group: karpenter.k8s.aws
          kind: EC2NodeClass
        kubelet:
          maxPods: 50
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["arm64"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["r6g", "r7g", "m6g", "m7g"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: ["2", "4"]
          - key: "karpenter.k8s.aws/instance-memory"
            operator: In
            values: ["16384", "32768"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["5"]
          - key: "topology.kubernetes.io/zone"
            operator: In
            values: ["ap-south-1a", "ap-south-1b"]
    limits:
      cpu: "120"
      memory: 480Gi
    disruption:
      consolidationPolicy: WhenEmptyOrUnderutilized
      consolidateAfter: 300s
      budgets:
        - nodes: "20%"
          reasons:
            - "Empty"
            - "Drifted"
        - nodes: "20%"
          reasons:
            - "Underutilized"
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class]
}
