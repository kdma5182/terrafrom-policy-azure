variable "client_id" {}
variable "client_secret" {}
variable "tenant_id" {}
//variable "subscription_id" {}
variable "subscription_id_full" {
  description = "Azure Subscription ID"
  type        = string
}
variable "subscription_id" {
  description = "Azure subscription ID (short form)"
  type        = string
}
variable "resource_group_name" {}
variable "location" {}
variable "dcr_name" {}
variable "policy_definition_name" {}
variable "policy_display_name" {}
