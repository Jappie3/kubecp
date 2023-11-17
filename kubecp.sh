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


is_installed() {
	if ! command -v "$1" &> /dev/null; then
		echo "Error: $1 was not found, is it installed?"
		exit 1
	fi
}

is_installed "scp"
is_installed "rg"
is_installed "awk"
is_installed "kubectl"


OPTIONS=$(getopt -o arh --long add,remove,help -n "$0" -- "$@")
eval set -- "$OPTIONS"

OPERATION=

# make sure an argument was passed
if [[ $# -lt 2 ]]; then
	echo -e "Error: please provide at least one argument\nUse --help for a list of options & arguments."
	exit 1
fi

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

# make sure an argument was passed after filtering out the options (user@ip)
if [[ ${1:-} == "" ]]; then
	echo -e "Error: no argument was passed\nUse --help for a list of options & arguments."	
fi

USER=
IP=
PORT=6443

# remove @ and everything after it
# no user present -> user is set to $1
USER="${1%%@*}"

if [[ "$USER" == "$1" ]]; then
	# user isn't set (only an IP was passed), default to root & set IP
	USER="root"
	IP="$1"
	shift
else
	# user is set, get IP
	# remove @ and everything before it
	IP="${1#*@}"
	shift
fi

CLUSTER=
# if no cluster name passed -> default to IP
if [[ -n "$1" ]]; then CLUSTER="$1";
else CLUSTER="$IP"; fi

FILE="$(mktemp)"

# check default location for K3s
if scp "${USER}@${IP}:~/.kube/config" "$FILE" &> /dev/null; then
	echo "Found config!"

	cert_auth_data="$(rg -o 'certificate-authority-data:\s*(\S+)' "$FILE" | awk '{ print $2 }')"
	client_cert_data="$(rg -o 'client-certificate-data:\s*(\S+)' "$FILE" | awk '{ print $2 }')"
	client_key_data="$(rg -o 'client-key-data:\s*(\S+)' "$FILE" | awk '{ print $2 }')"

# check default location for K8s on NixOS
elif scp "${USER}@${IP}:/etc/kubernetes/cluster-admin.kubeconfig" "$FILE" &> /dev/null; then
	echo "Found config!"

	cert_auth_file=$(mktemp)
	scp "${USER}@${IP}:$(jq -r '.clusters[0].cluster."certificate-authority"' $FILE)" $cert_auth_file
	cert_auth_data=$(cat $cert_auth_file | base64)

	client_cert_file=$(mktemp)
	scp "${USER}@${IP}:$(jq -r '.users[0].user."client-certificate"' $FILE)" $client_cert_file
	client_cert_data=$(cat $client_cert_file | base64)

	client_key_file=$(mktemp)
	scp "${USER}@${IP}:$(jq -r '.users[0].user."client-key"' $FILE)" $client_key_file
	client_key_data=$(cat $client_key_file | base64)

	rm $cert_auth_file $client_cert_file $client_key_file

else
	echo "Couldn't find kubeconfig on the remote machine - exiting..."
	exit 1
fi

# check if all variables are set & return a vague error if one isn't set
if [[ ${CLUSTER:-} == "" || ${IP:-} == "" || ${PORT:-} == "" || ${cert_auth_data:-} == "" || ${client_cert_data:-} == "" || ${client_key_data:-} == "" ]]; then
	echo -e "Error: one of the variables was unset or set to null.\nUse --help for a list of options & arguments."
	exit 1
fi

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

