kube-leader-elect script
===
kubernetes leader election with shell script and `kubectl annotate`

DEPLICATED, move to https://github.com/xiaopal/kube-leaderelect (implemented with golang)

examples
---

```
# leader-holder
kubectl apply -f-<<\EOF
{
  "apiVersion": "v1",
  "kind": "ConfigMap",
  "metadata": {
    "name": "leader-election"
  }
}
EOF

dumb-init ./kube-leader-elect.sh --holder configmap/leader-election --member node1 --lifetime 30 --renew 10 echo master

dumb-init ./kube-leader-elect.sh --holder configmap/leader-election --member node2 --lifetime 30 --renew 10 echo master

```
