provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {
}

# Enable oidc issuer
resource "null_resource" "enable_oidci_issuer" {
  provisioner "local-exec" {
    command = <<-EOT
      az feature register --name EnableOIDCIssuerPreview --namespace Microsoft.ContainerService
    EOT
  }
}
#---------


# General resource group
resource "azurerm_resource_group" "default" {
  name     = "workload-identity-rg"
  location = "West Europe"

  tags = {
    environment = "Demo"
  }
}
#--------


# Create user assigned managed identity that will be used by the AKS service account to access AZ resources
resource "azurerm_user_assigned_identity" "example" {
  name                = "my-user-assigned-identity"
  resource_group_name = azurerm_resource_group.default.name
  location            = "West Europe"
}
#--------

# Create default AKS
resource "azurerm_kubernetes_cluster" "default" {
  name                      = "workload-identity-aks"
  location                  = azurerm_resource_group.default.location
  resource_group_name       = azurerm_resource_group.default.name
  dns_prefix                = "workload-identity-k8s"
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name            = "default"
    node_count      = 1
    vm_size         = "Standard_D2_v3"
    os_disk_size_gb = 30
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    environment = "Dev"
  }

  depends_on = [
    null_resource.enable_oidci_issuer
  ]
}
#---------


# Service account creation. It will be used to access AZ resources
provider "kubernetes" {
  host = azurerm_kubernetes_cluster.default.kube_config.0.host

  client_certificate     = base64decode(azurerm_kubernetes_cluster.default.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.default.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.default.kube_config.0.cluster_ca_certificate)
}


resource "kubernetes_service_account_v1" "sa" {
  metadata {
    name      = "workload-identity-sa"
    namespace = "default"
    annotations = {
      "azure.workload.identity/client-id" : azurerm_user_assigned_identity.example.client_id
    }
    labels = {
      "azure.workload.identity/use" = "true"
    }
  }

  secret {
    name = kubernetes_secret_v1.example.metadata[0].name
  }

}

resource "kubernetes_secret_v1" "example" {
  metadata {
    name = "sa-example"
  }
}
#-------------------

# Create the federated identity credential between the managed identity, the service account issuer, and the subject.
resource "azurerm_federated_identity_credential" "example" {
  name                = "kubernetes-federated-credential"
  resource_group_name = azurerm_resource_group.default.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.default.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.example.id
  subject             = "system:serviceaccount:${kubernetes_service_account_v1.sa.metadata[0].namespace}:${kubernetes_service_account_v1.sa.metadata[0].name}"
}
#--------


# Create a key-vault that can be accessed by "my-user-assigned-identity"
resource "azurerm_key_vault" "example" {
  name                        = "yuriy-examplekeyvault"
  location                    = azurerm_resource_group.default.location
  resource_group_name         = azurerm_resource_group.default.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "Set",
      "List",
      "Delete",
      "Purge"
    ]

  }

  access_policy {
    tenant_id    = data.azurerm_client_config.current.tenant_id
    object_id    = azurerm_user_assigned_identity.example.principal_id

    secret_permissions = [
      "Get"
    ]

  }
}


# Dont do it in PROD, secret in plain text is a bad idea
resource "azurerm_key_vault_secret" "example" {
  name         = "my-secret"
  value        = "secret value from keyvault"
  key_vault_id = azurerm_key_vault.example.id
}
#----------