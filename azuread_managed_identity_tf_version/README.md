```
terraform init
```

```
terraform plan
```

```
terraform apply
```


```
chmod +x k8s/deploy-pod-with-kv-access.sh
```

```
az aks get-credentials --resource-group workload-identity-rg --name workload-identity-aks
```


```
./k8s/deploy-pod-with-kv-access.sh
```

```
kubectl logs pod/quick-start 
```


