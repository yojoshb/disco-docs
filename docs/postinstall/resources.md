## Patch the OperatorHub default sources 

This patch disables the cluster from attempting to reach Red Hat's OperatorHub 
```bash
$ oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
operatorhub.config.openshift.io/cluster patched
```

## Configure the cluster to use the resources you mirrored