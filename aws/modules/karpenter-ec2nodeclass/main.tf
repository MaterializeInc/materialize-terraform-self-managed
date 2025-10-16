locals {
  # Generated with:
  # aws ec2 describe-instance-types --query "InstanceTypes[]"
  instance_descriptions = jsondecode(file("${path.module}/instance-descriptions.json"))

  # While the VM overhead is lower as a percentage of the node with larger instance types,
  # in absolute terms it is larger, so we use the largest instance type we expect to support
  # when calculating the reserved values.
  instance_memory = max([
    for instance_type, description in local.instance_descriptions :
    description["MemoryInfo"]["SizeInMiB"]
    if contains(var.instance_types, description["InstanceType"])
  ]...)
  instance_cpus = max([
    for instance_type, description in local.instance_descriptions :
    description["VCpuInfo"]["DefaultVCpus"]
    if contains(var.instance_types, description["InstanceType"])
  ]...)

  pods_per_slot = var.prefix_delegation_enabled ? 16 : 1
  max_pods = min([
    for instance_type, description in local.instance_descriptions :
    (description["NetworkInfo"]["MaximumNetworkInterfaces"] - 1) * (description["NetworkInfo"]["Ipv4AddressesPerInterface"] - 1) * local.pods_per_slot
    if contains(var.instance_types, description["InstanceType"])
  ]...)

  mem_0gib_to_4gib    = min(local.instance_memory, 4096)
  mem_4gib_to_8gib    = max(0, min(local.instance_memory, 8192) - 4096)
  mem_8gib_to_16gib   = max(0, min(local.instance_memory, 16384) - 8192)
  mem_16gib_to_128gib = max(0, min(local.instance_memory, 131072) - 16384)
  mem_over_128gib     = max(0, local.instance_memory - 131072)

  kube_reserved_mem_mib = ceil(
    (local.mem_0gib_to_4gib * 0.25)
    + (local.mem_4gib_to_8gib * 0.1)
    + (local.mem_8gib_to_16gib * 0.05)
    + (local.mem_16gib_to_128gib * 0.03)
    + (local.mem_over_128gib * 0.01)
  )
  kube_reserved_memory_description = local.kube_reserved_mem_mib % 1024 == 0 ? "${local.kube_reserved_mem_mib / 1024}Gi" : "${local.kube_reserved_mem_mib}Mi"

  first_core             = 1
  second_core            = max(0, local.instance_cpus - 1)
  third_and_fourth_cores = max(0, local.instance_cpus - 2)
  fifth_and_more_cores   = max(0, local.instance_cpus - 4)

  kube_reserved_mcpus = ceil(
    (local.first_core * 60)
    + (local.second_core * 10)
    + (local.third_and_fourth_cores * 5)
    + (local.fifth_and_more_cores * 2.5)
  )
  kube_reserved_cpus_description = local.kube_reserved_mcpus % 1000 == 0 ? tostring(local.kube_reserved_mcpus / 1000) : "${local.kube_reserved_mcpus}m"

  bottlerocket_block_device_mappings = [
    {
      "deviceName" : "/dev/xvda",
      "ebs" : {
        "deleteOnTermination" : true,
        "encrypted" : true,
        "volumeSize" : "4Gi",
        "volumeType" : "gp3",
      }
    },
    {
      "deviceName" : "/dev/xvdb",
      "ebs" : {
        "deleteOnTermination" : true,
        "encrypted" : true,
        "volumeSize" : "100Gi",
        "volumeType" : "gp3",
      }
      "rootVolume" : true,
    }
  ]

  default_userdata = <<-EOF
    [settings.oci-defaults.resource-limits.max-open-files]
    soft-limit = 1048576
    hard-limit = 1048576
  EOF

  swap_bootstrap_args = <<-EOF
    [settings.bootstrap-containers.diskstrap]
    source = "${var.disk_setup_image}"
    mode = "always"
    essential = true
    user-data = "${base64encode(jsonencode(["swap", "--cloud-provider", "aws", "--bottlerocket-enable-swap"]))}"

    [settings.kernel.sysctl]
    "vm.swappiness" = "100"
    "vm.min_free_kbytes" = "1048576"
    "vm.watermark_scale_factor" = "100"
  EOF

  userdata = var.swap_enabled ? "${local.default_userdata}\n${local.swap_bootstrap_args}" : local.default_userdata
}

resource "kubectl_manifest" "ec2nodeclass" {
  yaml_body = jsonencode(
    {
      "apiVersion" : "karpenter.k8s.aws/v1",
      "kind" : "EC2NodeClass",
      "metadata" : {
        "name" : var.name,
      },
      "spec" : {
        "amiFamily" : "Bottlerocket",
        "amiSelectorTerms" : var.ami_selector_terms,
        "blockDeviceMappings" : local.bottlerocket_block_device_mappings,
        "instanceProfile" : var.instance_profile,
        "kubelet" : {
          # TODO "clusterDNS"
          "cpuCFSQuota" : true,
          "evictionHard" : {
            "memory.available" : "100Mi",
            "nodefs.available" : "10%",
            "nodefs.inodesFree" : "10%",
          },
          "evictionSoft" : {
            "memory.available" : "200Mi",
          },
          "evictionSoftGracePeriod" : {
            "memory.available" : "1m0s",
          },
          "imageGCHighThresholdPercent" : 60,
          "imageGCLowThresholdPercent" : 40,
          "kubeReserved" : {
            "cpu" : local.kube_reserved_cpus_description,
            "memory" : local.kube_reserved_memory_description,
          },
          "maxPods" : local.max_pods,
          "systemReserved" : {
            "memory" : "100Mi",
          },
        },
        "userData" : local.userdata,
        "securityGroupSelectorTerms" : [for id in var.security_group_ids : { "id" : id }],
        "subnetSelectorTerms" : [for id in var.subnet_ids : { "id" : id }],
        "tags" : var.tags,
      },
    }
  )
}

