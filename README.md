kube-leader-elect script
===
kubernetes leader election with shell script and `kubectl annotate`


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

./kube-leader-elect.sh --holder configmap/leader-election --member node1 --lifetime 30 --renew 10 echo master

./kube-leader-elect.sh --holder configmap/leader-election --member node2 --lifetime 30 --renew 10 echo master

```
