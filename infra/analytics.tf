# Athena over CloudFront logs — serverless analytics with no warehouse.
# CloudFront writes gzipped TSV logs to the already-provisioned logs bucket
# under /cloudfront/. Glue Catalog tables the schema; Athena queries in
# columnar plans against S3 without ever spinning up a cluster.
#
# Query cost: $5/TB scanned. At portfolio scale (a few MB/mo), one query
# costs fractions of a cent. The pricing story is a resume line by itself.

# Query results land here. Lifecycle keeps costs bounded by expiring old
# result sets after 14 days.
resource "aws_s3_bucket" "athena_results" {
  bucket        = "${var.domain}-athena-results"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  rule {
    id     = "expire-old-results"
    status = "Enabled"
    filter {}
    expiration { days = 14 }
  }
}

resource "aws_athena_workgroup" "portfolio" {
  name        = "${replace(var.domain, ".", "-")}-analytics"
  description = "Analytics workgroup for showcase.dram-soc.org CloudFront + WAF logs"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/query-results/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    # Cap accidental large scans. Portfolio queries stay under a MB;
    # this caps a single query at 1 GB of scanned data ($0.005).
    bytes_scanned_cutoff_per_query = 1073741824
  }
}

resource "aws_glue_catalog_database" "portfolio" {
  name        = replace("${var.domain}_analytics", "-", "_")
  description = "Glue Data Catalog for CloudFront access logs (Athena-queried)."
}

# CloudFront logs are TSV, gzipped, with a hard-defined 33-column schema.
# Column names are dashes+parens in the docs — Glue Hive-style names must
# be lowercase and use underscores, so the field ordering matters far more
# than the field names.
resource "aws_glue_catalog_table" "cloudfront_logs" {
  name          = "cloudfront_logs"
  database_name = aws_glue_catalog_database.portfolio.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "skip.header.line.count" = "2"
    "EXTERNAL"               = "TRUE"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.logs.bucket}/cloudfront/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    compressed    = true

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
      parameters = {
        "field.delim"            = "\t"
        "serialization.format"   = "\t"
        "input.regex"            = ""
      }
    }

    dynamic "columns" {
      for_each = [
        { name = "log_date",                    type = "date" },
        { name = "log_time",                    type = "string" },
        { name = "location",                    type = "string" },
        { name = "bytes",                       type = "bigint" },
        { name = "request_ip",                  type = "string" },
        { name = "method",                      type = "string" },
        { name = "host",                        type = "string" },
        { name = "uri",                         type = "string" },
        { name = "status",                      type = "int" },
        { name = "referrer",                    type = "string" },
        { name = "user_agent",                  type = "string" },
        { name = "query_string",                type = "string" },
        { name = "cookie",                      type = "string" },
        { name = "result_type",                 type = "string" },
        { name = "request_id",                  type = "string" },
        { name = "host_header",                 type = "string" },
        { name = "request_protocol",            type = "string" },
        { name = "request_bytes",               type = "bigint" },
        { name = "time_taken",                  type = "float" },
        { name = "xforwarded_for",              type = "string" },
        { name = "ssl_protocol",                type = "string" },
        { name = "ssl_cipher",                  type = "string" },
        { name = "response_result_type",        type = "string" },
        { name = "http_version",                type = "string" },
        { name = "fle_status",                  type = "string" },
        { name = "fle_encrypted_fields",        type = "int" },
        { name = "c_port",                      type = "int" },
        { name = "time_to_first_byte",          type = "float" },
        { name = "x_edge_detailed_result_type", type = "string" },
        { name = "sc_content_type",             type = "string" },
        { name = "sc_content_len",              type = "bigint" },
        { name = "sc_range_start",              type = "bigint" },
        { name = "sc_range_end",                type = "bigint" },
      ]
      content {
        name = columns.value.name
        type = columns.value.type
      }
    }
  }
}

# Canonical saved queries — Athena stores them in the workgroup so anyone
# with console access sees them. `terraform apply` becomes the source of
# truth for how to query the analytics data.

resource "aws_athena_named_query" "top_pages" {
  name        = "01_top_pages_last_7_days"
  workgroup   = aws_athena_workgroup.portfolio.name
  database    = aws_glue_catalog_database.portfolio.name
  description = "Most-visited pages in the last 7 days."
  query       = <<-SQL
    SELECT uri, COUNT(*) AS hits
    FROM ${aws_glue_catalog_database.portfolio.name}.cloudfront_logs
    WHERE log_date >= current_date - interval '7' day
      AND status = 200
      AND uri NOT LIKE '/_assets/%'
      AND uri NOT LIKE '/fonts/%'
      AND uri NOT LIKE '/assets/%'
    GROUP BY uri
    ORDER BY hits DESC
    LIMIT 20;
  SQL
}

resource "aws_athena_named_query" "geo_breakdown" {
  name        = "02_geo_by_edge_location"
  workgroup   = aws_athena_workgroup.portfolio.name
  database    = aws_glue_catalog_database.portfolio.name
  description = "Requests grouped by CloudFront edge location prefix."
  query       = <<-SQL
    SELECT substring(location, 1, 3) AS edge_region, COUNT(*) AS hits
    FROM ${aws_glue_catalog_database.portfolio.name}.cloudfront_logs
    WHERE log_date >= current_date - interval '30' day
    GROUP BY substring(location, 1, 3)
    ORDER BY hits DESC;
  SQL
}

resource "aws_athena_named_query" "cache_hit_rate" {
  name        = "03_cache_hit_rate"
  workgroup   = aws_athena_workgroup.portfolio.name
  database    = aws_glue_catalog_database.portfolio.name
  description = "CloudFront cache hit vs miss ratio."
  query       = <<-SQL
    SELECT result_type, COUNT(*) AS hits,
           ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
    FROM ${aws_glue_catalog_database.portfolio.name}.cloudfront_logs
    WHERE log_date >= current_date - interval '7' day
    GROUP BY result_type
    ORDER BY hits DESC;
  SQL
}

resource "aws_athena_named_query" "referrers" {
  name        = "04_top_referrers"
  workgroup   = aws_athena_workgroup.portfolio.name
  database    = aws_glue_catalog_database.portfolio.name
  description = "External referrers driving traffic."
  query       = <<-SQL
    SELECT referrer, COUNT(*) AS hits
    FROM ${aws_glue_catalog_database.portfolio.name}.cloudfront_logs
    WHERE log_date >= current_date - interval '30' day
      AND referrer <> '-'
      AND referrer NOT LIKE '%showcase.dram-soc.org%'
    GROUP BY referrer
    ORDER BY hits DESC
    LIMIT 10;
  SQL
}

resource "aws_athena_named_query" "error_pages" {
  name        = "05_error_status_by_uri"
  workgroup   = aws_athena_workgroup.portfolio.name
  database    = aws_glue_catalog_database.portfolio.name
  description = "URIs returning 4xx or 5xx over the last 7 days."
  query       = <<-SQL
    SELECT uri, status, COUNT(*) AS hits
    FROM ${aws_glue_catalog_database.portfolio.name}.cloudfront_logs
    WHERE log_date >= current_date - interval '7' day
      AND status >= 400
    GROUP BY uri, status
    ORDER BY hits DESC
    LIMIT 25;
  SQL
}
