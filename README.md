# aws-terraform-bootstrap
A bash script that uses the AWS CLI and CloudFormation to provision an encrypted S3 bucket and DynamoDB table for storing Terraform remote state.

On successful completion, a Terraform `main.tf` file will be created that references the correct S3 bucket, DynamoDB table and AWS account id.

## Usage
```bash
USAGE: init.sh [OPTIONS]

A script that uses AWS CloudFormation to automate the setup of necessary resources for storing Terraform state in S3.

  OPTIONAL OPTIONS:
    --cf-stack-name   Name of CloudFormation stack to create or reuse
                      (default: "TerraformRemoteState")
    --tf-aws-version  The version of the AWS Provider to use in Terraform
                      (default: "2.58")
    --tf-output-file  The name of the file to save the final Terraform code in
                      (default: "main.tf")
    --tf-state-key    The name of the S3 key to store Terraform state in
                      (default: "main/state.tfstate")
    --tf-version      The version of Terraform to use
                      (default: "0.12.24")
```
