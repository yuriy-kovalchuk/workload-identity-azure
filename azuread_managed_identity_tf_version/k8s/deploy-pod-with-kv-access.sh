KEYVAULT_URL=$(az keyvault show --name "yuriy-examplekeyvault" --query "properties.vaultUri" --output tsv)
echo "KEYVAULT_URL -> ${KEYVAULT_URL}"


cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: quick-start
  namespace: default
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: "workload-identity-sa"
  containers:
    - image: ghcr.io/azure/azure-workload-identity/msal-go
      name: oidc
      env:
      - name: KEYVAULT_URL
        value: ${KEYVAULT_URL}
      - name: SECRET_NAME
        value: "my-secret"
  nodeSelector:
    kubernetes.io/os: linux
EOF