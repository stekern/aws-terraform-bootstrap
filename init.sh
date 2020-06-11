#!/usr/bin/env bash
#
# Copyright (C) 2020 Erlend Ekern <dev@ekern.me>
#
# Distributed under terms of the MIT license.

set -euo pipefail
IFS=$'\n\t'

confirm() {
  # Ask for user confirmation
  local query yn
  query="$1"
  while true; do
    read -rp "$query " yn
    case $yn in
      [yY]* ) return 0;;
      [nN]* ) return 1;;
      * ) printf "Please answer yes or no.\n";;
    esac
  done
}

check_dependencies() {
  # Verify that the required dependencies are installed
  local dependencies dependency
  dependencies=($@)
  missing_dependencies=()
  for dependency in "${dependencies[@]}"; do
    if [ -z "$(which "$dependency")" ]; then
      missing_dependencies+=("$dependency")
    fi
  done
  test "${#missing_dependencies[@]}" -gt 0 && \
    printf "The following dependencies are missing:\n" && \
    printf "%s\n" "${missing_dependencies[@]}" && \
    exit 1
  return 0
}

stack_exists() {
  local stack_name
  stack_name="$1"
  aws cloudformation describe-stacks \
    --stack-name "$stack_name" \
    > /dev/null 2>&1
}

create_stack() {
  local stack_name
  stack_name="$1"
  if stack_exists "$stack_name"; then
    printf "A CloudFormation stack with name '%s' already exists\n" "$stack_name"
  else
    printf "Creating CloudFormation stack '%s'\n" "$stack_name"
    stack_id="$(aws cloudformation create-stack \
      --stack-name "$stack_name" \
      --template-body file://cloudformation.yml \
      --query 'StackId' \
      --output text
    )"
    printf "Waiting for creation of CloudFormation stack '%s' to complete\n" "$stack_name"
    aws cloudformation wait stack-create-complete --stack-name "$stack_id"
    printf "Creation of CloudFormation stack '%s' complete\n" "$stack_name"
  fi
}

get_stack_output() {
  local stack_name output_key value
  stack_name="$1"
  output_key="$2"
  value="$(aws cloudformation describe-stacks \
    --stack-name "$stack_name" \
    --query "Stacks[*].Outputs[?OutputKey==\`$output_key\`].OutputValue" \
    --output text
  )"
  printf "%s\n" "$value"
}

usage() {
  cat <<EOF
USAGE: $(basename "$0") [OPTIONS]

A script that uses AWS CloudFormation to automate the setup of necessary resources for storing Terraform state in S3.

  OPTIONAL OPTIONS:
    --cf-stack-name   Name of CloudFormation stack to create or reuse
                      (default: "$CF_STACK_NAME")
    --tf-aws-version  The version of the AWS Provider to use in Terraform
                      (default: "$TF_AWS_VERSION")
    --tf-output-file  The name of the file to save the final Terraform code in
                      (default: "$TF_OUTPUT_FILE")
    --tf-state-key    The name of the S3 key to store Terraform state in
                      (default: "$TF_STATE_KEY")
    --tf-version      The version of Terraform to use
                      (default: "$TF_VERSION")

EOF
  exit 1
}

read_arguments() {
  TF_OUTPUT_FILE="main.tf"
  TF_STATE_KEY="main/state.tfstate"
  TF_VERSION="0.12.24"
  CF_STACK_NAME="TerraformRemoteState"
  TF_AWS_VERSION="2.58"
  while [ -n "${1:-}" ]; do
    case "$1" in
      --help           ) usage ;;
      --cf-stack-name  ) CF_STACK_NAME="${2-}" ;;
      --tf-aws-version ) TF_AWS_VERSION="${2-}" ;;
      --tf-output-file ) TF_OUTPUT_FILE="${2-}"; test -e "$TF_OUTPUT_FILE" && printf "File '%s' already exists\n" "$TF_OUTPUT_FILE" && usage ;;
      --tf-state-key ) TF_STATE_KEY="${2-}" ;;
      --tf-version     ) TF_VERSION="${2-}" ;;
      *                ) printf "Unknown argument '%s'\n\n" "$1" && usage ;;
    esac
    shift; shift
  done
  readonly TF_OUTPUT_FILE TF_STATE_KEY TF_VERSION CF_STACK_NAME TF_AWS_VERSION
}

main() {
  local stack_name stack_id table_name bucket_name
  read_arguments "$@"
  verify_dependencies "aws"
  aws_region="$(aws configure get region)"
  aws_account_id="$(aws sts get-caller-identity \
    --query 'Account' \
    --output text
  )"
  printf "Using AWS account '%s' in region '%s'\n" "$aws_account_id" "$aws_region"
  if ! confirm "Do you want to continue?"; then
    printf "Exiting\n"
    exit 1
  fi
  create_stack "$CF_STACK_NAME"
  table_name="$(get_stack_output "$CF_STACK_NAME" "NameOfTerraformTable")"
  bucket_name="$(get_stack_output "$CF_STACK_NAME" "NameOfTerraformBucket")"

  printf "Creating a file '%s' with initial terraform setup\n" "$TF_OUTPUT_FILE"

  cat <<EOF > "$TF_OUTPUT_FILE"
terraform {
  backend "s3" {
    bucket         = "$bucket_name"
    key            = "$TF_STATE_KEY"
    dynamodb_table = "$table_name"
    region         = "$aws_region"
  }
  required_version = "$TF_VERSION"
}

provider "aws" {
  version             = "$TF_AWS_VERSION"
  region              = "$aws_region"
  allowed_account_ids = ["$aws_account_id"]
}
EOF

  printf "%s\n%s\n" \
    "You can now run \`terraform init\` to verify that terraform" \
    "is able to use the remote state that has been set up"
}


main "$@"
