variable "aws_region" {
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  type        = string
  default     = "noughts-and-crosses"
}

variable "bucket_name" {
  type        = string
  default     = ""
}

variable "price_class" {
  type        = string
  default     = "PriceClass_100"
}
