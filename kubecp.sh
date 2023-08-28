#!/usr/bin/env bash

printhelp () {
	echo "Usage: ./kubecp.sh [OPTIONS] [USER@]IP [CLUSTER-NAME]"
	echo ""
	echo "Options:"
	echo "  -a | --add      add cluster to ~/.kube/config"
	echo "  -r | --remove   remove cluster from ~/.kube/config"
	echo "  -h | --help     show this menu"
	echo
	echo "Positional arguments:"
	echo "  USER            user with which to connect, defaults to root"
	echo "  CLUSTER-NAME    name of cluster (optional, defaults to IP-cluster)"
	echo "  IP              IP of the server where there is a ~/.kube/config"
	echo "                  file for the cluster you want to add"
	echo ""
	echo "Dependencies: scp, rg, awk, kubectl"

}

invalid-combo () { echo "Invalid combination of arguments - exiting..."; }
invalid-arg () { echo "Invalid argument: "$1" - exiting..."; }


OPTIONS=$(getopt -o arh --long add,remove,help -n "$0" -- "$@")
eval set -- "$OPTIONS"

OPERATION=

while true; do
	case "$1" in
		"-h" | "--help")
			printhelp
			exit 0
			;;
		"-a" | "--add")
			if [[ -n "$OPERATION" ]]; then invalid-combo; fi
			OPERATION="add"
			shift
			;;
		"-r" | "--remove")
			if [[ -n "$OPERATION" ]]; then invalid-combo; fi
			OPERATION="remove"
			shift
			;;
		--)
			shift
			break
			;;
		*)
			"Invalid option: $1 - exiting..."
			exit 1
			;;
	esac
done

# get user
USER="$(echo "$1" | rg -o '.*@')"
USER="${USER%?}" # remove trailing @
# default to root if only IP was given
if [[ -z "$USER" ]]; then USER="root"; fi

IP="$1"
PORT=6443
shift

CLUSTER=
# if no cluster name passed -> default to IP
if [[ -n "$1" ]]; then CLUSTER="$1";
else CLUSTER="$IP"; fi

FILE="$(mktemp)"

if ! scp "${user}@${IP}:~/.kube/config" "$FILE"; then
	echo "Couldn't scp ~/.kube/config from remote to local machine - exiting..."
	exit 1
fi

cert_auth_data="$(rg -o 'certificate-authority-data:\s*(\S+)' "$FILE" | awk '{ print $2 }')"
client_cert_data="$(rg -o 'client-certificate-data:\s*(\S+)' "$FILE" | awk '{ print $2 }')"
client_key_data="$(rg -o 'client-key-data:\s*(\S+)' "$FILE" | awk '{ print $2 }')"

case "$OPERATION" in
	"add")
		kubectl config set clusters."$CLUSTER".certificate-authority-data "$cert_auth_data"
		kubectl config set clusters."$CLUSTER".server "https://$IP:$PORT"
		kubectl config set users."$CLUSTER-user".client-certificate-data "$client_cert_data"
		kubectl config set users."$CLUSTER-user".client-key-data "$client_key_data"
		kubectl config set contexts."$CLUSTER-context".cluster "$CLUSTER"
		kubectl config set contexts."$CLUSTER-context".user "$CLUSTER-user"
		kubectl config use-context "$CLUSTER-context"
		;;
	"remove")
		kubectl config delete-cluster "$CLUSTER"
		kubectl config delete-context "$CLUSTER-context"
		kubectl config delete-user "$CLUSTER-user"
		kubectl config unset current-context
		;;
	*)
		echo "Invalid operation set - exiting..."
		exit 1
		;;
esac

rm "$FILE"

