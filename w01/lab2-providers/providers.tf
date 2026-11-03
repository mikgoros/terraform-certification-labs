provider "aws" {
  region = "eu-west-1"
}

provider "aws" {
  alias  = "useast"
  region = "us-east-1"
}
