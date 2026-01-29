data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "codetest" {
  id = "vpc-05c391e12a898f0f0"
}

data "aws_subnet" "selected" {
  id = "subnet-0f353efe2777087aa"
}

#sns topic
resource "aws_sns_topic" "codetest" {
  name = "coding-test-topic"
}

resource "aws_sns_topic_subscription" "codetest" {
  topic_arn = aws_sns_topic.codetest.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

#ec2 instance - basic
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "sg" {
  name = "codetest-sg"
  vpc_id = data.aws_vpc.codetest.id

  #keep generic for now
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "codetest" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  subnet_id = data.aws_subnet.selected.id
  vpc_security_group_ids = [aws_security_group.sg.id]

  tags = {
    Name = "codetest-ec2"
  }
}

#lambda config
resource "aws_iam_role" "lambda_role" {
  name = "codetest-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    tag-key = "codetest"
  }
}

resource "aws_iam_policy" "lambda_polciy" {
  name = "codetest-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:Describe*", "ec2:RebootInstances"
        ]
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.codetest.id}"
      },
      {
        Action = [
          "sns:Publish"
        ]
        Effect   = "Allow"
        Resource = aws_sns_topic.codetest.arn
      },
      {
        Action = [
          "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },      
    ]
  })
}

#attach policy
resource "aws_iam_role_policy_attachment" "codetest" {
  role = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_polciy.arn
}

#package lambda function
data "archive_file" "codetest" {
  type        = "zip"
  source_file = "${path.module}/../lambda_function/lambda.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "codetest" {
  filename      = data.archive_file.codetest.output_path
  role          = aws_iam_role.lambda_role.arn
  handler   = "app.lambda_handler"
  function_name = "codetest-lambda"
  runtime = "python3.12"
  source_code_hash   = data.archive_file.codetest.output_base64sha256
  environment {
    variables = {
        INSTANCE_ID = aws_instance.codetest.id
        LOG_LEVEL   = "info"
        SNS_TOPIC_ARN = aws_sns_topic.codetest.arn
    }
  }
  tags = {
    environment = "codetest"
  }
}  

#set API gateway
resource "aws_apigatewayv2_api" "codetest" {
  name                       = "codetest-http"
  protocol_type              = "HTTP"
}

resource "aws_apigatewayv2_integration" "codetest" {
  api_id           = aws_apigatewayv2_api.codetest.id
  integration_type = "AWS_PROXY"
  integration_method = "ANY"
  integration_uri    = aws_lambda_function.codetest.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "codetest" {
  api_id    = aws_apigatewayv2_api.codetest.id
  route_key = "POST /sumo-alerts" #for sumo webhooks
  target = "integrations/${aws_apigatewayv2_integration.codetest.id}"
}

resource "aws_apigatewayv2_stage" "example" {
  api_id = aws_apigatewayv2_api.codetest.id
  name   = "codetest-stage"
}

#set permissions for API gateway to invoke lambda
resource "aws_lambda_permission" "api_invoke" {
statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.codetest.function_name
  principal = "apigateway.amazonaws.com"
  source_arn = aws_apigatewayv2_api.codetest.execution_arn
}

output "sumo_logic_webhook_url" {
    value = "${aws_apigatewayv2_api.codetest.api_endpoint}/sumo-alert"
}