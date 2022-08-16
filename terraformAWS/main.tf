# PROVIDER

provider "aws" {
    region = "${var.aws_regions[0]}"
    #Se definen los tags comunes a todos los resources
    default_tags {
        tags = {
            despliegue = "Terraform AWS"
        }
    }
}

#DATA - PARAMETERS - VARIABLES


locals {
  tags = {
    despliegue = "Terraform AWS"
  }
}
variable "amiinstance" {
    default = "ami-090fa75af13c156b4"
    type = string  
}

variable "aws_regions" {
    default = [
        "us-east-1",
        "us-east-2"
    ]
    type = list
}

variable "aws_instance_size" {
    type = map
    default= {
        small = "t2.micro",
        medium = "t2.medium",
        large = "t2.large"
    }
}

variable "aws_instancedb_size" {
    type = map
    default= {
        small = "db.t2.micro",
        medium = "db.t2.small"
    }
}

variable "tag" {
    default = "template_terraform"
    type = string
}

variable "cidr_subnets" {
    default = [
        "10.0.1.0/24",#public
        "10.0.2.0/28",#private
        "10.0.3.0/28"#private
    ]
    type = list
}

#RESOURCES

resource "aws_vpc" "vpcterraform" {
    cidr_block = "10.0.0.0/16"
    enable_dns_hostnames = true
    tags = {
        Name = "${var.tag}"
    }
}

resource "aws_internet_gateway" "igwterraform" {
    vpc_id = "${aws_vpc.vpcterraform.id}"
    tags = {
        Name = "routeTableTFPublic_${var.tag}"
    }
}

resource "aws_route_table" "routeTableTFPublic" {
    vpc_id = "${aws_vpc.vpcterraform.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.igwterraform.id}"
    }
    tags = {
        Name = "routeTableTFPublic_${var.tag}"
    }
}

resource "aws_route_table" "routeTablerivate" {
    vpc_id = "${aws_vpc.vpcterraform.id}"
    tags = {
        Name = "routeTableTFPrivate_${var.tag}"
    }
    
}

resource "aws_subnet" "publicsubnet1" {
    vpc_id = "${aws_vpc.vpcterraform.id}"
    cidr_block = var.cidr_subnets[0]
    map_public_ip_on_launch = true
    availability_zone = "us-east-1a"
    tags = {
        Name = "publicsubnet1_${var.tag}"
    }
}

resource "aws_route_table_association" "routeTableAssociationTF" {
    subnet_id = "${aws_subnet.publicsubnet1.id}"
    route_table_id = "${aws_route_table.routeTableTFPublic.id}"
}

resource "aws_subnet" "privatesubnet1" {
    vpc_id = "${aws_vpc.vpcterraform.id}"
    cidr_block = var.cidr_subnets[1]
    availability_zone = "us-east-1b"
    tags = {
        Name = "privatesubnet1_${var.tag}"
    }
}

resource "aws_subnet" "privatesubnet2" {
    vpc_id = "${aws_vpc.vpcterraform.id}"
    cidr_block = var.cidr_subnets[2]
    availability_zone = "us-east-1c"
    tags = {
        Name = "privatesubnet2_${var.tag}"
    }
}

resource "aws_db_subnet_group" "dbprivatesubnetgroup"{
    name = "dbprivatesubnetgroup"
    subnet_ids = ["${aws_subnet.privatesubnet1.id}","${aws_subnet.privatesubnet2.id}"]
    tags = {
        Name = "dbprivatesubnetgroup_${var.tag}"
    }
}

resource "aws_iam_role" "instance_role" {
    assume_role_policy = jsonencode({
        "Version": "2012-10-17",
        "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sts:AssumeRole"
            ],
            "Principal": {
                "Service": [
                    "ec2.amazonaws.com"
                ]
            }
        }
        ]
    })

    tags = {
        tag-key = "role_${var.tag}"
    }
}

resource "aws_iam_policy" "policy"{
    policy = jsonencode({
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "cloudwatch:PutMetricData",
                    "ds:CreateComputer",
                    "ds:DescribeDirectories",
                    "ec2:DescribeInstanceStatus",
                    "logs:*",
                    "ssm:*",
                    "ec2messages:*"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": "iam:CreateServiceLinkedRole",
                "Resource": "arn:aws:iam::*:role/aws-service-role/ssm.amazonaws.com/AWSServiceRoleForAmazonSSM*",
                "Condition": {
                    "StringLike": {
                        "iam:AWSServiceName": "ssm.amazonaws.com"
                    }
                }
            },
            {
                "Effect": "Allow",
                "Action": [
                    "iam:DeleteServiceLinkedRole",
                    "iam:GetServiceLinkedRoleDeletionStatus"
                ],
                "Resource": "arn:aws:iam::*:role/aws-service-role/ssm.amazonaws.com/AWSServiceRoleForAmazonSSM*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "ssmmessages:CreateControlChannel",
                    "ssmmessages:CreateDataChannel",
                    "ssmmessages:OpenControlChannel",
                    "ssmmessages:OpenDataChannel"
                ],
                "Resource": "*"
            }
        ]
    })
    tags = {
        tag-key = "policy_${var.tag}"
    }
}

resource "aws_iam_role_policy_attachment" "policy_attachment" {
    role = "${aws_iam_role.instance_role.name}"
    policy_arn = "${aws_iam_policy.policy.arn}"
}

resource "aws_iam_instance_profile" "instance_profile" {
    role  = "${aws_iam_role.instance_role.name}"
}

resource "aws_security_group" "sg_instance" {
    vpc_id = "${aws_vpc.vpcterraform.id}"
    ingress {
        from_port = 22
        to_port = 22
        protocol ="tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    tags = {
        Name = "sg_instance_${var.tag}"
    }
}

resource "aws_instance" "instancia" {
    ami= "${var.amiinstance}"
    instance_type = "${var.aws_instance_size.small}"
    subnet_id = "${aws_subnet.publicsubnet1.id}"
    vpc_security_group_ids = [ "${aws_security_group.sg_instance.id}" ]
    tags = {
        Name = "instancia_${var.tag}"
    }
    iam_instance_profile = "${aws_iam_instance_profile.instance_profile.id}"
    depends_on = [aws_internet_gateway.igwterraform]
    user_data = <<EOF
    #!/bin/bash
    yum update -y
    yum install httpd -y
    service httpd start
    chkconfig httpd on
    cd /var/www/html
    echo "<html><body><h1>Terraform Instancia: $(hostname -f)</h1></body></html>" > index.html
    EOF

}

resource "aws_security_group" "sgbd" {
    name = "sg"
    vpc_id = "${aws_vpc.vpcterraform.id}"
    ingress {
        from_port = 3306
        to_port = 3306
        protocol ="tcp"
        cidr_blocks = ["${aws_instance.instancia.private_ip}/32"]
    }
    tags = {
        Name = "sgbd_${var.tag}"
    }
}

resource "aws_db_instance" "dbinstance" {
    db_subnet_group_name = "${aws_db_subnet_group.dbprivatesubnetgroup.name}"
    engine = "mysql"
    db_name = "dbterraform"
    engine_version = "5.7.28"
    instance_class = "${var.aws_instancedb_size.small}"
    username = "admin"
    password = "admin12345678"
    allocated_storage = 10
    skip_final_snapshot = true
    vpc_security_group_ids =  [ "${aws_security_group.sgbd.id}" ]
    tags = {
        Name = "dbinstance_${var.tag}"
    }
}

output "endpoint" {
    value = "${aws_instance.instancia.public_ip}"
}
