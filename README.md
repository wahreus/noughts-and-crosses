# ⭕ Noughts and Crosses ❌

A browser-based noughts and crosses (tic tac toe) game deployed to AWS with Terraform. The app is hosted as a static website using a private S3 bucket, CloudFront for public HTTPS delivery, and a serverless backend for storing game statistics.

Live deployment: <https://d2mrwywexba4ua.cloudfront.net>

<p align="center">
  <img src="figures/noughts-and-crosses-screenshot.png" alt="Screenshot of live noughts and crosses deployment.">
  <br>
  <em>Figure 1: Screenshot of live deployment.</em>
</p>

## Architecture

- Amazon S3 stores the static website files
- Amazon CloudFront serves the site over HTTPS
- CloudFront Origin Access Control keeps the S3 bucket private
- Amazon API Gateway exposes the backend API
- AWS Lambda handles game statistics requests
- Amazon DynamoDB stores game statistics
- Terraform provisions the AWS infrastructure

<p align="center">
  <img src="figures/noughts-and-crosses-diagram.svg" alt="Architecture diagram showing CloudFront, S3, API Gateway, Lambda, and DynamoDB.">
  <br>
  <em>Figure 2: Architecture diagram.</em>
</p>