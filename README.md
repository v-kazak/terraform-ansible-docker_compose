# Terraform + Ansible + Docker для Yandex Cloud

Проект разворачивает в Yandex Cloud готовый стенд из нескольких web-нод и отдельного monitoring-хоста. Terraform поднимает инфраструктуру и генерирует Ansible inventory, Ansible настраивает серверы и устанавливает Docker, а затем запускает контейнеры приложения, мониторинга и логирования (ELK) через Docker Compose v2.

После деплоя вы получаете:

- сетевую инфраструктуру в Yandex Cloud: VPC, подсеть и security groups;
- группу web-серверов за `Network Load Balancer`;
- отдельный `monitoring-server`;
- тестовое web-приложение на `nginx`, которое показывает имя ноды, обработавшей запрос;
- `node-exporter` на web-нодах и на monitoring-хосте;
- `Prometheus` и `Grafana` на отдельном monitoring-хосте;
- стек `ELK` (`Elasticsearch`, `Logstash`, `Kibana` и `Filebeat`) на отдельном monitoring-хосте;
- автоматически сгенерированный `ansible/inventory.ini`.

## Архитектура

```text
Интернет
   |
   v
Yandex Network Load Balancer :80
   |
   +--> web-0 (nginx + node-exporter)
   +--> web-1 (nginx + node-exporter)
   +--> ...

monitoring-server
   +--> Prometheus
   +--> Grafana
   +--> node-exporter
   +--> Elasticsearch
   +--> Logstash
   +--> Kibana
   +--> Filebeat
```

Что происходит при развертывании:

1. Terraform создаёт `vps_count` web-нод, отдельную monitoring-ВМ, сеть, подсеть и балансировщик.
2. Terraform формирует `ansible/inventory.ini` с внешними и внутренними IP-адресами.
3. Ansible ждёт доступности SSH, устанавливает Docker Engine и `docker compose` plugin.
4. Ansible создаёт пользователей `deploy` и `monitoring`, добавляет SSH-ключ и отключает вход по паролю.
5. На web-нодах запускаются `nginx` и `node-exporter`.
6. На monitoring-хосте запускаются `Prometheus`, `Grafana` и `node-exporter`.
7. `Prometheus` собирает метрики с monitoring-хоста и всех web-нод по внутренним адресам.
8. На monitoring-хосте запускается `ELK`-стек. При запуске Ansible автоматически генерирует `Service Account Token` для Kibana, формирует `.env` файл конфигурации и поднимает сервисы. `Filebeat` собирает логи Docker-контейнеров и системные логи, передавая их в `Logstash` и далее в `Elasticsearch`.

## Что создаёт проект

### Terraform

- `terraform/main.tf`
  Создаёт web-ВМ, VPC, подсеть, target group, балансировщик и Ansible inventory.
- `terraform/monitoring.tf`
  Создаёт отдельную monitoring-ВМ и security groups (с открытыми портами для SSH, Grafana, Kibana).
- `terraform/local.tf`
  Описывает набор публично доступных портов для web-нод.
- `terraform/outputs.tf`
  Возвращает IP балансировщика, IP web-нод и текстовую сводку после деплоя.

### Ansible

- `ansible/playbook.yml`
  Общий сценарий подготовки всех хостов и раздельного деплоя ролей.
- `ansible/roles/install_docker`
  Устанавливает Docker Engine, Compose plugin и зависимости.
- `ansible/roles/create_user`
  Создаёт системных пользователей, настраивает `authorized_keys` и отключает `PasswordAuthentication`.
- `ansible/roles/copy_app_files` и `ansible/roles/run_container_app`
  Кладут шаблон страницы, `nginx.conf`, `compose.yml` и запускают web-стек.
- `ansible/roles/copy_monitoring_files` и `ansible/roles/run_container_monitoring`
  Подготавливают конфиги Prometheus/Grafana и запускают monitoring-стек.
- `ansible/roles/copy_elk_files` и `ansible/roles/run_container_elk`
  Копируют конфигурационные файлы ELK-стека, автоматически генерируют токены аутентификации для Kibana и поднимают Docker Compose конфигурацию.

## Требования

- аккаунт Yandex Cloud с доступом к `cloud_id` и `folder_id`;
- Terraform `>= 0.13`;
- Ansible;
- `make`;
- SSH-ключ, доступный локально, по умолчанию `~/.ssh/id_ed25519` и `~/.ssh/id_ed25519.pub`;
- Ansible collections:

```bash
ansible-galaxy collection install community.docker ansible.posix
```

`yc` CLI не обязателен для работы проекта, но удобен для получения OAuth-токена.

## Настройка

### 1. Секреты Terraform

