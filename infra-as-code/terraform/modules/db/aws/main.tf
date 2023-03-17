resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db-subnet-group-${var.environment}"
  subnet_ids = "${var.subnet_ids}"

    tags = "${
    tomap({
      "Name" = "db-subnet-group-${var.environment}",
      "environment" = "${var.environment}"
    })
  }"
}

resource "aws_db_instance" "rds_postgres" {
  allocated_storage       = "${var.storage_gb}"
  storage_type            = "${var.storage_type}"
  engine                  = "postgres"
  db_name                 = "${var.db_name}"
  engine_version          = "${var.engine_version}"
  instance_class          = "${var.instance_class}"
  identifier              = "${var.identifier}"
  availability_zone       = "${var.availability_zone}"
  username                = "${var.administrator_login}"
  password                = "${var.administrator_login_password}"
  vpc_security_group_ids  = "${var.vpc_security_group_ids}"
  backup_retention_period = "${var.backup_retention_days}"
  db_subnet_group_name    = "${aws_db_subnet_group.db_subnet_group.name}"
  copy_tags_to_snapshot   = "true"
  skip_final_snapshot     = "true"

    tags = "${
    tomap({
      "Name" =  "${var.environment}-db",
      "environment" = "${var.environment}"
    })
  }"  
}

