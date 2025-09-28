#! /bin/bash
# This script is intended to run on a new ubuntu instance to set it up 
# Sets up an edge-endpoint environment.
# It is tested in the CICD pipeline to install the edge-endpoint on a new 
# g4dn.xlarge EC2 instance with Ubuntu 22.04LTS.

# As a user-data script on ubuntu, this file probably lands at
# /var/lib/cloud/instance/user-data.txt
echo "Setting up IntelliOptics Edge Endpoint.  Follow along at /var/log/cloud-init-output.log" > /etc/motd

echo "Starting cloud init.  Uptime: $(uptime)"

# Set up signals about the status of the installation
mkdir -p /opt/intellioptics/ee-install-status
touch /opt/intellioptics/ee-install-status/installing
SETUP_COMPLETE=0
record_result() {
    if [ "$SETUP_COMPLETE" -eq 0 ]; then
        echo "Setup failed at $(date)"
        touch /opt/intellioptics/ee-install-status/failed
        echo "IntelliOptics Edge Endpoint setup FAILED.  See /var/log/cloud-init-output.log for details." > /etc/motd
    else
        echo "Setup complete at $(date)"
        echo "IntelliOptics Edge Endpoint setup complete.  See /var/log/cloud-init-output.log for details." > /etc/motd
        touch /opt/intellioptics/ee-install-status/success
    fi
    # Remove "installing" at the end to avoid a race where there is no status
    rm -f /opt/intellioptics/ee-install-status/installing
}
trap record_result EXIT

set -e  # Exit on error of any command.

wait_for_apt_lock() {
    # We wait for any apt or dpkg processes to finish to avoid lock collisions
    # Unattended-upgrades can hold the lock and cause the install to fail
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        echo "Another apt/dpkg process is running. Waiting for it to finish..."
        sleep 5
    done
}

# Install basic tools
wait_for_apt_lock
sudo apt update
wait_for_apt_lock
sudo apt install -y \
    git \
    vim \
    tmux \
    make \
    htop \
    curl \
    wget \
    tree \
    bash-completion \
    ffmpeg

# Download the edge-endpoint code
CODE_BASE=/opt/intellioptics/src/
mkdir -p ${CODE_BASE}
cd ${CODE_BASE}
git clone https://github.com/IntelliOptics/IntelliOptics-Edge
cd IntelliOptics-Edge/
# The launching script should update this to a specific commit.
SPECIFIC_COMMIT="__EE_COMMIT_HASH__"
if [ -n "$SPECIFIC_COMMIT" ]; then
    # See if the string got substituted.  Note can't compare to the whole thing
    # because that would be substituted too!
    if [ "${SPECIFIC_COMMIT:0:11}" != "__EE_COMMIT" ]; then
        echo "Checking out commit ${SPECIFIC_COMMIT}"
        # This is probably a merge commit, so we need to fetch it deliberately.
        git fetch origin $SPECIFIC_COMMIT
        git checkout $SPECIFIC_COMMIT
        EE_IMAGE_TAG="__EEIMAGETAG__"
        if [ "${EE_IMAGE_TAG:0:12}" != "__EEIMAGETAG" ]; then
            echo "Using image tag ${EE_IMAGE_TAG}"
        else
            echo "ERROR: EEIMAGETAG was not substituted.  Required for specific commit."
            exit 1
        fi
    else
        echo "It appears the commit hash was not substituted.  Staying on main."
        EE_IMAGE_TAG="release"
    fi
else
    echo "A blank commit hash was provided.  Staying on main."
    EE_IMAGE_TAG="release"
fi

# Set up k3s with GPU support
./deploy/bin/install-k3s.sh gpu

# Set up some shell niceties
TARGET_USER="ubuntu"
echo "alias k='kubectl'" >> /home/${TARGET_USER}/.bashrc
echo "source <(kubectl completion bash)" >> /home/${TARGET_USER}/.bashrc
echo "complete -F __start_kubectl k" >> /home/${TARGET_USER}/.bashrc
echo "set -o vi" >> /home/${TARGET_USER}/.bashrc
echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /home/${TARGET_USER}/.bashrc
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# This should get substituted by the launching script
export INTELLIOPTICS_API_TOKEN="__INTELLIOPTICSAPITOKEN__"

# Install the edge-endpoint using helm
make helm-install HELM_ARGS="--set intelliopticsApiToken=${INTELLIOPTICS_API_TOKEN} --set imageTag=${EE_IMAGE_TAG}"

# Configure kubectl to use the namespace where the EE is installed
kubectl config set-context intellioptics-edge --namespace=intellioptics-edge --cluster=default --user=default
kubectl config use-context intellioptics-edge

# Indicate that setup is complete
SETUP_COMPLETE=1
echo "EE is installed into kubernetes, which will attempt to finish the setup."
