resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db-subnet-group-${var.environment}"
  subnet_ids = "${var.subnet_ids}"

    tags = "${
    
    {
      "Name" = "db-subnet-group-${var.environment}",
      "environment" = "${var.environment}"
    }
  }"
}

resource "aws_db_instance" "rds_postgres" {
  allocated_storage       = "${var.storage_gb}"
  storage_type            = "${var.storage_type}"
  engine                  = "postgres"
  engine_version          = "${var.engine_version}"
  instance_class          = "${var.instance_class}"
  identifier              = "${var.db_name}"
  availability_zone       = "${var.availability_zone}"
  username                = "${var.administrator_login}"
  password                = "${var.administrator_login_password}"
  vpc_security_group_ids  = "${var.vpc_security_group_ids}"
  backup_retention_period = "${var.backup_retention_days}"
  db_subnet_group_name    = "${aws_db_subnet_group.db_subnet_group.name}"
  copy_tags_to_snapshot   = "true"

    tags = "${
    {
      "Name" = "${var.environment}-db",
      "environment" = "${var.environment}"
    }
  }"  
}