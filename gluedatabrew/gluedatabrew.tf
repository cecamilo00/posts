 provider "aws" {
   region = "us-east-1"
 }


resource "random_id" "random" {
  byte_length = 2
}

variable "job_name"{
    type= string
    default= "PreciosJob"
}

variable "bucket_name" {
    type = string
    default = "datosgluedatabrew"
}

variable "telefono"{
    type = string
    default = "+573005465765"
}

resource "aws_lambda_function" "lambda_function_call_step_function" {
  filename      = "lambda_function.py.zip"
  function_name = "LambdaStepFunction-${random_id.random.hex}"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.8"
  memory_size   = 128
  timeout       = 5
  environment {
    variables = {
      STEPFUNCTIONARN = aws_sfn_state_machine.function.arn
    }
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role-${random_id.random.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_execution_role_policy_attach" {
  policy_arn = "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
  role       = aws_iam_role.lambda_execution_role.name
}

resource "aws_iam_role_policy_attachment" "lambda_execution_role_cloudwatch_attach" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  role       = aws_iam_role.lambda_execution_role.name
}


resource "aws_lambda_permission" "s3_permission_to_trigger_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function_call_step_function.arn
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.bucket_name}"
}

resource "aws_s3_bucket_notification" "bucket_notification_put" {
  bucket = "${var.bucket_name}"

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda_function_call_step_function.arn
    events              = ["s3:ObjectCreated:Put"]
    filter_prefix = "procesardata/"
    filter_suffix = ".csv"
  }
  depends_on = [aws_lambda_permission.s3_permission_to_trigger_lambda]
}


resource "aws_sfn_state_machine" "function" {
  name     = "StateMachineGlueDataBrew-${random_id.random.hex}"
  role_arn = aws_iam_role.function_role.arn

  definition = <<DEFINITION
    {
  "Comment": "A description of my state machine",
  "StartAt": "Actualizar DataSet",
  "States": {
    "Actualizar DataSet": {
      "Type": "Task",
      "Parameters": {
        "Format": "CSV",
        "Input": {
          "S3InputDefinition": {
            "Bucket.$": "$.bucket",
            "BucketOwner.$": "$.cuenta",
            "Key.$": "$.carpeta"
          }
        },
        "Name": "Precios"
      },
      "Resource": "arn:aws:states:::aws-sdk:databrew:updateDataset",
      "Next": "Ejecutar Job"
    },
    "Ejecutar Job": {
      "Type": "Task",
      "Resource": "arn:aws:states:::databrew:startJobRun",
      "Parameters": {
        "Name": "${var.job_name}"
      },
      "Catch": [
        {
          "ErrorEquals": [
            "DataBrew.ConflictException"
          ],
          "Next": "SNS Error"
        }
      ],
      "Next": "SNS Job Ejecutado"
    },
    "SNS Error": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "Message": {
          "Mensaje": "Se produjo un error"
        },
        "TopicArn": "${aws_sns_topic.topic_glue_databrew.arn}"
      },
      "End": true
    },
    "SNS Job Ejecutado": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "${aws_sns_topic.topic_glue_databrew.arn}",
        "Message": {
          "Mensaje": "Se ejecuto el job correctamente"
        }
      },
      "End": true
    }
  }
}
  DEFINITION
}

resource "aws_iam_role" "function_role" {
  name = "my-state-machine-role-${random_id.random.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "function_policy_role_sns" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
  role       = aws_iam_role.function_role.name
}

resource "aws_iam_role_policy_attachment" "lambda_policy_glue_data_brew" {
  policy_arn = "arn:aws:iam::aws:policy/AwsGlueDataBrewFullAccessPolicy"
  role       = aws_iam_role.function_role.name
}

resource "aws_sns_topic" "topic_glue_databrew" {
  name = "topic_glue_databrew-${random_id.random.hex}"
}

resource "aws_sns_topic_subscription" "subscription_glue_databrew" {
  topic_arn = aws_sns_topic.topic_glue_databrew.arn
  protocol  = "sms"
  endpoint  = "${var.telefono}"
}
