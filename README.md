**Installation Guide for DIGIT via GitHub Actions in AWS**

This guide provides step-by-step instructions for installing DIGIT using GitHub Actions within an AWS environment.

Prerequisites
AWS account

**Installation Steps:**

1. Prepare AWS IAM User
Create an IAM User in your AWS account.
Generate ACCESS_KEY and SECRET_KEY for the IAM user.
Assign Administrator Access to the IAM user for necessary permissions.

2. Configure GitHub Repository
Fork the Repository into your organization account on GitHub.
Navigate to the repository settings, then to Secrets and Variables, and add the following repository secrets:

AWS_ACCESS_KEY_ID: <GENERATED_ACCESS_KEY>
AWS_SECRET_ACCESS_KEY: <GENERATED_SECRET_KEY>
AWS_DEFAULT_REGION: ap-south-1
AWS_REGION: ap-south-1

3. Enable GitHub Actions
Open the GitHub Actions workflow file.
Specify the branch name you wish to enable GitHub Actions for.

4. Configure Infrastructure-as-Code
Navigate to infra-as-code/terraform/sample-aws.
Open input.yaml and enter details such as domain_name, cluster_name, bucket_name, and db_name.

5. Configure Application Secrets
Navigate to config-as-code/environments.
Open egov-demo-secrets.yaml.
Enter db_password and ssh_private_key.
Add the public_key to your GitHub account.

6. Generate SSH Key Pair
Choose one of the following methods to generate an SSH key pair:

Method a: Use an online website (Note: This is not recommended for production setups, only for demo purposes): https://8gwifi.org/sshfunctions.jsp
Method b: Use OpenSSL commands:
openssl genpkey -algorithm RSA -out private_key.pem
openssl rsa -pubout -in private_key.pem -out public_key.pem

7. Finalize Installation
After entering all the details, push these changes to the remote GitHub repository.
Open the Actions tab in your GitHub account to view the workflow. You should see that the workflow has started, and the pipelines are completing successfully.

