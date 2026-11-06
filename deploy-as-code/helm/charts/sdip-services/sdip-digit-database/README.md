# SDIP DIGIT Database

This chart is disabled by default.

Target CloudNativePG Cluster: sdip-postgresql
DIGIT database: sdip_digit

Roles:
- sdip_digit_migrator: migration and database owner
- sdip_digit_app: runtime account

Required external Secrets in namespace sdip:
- sdip-digit-db-migrator-auth
- sdip-digit-db-app-auth

Each Secret must use type kubernetes.io/basic-auth
with username and password fields.

Also provision the legacy DIGIT User Secret named db
with these keys:
- username
- password
- flyway-username
- flyway-password

Ensure these values correspond to the correct roles.

This chart does not create any credentials or passwords.

Important:
- Verify the CNPG CRDs exist before deployment.
- Provision the role Secrets before enabling the chart.
- DatabaseRole reconciliation must complete before Database.
- Flyway migrations must be verified before startup.
- Configure grants and default privileges for sdip_digit_app.
- Do not connect DIGIT services to sdip_core.
- Do not deploy until database backups are configured.

Database and role reclaim policies are set to retain.
