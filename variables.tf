variable "subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
}

variable "student_name" {
  description = "Lowercase student name used in the [resource]-uvu-it3200-[studentname] naming convention."
  type        = string
  default     = "douglas"

  validation {
    condition     = can(regex("^[a-z0-9]{2,20}$", var.student_name))
    error_message = "Use 2-20 lowercase letters or numbers (it is also part of the ACR name)."
  }
}

variable "acr_name_suffix" {
  description = "Optional digits/letters appended to the ACR name if acruvuit3200<student> is already taken globally."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9]{0,6}$", var.acr_name_suffix))
    error_message = "Suffix must be 0-6 lowercase letters or numbers."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westus2"
}

variable "node_vm_size" {
  description = "VM size for the single system node. Needs at least 2 vCPU / 4 GiB."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "node_count" {
  description = "Number of nodes in the default pool."
  type        = number
  default     = 1
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version. null = the current AKS default."
  type        = string
  default     = null
}

variable "app_namespace" {
  description = "Kubernetes namespace the service principal is allowed to deploy into."
  type        = string
  default     = "hello-web"
}

variable "sp_secret_lifetime_days" {
  description = "How long the lab client secret stays valid."
  type        = number
  default     = 7
}

# ---------------------------------------------------------------------------
# Access toggles. These let you walk through the assignment one step at a time
# and capture the failures / fixes with Terraform as the only source of change.
# ---------------------------------------------------------------------------

variable "sp_access_stage" {
  description = <<-EOT
    How much AKS access the service principal gets:
      none        - no role assignments (authentication works, authorization fails)
      credentials - Azure Kubernetes Service Cluster User Role only (can download kubeconfig, kubectl is Forbidden)
      deployer    - Cluster User + RBAC Reader (cluster) + RBAC Writer (app namespace only)
  EOT
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "credentials", "deployer"], var.sp_access_stage)
    error_message = "sp_access_stage must be none, credentials, or deployer."
  }
}

variable "operator_access_enabled" {
  description = "Give your own user account read access to the cluster plus permission to create namespaces (custom role). No Cluster Admin."
  type        = bool
  default     = false
}

variable "kubelet_acr_pull_enabled" {
  description = "Grant the AKS kubelet identity AcrPull on the registry. Set false for the optional break-and-fix bonus."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags for every resource."
  type        = map(string)
  default     = {}
}
