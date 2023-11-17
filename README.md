Add & remove kubernetes clusters to & from `~/.kube/config`, allowing you to use `kubectl` from your local machine.

```ini
Usage: ./kubecp.sh [OPTIONS] [USER@]IP [CLUSTER-NAME]

Options:
  -a | --add      add cluster to ~/.kube/config
  -r | --remove   remove cluster from ~/.kube/config
  -h | --help     show this menu

Positional arguments:
  USER            user with which to connect, defaults to root
  CLUSTER-NAME    name of the cluster to use in ~/.kube/config
                  (optional, defaults to <ip>-cluster)
  IP              IP or hostname corresponding to the master of the cluster

Dependencies: scp, rg, awk, kubectl
```

Example usage: `./kubecp.sh -a root@some-host`
