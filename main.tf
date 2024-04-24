locals {
    root_domain_name = var.root_domain
    www_domain_name = var.www_domain
    website_content_bucket = var.s3_bucket_name
}


resource "aws_route53domains_registered_domain" "oldcrestviewhills_net" {

  domain_name = local.root_domain_name

  dynamic "name_server" {
    for_each = aws_route53_zone.zone.name_servers
    content {
        name = name_server.value
    }
  }
}

resource "aws_route53_zone" "zone" {
  name = local.root_domain_name
}

resource "aws_s3_bucket" "main" {
  bucket = local.website_content_bucket
}

resource "aws_s3_bucket_policy" "default" {
  bucket = aws_s3_bucket.main.id
  policy = data.aws_iam_policy_document.cloudfront_oac_access.json
}

data "aws_iam_policy_document" "cloudfront_oac_access" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      aws_s3_bucket.main.arn,
      "${aws_s3_bucket.main.arn}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.s3_distribution.arn]
    }
  }
}

resource "aws_cloudfront_origin_access_control" "main" {
  name                              = "s3-cloudfront-oac"
  description                       = "Grant cloudfront access to s3 bucket ${aws_s3_bucket.main.id}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

locals {
  s3_origin_id = "s3origin" # should change this in the future to something meaningful
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.main.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
    origin_id                = local.s3_origin_id
  }

  enabled             = true
  default_root_object = "index.html"
  comment             = local.root_domain_name

  #   Optional - Extra CNAMEs (alternate domain names), if any, for this distribution
  aliases             = [local.root_domain_name, local.www_domain_name]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = true

      cookies {
        forward = "none"
      }
    }

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.drop_html_ext.arn
    }

    #viewer_protocol_policy = "allow-all"
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.certificate.arn
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# This already exists in this cloudfront instance from previous website. No need to re-create I guess
# TODO make this name dynamic
resource "aws_cloudfront_function" "drop_html_ext" {
  name    = "DropHTMLExt${local.root_domain_name}"
  runtime = "cloudfront-js-2.0"
  comment = "Using this to drop the HTML extension"
  publish = true
  code    = file("${path.module}/../scripts/function.js")
}

resource "aws_acm_certificate" "certificate" {
  // We want a wildcard cert so we can host subdomains later.
  domain_name       = "*.${local.root_domain_name}"
  validation_method = "DNS"

  // We also want the cert to be valid for the root domain even though we'll be
  // redirecting to the www. domain immediately.
  subject_alternative_names = [local.www_domain_name, local.root_domain_name]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.certificate.arn
  validation_record_fqdns = [for record in aws_route53_record.www : record.fqdn]
}


resource "aws_route53_record" "www" {
  for_each = {
    for dvo in aws_acm_certificate.certificate.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.zone.zone_id

}


# Root domain A record
resource "aws_route53_record" "a_root" {
  zone_id = aws_route53_zone.zone.zone_id
  name    = local.root_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# WWW A Record routing to root domain A record
resource "aws_route53_record" "a_www" {
  zone_id = aws_route53_zone.zone.zone_id
  name    = local.www_domain_name
  type    = "A"

  alias {
    name                   = aws_route53_record.a_root.name
    zone_id                = aws_route53_zone.zone.zone_id
    evaluate_target_health = false
  }
}