Создайте файл `terraform/secret.auto.tfvars`:

```hcl
token     = "your_yandex_oauth_token"
cloud_id  = "your_cloud_id"
folder_id = "your_folder_id"
```

### 2. Переопределение переменных инфраструктуры

При необходимости создайте `terraform/terraform.tfvars` и измените параметры стенда:

```hcl
vps_count     = 2
name          = "web-server"
zone          = "ru-central1-d"
blns_zone     = "ru-central1"
platform_type = "standard-v3"
cores_count   = 2
memory_count  = 2
core_fraction = 20
disc_size     = 15
disc_type     = "network-hdd"
image_id      = "fd8e9t6fpgi13oh7q39f"
preemptible   = true

ssh_user            = "superuser"
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
nat                 = true
```

По умолчанию:

- web-ноды создаются в количестве `2`;
- все ВМ прерываемые (`preemptible = true`);
- для web-нод открыты `22`, `80`, `443`;
- порт `9100` у web-нод доступен только из внутренней сети;
- у monitoring-хоста публично доступны `22`, `3000` (Grafana) и `5601` (Kibana).

### 3. Настройка Grafana

Файл `ansible/roles/run_container_monitoring/files/.env` содержит переменные для Grafana:

```env
SERVER_DOMAIN=http://localhost:3000
SERVER_ROOT_URL=http://localhost:3000
GRAFANA_PASSWORD=admin
```

Для демонстрации этого достаточно, но для реального использования лучше заранее поменять пароль администратора. Если хотите, чтобы Grafana использовала корректный внешний URL, обновите `SERVER_ROOT_URL` и затем повторно выполните `make ansible`.

### 4. Настройка ELK-стека

По умолчанию Kibana и Elasticsearch используют статический пароль, прописанный в `ansible/roles/run_container_elk/templates/.env.j2`. Для production среды настоятельно рекомендуется его изменить.

## Запуск

### Полное развертывание

```bash
make start
```

Команда выполняет:

1. `terraform init`
2. `terraform fmt`
3. `terraform validate`
4. `terraform apply`
5. запуск `ansible-playbook`
6. вывод итоговой сводки с адресами

### Только инфраструктура

```bash
make terraform
```

### Повторный прогон конфигурации Ansible

```bash
make ansible
```

Полезно, если:

- вы поменяли шаблоны или compose-файлы;
- вы изменили настройки Grafana или ELK;
- инфраструктура уже создана, и нужно только заново применить конфигурацию.

## Доступ после деплоя

### Web-приложение

Откройте адрес балансировщика:

```bash
terraform -chdir=terraform output -raw load_balancer_public_ip
```

или краткую сводку:

```bash
terraform -chdir=terraform output -raw summary
```

Страница покажет имя узла, который ответил на запрос. Это удобно для проверки балансировки.

### Grafana

Получите IP monitoring-хоста:

```bash
terraform -chdir=terraform output -raw monitoring_public_ip
```

Далее откройте:

```text
http://<monitoring_public_ip>:3000
```

Логин:

- `admin`

Пароль:

- значение `GRAFANA_PASSWORD` из `ansible/roles/run_container_monitoring/files/.env`

### Kibana

Интерфейс Kibana доступен на monitoring-хосте:

```text
http://<monitoring_public_ip>:5601
```

Логин:

- `elastic`

Пароль по умолчанию (задан в шаблоне `.env.j2`):

- `6R2dcEC95Q`

### Prometheus

В текущей конфигурации Prometheus не публикуется наружу. Он работает внутри monitoring-стека и используется как источник данных для Grafana.

## Удаление инфраструктуры

```bash
make destroy
```

Команда удаляет ресурсы, созданные Terraform в Yandex Cloud.

## Структура проекта

```text
.
├── Makefile
├── README.md
├── terraform
│   ├── local.tf
│   ├── main.tf
│   ├── monitoring.tf
│   ├── outputs.tf
│   └── variables.tf
└── ansible
    ├── ansible.cfg
    ├── group_vars
    │   ├── all.yml
    │   ├── monitoring.yaml
    │   └── web.yml
    ├── inventory.ini
    ├── playbook.yml
    └── roles
        ├── copy_app_files
        ├── copy_elk_files
        ├── copy_monitoring_files
        ├── create_user
        ├── install_docker
        ├── run_container_app
        ├── run_container_elk
        └── run_container_monitoring
```

## Текущие ограничения

- проект ориентирован на демонстрационный стенд и не настраивает HTTPS;
- пароли Grafana и ELK хранятся в репозитории, поэтому для production нужен другой способ управления секретами;
- `make start` использует обычный `terraform apply`, то есть потребует ручного подтверждения.