locals {
  content_types = {
    ".css" : "text/css",
    ".html" : "text/html",
    ".ico" : "image/vnd.microsoft.icon"
    ".jpeg" : "image/jpeg"
    ".jpg" : "image/jpeg"
    ".js" : "text/javascript"
    ".mp4" : "video/mp4"
    ".png" : "image/png"
    ".svg" : "image/svg+xml"
    ".wasm" : "application/wasm"
    ".zip" : "application/zip"
  }
}

resource "aws_s3_object" "website_files" {
  for_each = fileset("../website-content/", "**")
  bucket = aws_s3_bucket.main.id
  key = each.value
  source = "../website-content/${each.value}"
  content_type = lookup(local.content_types, regex("\\.[^.]+$", each.value), null)
  etag = filemd5("../website-content/${each.value}")
}