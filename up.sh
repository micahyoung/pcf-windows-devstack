#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

if ! [ -d state ]; then
  exit "No State, exiting"
  exit 1
fi

source ./state/env.sh
: ${PIVNET_API_TOKEN:?"!"}
: ${OPSMAN_FQDN:?"!"}
: ${OPSMAN_USERNAME:?"!"}
: ${OPSMAN_PASSWORD:?"!"}
: ${CONCOURSE_URL:?"!"}
PAS_PRODUCT_NAME=p-windows-runtime
PAS_VERSION=2.0.1
PAS_GLOB="p-windows-runtime-*.pivotal"
PAS_STEMCELL_PRODUCT_NAME=stemcells-windows-server-internal
PAS_STEMCELL_GLOB='bosh-stemcell-*-vsphere-esxi-windows2012R2-go_agent.tgz' 
PAS_STEMCELL_VERSION=3445.19
PAS_MAJOR_MINOR_VERSION='2\.[0-9\]+\.[0-9]+$'
PCF_PIPELINES_VERSION=v0.23.0

set -x

mkdir -p bin
PATH=$PATH:$(pwd)/bin

if ! [ -f bin/pivnet ]; then
  curl -L "https://github.com/pivotal-cf/pivnet-cli/releases/download/v0.0.49/pivnet-linux-amd64-0.0.49" > bin/pivnet
  chmod +x bin/pivnet
fi

if ! [ -f bin/yaml-patch ]; then
  curl -L "https://github.com/krishicks/yaml-patch/releases/download/v0.0.10/yaml_patch_linux" > bin/yaml-patch
  chmod +x bin/yaml-patch
fi

if ! [ -f bin/fly ]; then
  curl -L "$CONCOURSE_URL/api/v1/cli?arch=amd64&platform=linux" > bin/fly
  chmod +x bin/fly
fi

bin/pivnet login --api-token=$PIVNET_API_TOKEN

if ! [ -d bin/pcf-pipelines ]; then
  bin/pivnet \
    download-product-files \
    --product-slug=pcf-automation \
    --release-version=$PCF_PIPELINES_VERSION \
    --glob=pcf-pipelines-*.tgz \
    --download-dir=bin/ \
    --accept-eula \
  ;

  tar -xf bin/pcf-pipelines-*.tgz -C bin/
  rm bin/pcf-pipelines-*.tgz
fi

IAAS_TYPE=openstack
cat > state/upgrade-tile-params.yml <<EOF
# Resource
# ------------------------------
# The token used to download the product file from Pivotal Network. Find this
# on your Pivotal Network profile page:
# https://network.pivotal.io/users/dashboard/edit-profile
pivnet_token: $PIVNET_API_TOKEN
# The minor product version to track, as a regexp. To track 1.11.x of a product, this would be "^1\.11\..*$", as shown below.
product_version_regex: $PAS_MAJOR_MINOR_VERSION

# Operations Manager
# ------------------------------
# Credentials for Operations Manager. These are used for uploading, staging,
# and deploying the product file on Operations Manager.
# Either opsman_client_id/opsman_client_secret or opsman_admin_username/opsman_admin_password needs to be specified. 
# If you are using opsman_admin_username/opsman_admin_password, edit opsman_client_id/opsman_client_secret to be an empty value.
# If you are using opsman_client_id/opsman_client_secret, edit opsman_admin_username/opsman_admin_password to be an empty value. 
opsman_client_id:
opsman_client_secret:
opsman_admin_username: $OPSMAN_USERNAME
opsman_admin_password: $OPSMAN_PASSWORD
opsman_domain_or_ip_address: $OPSMAN_FQDN

# The IaaS name for which stemcell to download. This must match the IaaS name
# within the stemcell to download, e.g. "vsphere", "aws", "azure", "google" must be lowercase.
iaas_type: $IAAS_TYPE

# om-linux
# ------------------------------
# The name of the product on Pivotal Network. This is used to configure the
# resource that will fetch the product file.
#
# This can be found in the URL of the product page, e.g. for rabbitmq the URL
# is https://network.pivotal.io/products/pivotal-rabbitmq-service, and the
# product slug is 'pivotal-rabbitmq-service'.
product_slug: $PAS_PRODUCT_NAME
# The globs regular expression for the PivNet resource to download the product
# release files. "*pivotal" is the default.
# For products such as ERT, it is recommended to use "cf*pivotal" to avoid the
# extra download of the SRT file in PCF 1.12.*
product_globs: $PAS_GLOB

git_private_key:
EOF

PATCHED_PIPELINE=$(
  yaml-patch \
    < bin/pcf-pipelines/upgrade-tile/pipeline.yml
)

fly --target c login --concourse-url $CONCOURSE_URL

PIPELINE_NAME=upgrade-tile
fly --target c set-pipeline \
  --pipeline $PIPELINE_NAME \
  --config <(echo "$PATCHED_PIPELINE") \
  --load-vars-from state/upgrade-tile-params.yml \
  --non-interactive \
  ;

fly --target c unpause-pipeline --pipeline $PIPELINE_NAME
