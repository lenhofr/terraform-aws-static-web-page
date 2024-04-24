# terraform-aws-static-website
Terraform module for hosting a static webpage via Cloudfront, Route53, and S3 with your custom domain name

#### Via the console:
1. Register a custom domain name in Route53
2. Verify your email address via email from AWS
3. Delete the hosted zone that is automatically created for you when your domain is registered

#### Via terraform

```hcl

module my_cool_website {
    call this module
}

```