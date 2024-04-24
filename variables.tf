variable "root_domain" {
  description = "The root domain of your site: example.com"
  type        = string
}

variable "www_domain" {
  description = "The www domain of your site: www.example.com"
  type        = string
}

variable "s3_bucket_name" {
  description = "Unique S3 bucket to be created to host your website static content"
  type        = string
}