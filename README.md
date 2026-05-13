# ⭕ Noughts and Crosses ❌

A browser-based noughts and crosses (tic tac toe) game deployed to AWS with Terraform. The app is hosted as a static site using a private S3 bucket, CloudFront for public HTTPS delivery, and a serverless backend for storing game statistics.

Live CloudFront deployment: <https://d2mrwywexba4ua.cloudfront.net>

## Architecture

- S3 stores the static website files
- CloudFront serves the site over HTTPS
- Origin Access Control keeps the S3 bucket private
- API Gateway exposes the backend API
- Lambda handles game stats requests
- DynamoDB stores game statistics
- Terraform provisions the AWS infrastructure