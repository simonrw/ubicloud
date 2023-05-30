# Deploy Ubicloud with MRSK
1. Create application and database virtual machines
2. Create `config/deploy.yml` based on following example. Change app and db host IP addresses. Use IPv4 for them.
```yaml
# Name of your application. Used to uniquely configure containers.
service: ubicloud

# Name of the container image.
image: ubicloud/mrsk-deployments

# Deploy to these servers.
servers:
  web:
    - <APP_VM_1_IP>
    - <APP_VM_2_IP>

# Credentials for your image host.
registry:
  username: ubicloud
  password:
    - MRSK_REGISTRY_PASSWORD

# Inject ENV variables into containers (secrets come from .env).
env:
  clear:
    RACK_ENV: production
    MAIL_DRIVER: logger
    MAIL_FROM: "dev@example.com"
  secret:
    - CLOVER_SESSION_SECRET
    - CLOVER_DATABASE_URL
    - CLOVER_COLUMN_ENCRYPTION_KEY

# Use a different ssh user than root
ssh:
  user: ubi

# Use accessory services (secrets come from .env).
accessories:
  postgres:
    image: postgres:15.2
    host: - <DB_VM_IP>
    port: 5432
    env:
      secret:
        - POSTGRES_DB
        - POSTGRES_PASSWORD
    directories:
      - postgres:/var/lib/postgresql/data
    files:
      - ./demo/init_db.sh:/docker-entrypoint-initdb.d/init_db.sh
```
3. Create `.env` file at root, and put correct values
```
MRSK_REGISTRY_PASSWORD=<REGISTIRY_PASSWORD>
CLOVER_SESSION_SECRET=<SESSION_SECRET>
CLOVER_DATABASE_URL="postgres://<DB_VM_IP>/clover?user=clover&password=<PG_PASSWORD>"
CLOVER_COLUMN_ENCRYPTION_KEY="<ENCRYPTION_KEY>"
POSTGRES_DB=clover
POSTGRES_PASSWORD="<PG_PASSWORD>"
```
4. Connect virtual machines via SSH and install docker
```bash
sudo apt update
sudo apt install -y docker.io curl git
sudo usermod -a -G docker ubi
```
5. Run MRSK setup `mrsk setup`
6. App containers can't run because migrations aren't applied yet. Run migrations. `mrsk app exec --primary "rake prod_up"`
7. Deploy again `mrsk deploy`
8. Check containers are running `mrsk details`
9. Visit app vm IP addresses
10. You can put a load balancer in front of them
