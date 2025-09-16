# Оглавление

- [О проекте](#о-проекте)  
- [Архитектура Helm/Helmfile](#архитектура-helmhelmfile)  
[Адаптация manual deploy в GitOps deploy](#адаптация-manual-deploy-в-gitops-deploy)  
  - [infra/](#infra)
  - [Внедрение ARGO Rollout](#внедрение-argo-rollout)
  - [Изменения Helmfile для prod и dev](#изменения-helmfile-для-prod-и-dev)  
    - [Prod (helmfile.prod.gotmpl)](#prod-helmfileprodgotmpl)  
    - [Dev (helmfile.dev.gotmpl)](#dev-helmfiledevgotmpl)
    - [Структура](#структура)  
  - [Bitnami_charts/](#bitnami_charts)  
  - [helm/](#helm)  
  - [helm/helmfile.prod.gotmpl](#helmhelmfileprodgotmpl)  
  - [helm/helmfile.dev.gotmpl](#helmhelmfiledevgotmpl)  
  - [helm/values](#helmvalues)  
- [Требования перед запуском](#требования-перед-запуском)  
- [Инструкция по запуску (Makefile)](#инструкция-по-запуску-makefile)  
  - [Подготовка](#подготовка)  
  - [Основные команды](#основные-команды)  
  - [Blue/Green (prod)](#bluegreen-prod)  
  - [Canary (prod)](#canary-prod)  
- [Реализация Blue/Green и Canary](#реализация-bluegreen-и-canary)  
  - [Стратегии деплоя](#стратегии-деплоя)  
  - [Инструкция по деплою](#инструкция-по-деплою)  
    - [1. Blue/Green деплой](#1-bluegreen-деплой)  
    - [2. Проверка нового релиза](#2-проверка-нового-релиза)  
    - [3. Переключение-трафика](#3-переключение-трафика)  
    - [4. Canary rollout](#4-canary-rollout)  
    - [5. Rollback сценарии](#5-rollback-сценарии)  
- [Kubernetes Best Practices в Helm-чартах](#kubernetes-best-practices-в-helm-чартах)  
- [Внедренные DevSecOps практики](#внедренные-devsecops-практики)  
  - [Архитектура безопасности](#архитектура-безопасности)  
  - [Покрытие](#покрытие)  
    - [Базовые проверки](#базовые-проверки)  
    - [Линтеры и SAST](#линтеры-и-sast)  
    - [Policy-as-Code](#policy-as-code)  
    - [Конфигурации и безопасность секретов](#конфигурации-и-безопасность-секретов)  
    - [CI/CD и инфраструктура](#cicd-и-инфраструктура)  
  - [Результат](#результат)  
  - [Запуск проверок](#запуск-проверок)  
    - [Соответствие OWASP Top-10](#соответствие-owasp-top-10)  

---

# О проекте

Данный проект — рабочая инфраструктура деплоя веб-приложения [`health-api`](https://gitlab.com/vikgur/health-api-for-microservice-stack) с использованием **Helm** и **Helmfile**. Репозиторий содержит полный набор чартов для сервисов приложения (backend, frontend, nginx, postgres, jaeger, swagger) и управляет их раскаткой в dev и prod окружениях.

Основные задачи:

* единая структура деплоя всех сервисов в рамках единой директории `helm/`;  
* использование Helmfile для централизованного управления релизами;  
* удобное разделение окружений через порядок подключения values-файлов;  
* единые базовые values для всех окружений, с Blue/Green/Canary оверрайдами;  
* воспроизводимый запуск через Makefile и CI/CD;  
* продвинутая стратегия выката: Blue/Green и Canary;  
* централизованный запуск через Makefile;  
* внедрение актуальных DevSecOps-практик с оптимальным покрытием.  

Особенности:

* **Единая конфигурация для всех окружений** — базовые values-файлы общие, различия вынесены в отдельные директории (`values-dev/`, `values/blue/`, `values/green/`, `values/canary/`). Порядок их подключения задаёт конкретное окружение.  
* **VERSION в проде управляет и образом, и переменной окружения**, что гарантирует строгую связку кода и артефактов.  
* Применён паттерн **Helm Monorepo**: все чарты и values хранятся в одном репозитории, что исключает дрейф версий и упрощает воспроизводимость.  
* Используются стратегии **Blue/Green и Canary**: один слот обслуживает боевой трафик, другой — выкатывает и тестирует новую версию.  

---

# Архитектура Helm/Helmfile

Проект упакован в директорию `helm/`, где каждый сервис имеет свой чарт (backend, frontend, postgres, nginx и т.д.), а управление релизами централизовано через `helmfile`.  

Values вынесены в каталог `helm/values/`, что позволяет:  
- хранить базовые настройки и оверрайды для разных окружений в одном месте,  
- легко переключаться между prod и dev,  
- использовать Blue/Green и Canary без дублирования чартов.  

В результате:  
- **структура прозрачна** — у каждого сервиса есть отдельный чарт,  
- **деплой воспроизводим** — логика окружений полностью описана в helmfile,  
- **гибкость обеспечена** — поддержка prod/dev и стратегий выката уровня продакшн.  

---

# Адаптация manual deploy в GitOps deploy

## infra/

Директория `infra/` оставлена как артефакт manual-паттерна. В GitOps не используется, но позволяет быстро откатить проект в manual при необходимости

## Внедрение ARGO Rollout

**Шаг 1. Конвертация Deployment → Rollout**

- Переименовать `deployment.yaml` в `rollout.yaml` в сервисах **backend**, **frontend**, **nginx** (best practice).  
- В манифесте заменить `kind: Deployment` на `kind: Rollout`.  
- Сохранить все настройки контейнеров (`env`, `probes`, `resources`, `volumes`).  
- В конец манифеста добавить универсальный блок стратегии:

strategy:
{{- if eq .Values.rollout.strategy "blueGreen" }}
  blueGreen:
    activeService: {{ .Values.rollout.activeService }}
    previewService: {{ .Values.rollout.previewService }}
    autoPromotionEnabled: {{ .Values.rollout.autoPromotionEnabled | default false }}
{{- else if eq .Values.rollout.strategy "canary" }}
  canary:
    steps:
      {{- toYaml .Values.rollout.steps | nindent 6 }}
{{- end }}

**Шаг 2. Настройка values для стратегий**

- В `values/blue/*` и `values/green/*` добавить блок `rollout` со стратегией **blueGreen**; различие только в `image.tag`.  
- В `values/canary/*` добавить блок `rollout` со стратегией **canary** и `steps`.  
- Сервисы без стратегий (postgres, jaeger и др.) оставить на `Deployment`.  

## Изменения Helmfile для prod и dev

### Prod (`helmfile.prod.gotmpl`)

- Оставлен **один release на сервис** (backend, frontend, nginx), вместо дубликатов (-blue/-green).  
- Подключение values через `values/{{ requiredEnv "ENV" }}` → позволяет переключать blue/green/canary через переменную `ENV`.  
- **alias-service** удалён (traffic switch теперь выполняет Argo Rollouts).  
- Выставлен порядок зависимостей: `postgres → backend → frontend → nginx`.  
- Добавлены `helmDefaults` (`wait: true`, `timeout: 600`, `verify: true`).  
- `init-db` оставлен, но выключен (`installed: false`) как fallback/manual.  

### Dev (`helmfile.dev.gotmpl`)

- Подключение values строго из `values/dev/*`.  
- Оставлен **один release на сервис**, Rollouts не используются (обычные Deployments).  
- **alias-service** выключен (`installed: false`) как неактуальный для dev.  
- `init-db` выключен (`installed: false`), оставлено для ручного исполнения, миграции будут настроены через backend-job.  
- Прописан порядок зависимостей: `postgres → backend → frontend → nginx`.  
- Добавлен блок `helmDefaults` (`wait: true`, `timeout: 600`, `verify: true`).  
- Добавлена секция `environments.dev` с `requiredEnv "VERSION"` для управления версиями образов.  

---

# Структура

## Bitnami_charts/

В проекте используется чарт PostgreSQL от Bitnami.  
Из-за ограничений доступа без VPN чарт хранится локально в репозитории.  
Это гарантирует воспроизводимость установки без внешних зависимостей.

## helm/

- **alias-service/** — вспомогательный сервис для работы с алиасами API.  
- **backend/** — Helm-чарт для основного backend-сервиса.  
- **common/** — общие шаблоны и настройки, переиспользуемые в других чартах.
- **frontend/** — Helm-чарт для frontend-приложения.  
- **infra/** — общая инфраструктура (например, конфиги для ingress-nginx или других компонентов).  
- **init-db/** — чарт для инициализации базы данных (создание схем, начальных данных).  
- **jaeger/** — чарт для системы трассировки запросов Jaeger.  
- **nginx/** — чарт для nginx-прокси внутри проекта.  
- **postgres/** — чарт для PostgreSQL (БД проекта).  
- **swagger/** — чарт для swagger-ui (UI документации API).  
- **values/** — values-файлы для всех сервисов (отдельно dev/prod, blue/green/canary).  
- **helmfile.dev.gotmpl** — конфиг для раскатки полного стека в dev-окружении.  
- **helmfile.prod.gotmpl** — конфиг для production-окружения (c blue/green и canary стратегиями).  
- **rsync-exclude.txt** — список исключений dev-файлов для синхронизации прод-файлов на мастер-ноду.

## helm/helmfile.prod.gotmpl

Файл является единой точкой управления и описывает все релизы production-окружения. Он гарантирует согласованное и воспроизводимое развертывание и позволяет в один шаг раскатить все чарт-сервисы проекта: backend, frontend, nginx, postgres, swagger, alias-service, jaeger, init-db и ingress-контроллер.  

В нём:  
- задаются пути к чартам и values-файлам,  
- подключаются переменные окружения (например `VERSION` для образов),  
- указываются зависимости между сервисами (через `needs`),  
- описаны стратегии выкладки Blue/Green (по два релиза для каждого сервиса) и отдельный релиз для Canary в ingress-nginx.  

Дополнительные сервисы:  
- **alias-service** — вспомогательный сервис для работы с алиасами API, всегда устанавливается.  
- **jaeger** — сервис трассировки запросов (observability), всегда устанавливается.  
- **init-db** — вспомогательный чарт для инициализации базы данных; по умолчанию отключён (`installed: false`), используется вручную при первичной настройке.  

## helm/helmfile.dev.gotmpl

Файл описывает все релизы локального окружения и является упрощённым аналогом production-конфига. Предназначен для разработки и отладки: позволяет в один шаг поднять полный стек приложения в namespace `health-api`.   

В нём:  
- используются упрощённые values из каталога `helm/values/values-dev/`,  
- задеплоены сервисы: backend, frontend, nginx, postgres, swagger, alias-service, jaeger, init-db, ingress-nginx,  
- задаются зависимости между сервисами (например, nginx зависит от backend и frontend),  
- переменная `VERSION` берётся из окружения и подставляется в образы backend, frontend и nginx.  

Особенности:  
- **Blue/Green и Canary здесь не применяются**, так как это окружение для разработки и тестов.  
- **init-db** может включаться для быстрой инициализации БД в dev-сценариях.  
- Все сервисы работают в одном namespace и доступны сразу после `helmfile apply`.  

## helm/values

- **blue/** — values для релизов слота Blue (backend, frontend, nginx), обслуживающего продакшн-домен.  
- **green/** — values для релизов слота Green, куда выкатывается новая версия для тестирования перед переключением.  
- **canary/** — values для canary-выкатов (Ingress с аннотациями, распределяющий часть трафика между backend и frontend).
- **values-dev/** — упрощённые values для локальной разработки и тестового окружения.  

- **backend.yaml** — общие значения для backend-сервиса.  
- **frontend.yaml** — общие значения для frontend.  
- **nginx.yaml** — базовый конфиг nginx-прокси.  
- **postgres.yaml** — параметры PostgreSQL.  
- **jaeger.yaml** — конфиг системы трассировки.  
- **swagger.yaml** — конфиг swagger-ui.  

---

# Требования перед запуском

1. **Helm** (v3) — менеджер пакетов для Kubernetes.  
   Устанавливает чарты в кластер.  

2. **Helmfile** — управление группой релизов Helm.  
   Работает с `helmfile.dev.gotmpl` и `helmfile.prod.gotmpl`.  

3. **Helm Diff Plugin** — показывает разницу между текущим состоянием и новым (`helm plugin install https://github.com/databus23/helm-diff`).  
   Нужен для команды `make diff`.  

4. **kubectl** — CLI для работы с Kubernetes.  
   Helm и Helmfile используют kubeconfig для подключения к кластеру.  

5. **Make** — для запуска команд через `Makefile`.  

6. **Доступ к кластеру Kubernetes** — рабочий kubeconfig, чтобы Helmfile мог деплоить релизы.  

---

# Инструкция по запуску (Makefile)

## Подготовка

Перед запуском задать версию образа:

```bash
export VERSION=1.0.0
```

По умолчанию используется `ENV=prod`. Для разработки указывать `ENV=dev`.

## Основные команды

* `make deploy ENV=prod` — раскатать все релизы в prod.
* `make deploy ENV=dev` — раскатать все релизы в dev.
* `make diff ENV=prod` — показать разницу перед применением.
* `make delete ENV=dev` — удалить релизы dev.

## Blue/Green (prod)

* `make deploy-blue VERSION=...` — развернуть backend, frontend и nginx в слоте blue.
* `make deploy-green VERSION=...` — развернуть backend, frontend и nginx в слоте green.
* `make switch-blue` — переключить основной сервис `nginx` (alias-service) на slot blue.
* `make switch-green` — переключить основной сервис `nginx` (alias-service) на slot green.

## Canary (prod)

* `make set-canary N=10` — направить N% трафика на новый релиз через ingress-nginx.

---

# Реализация Blue/Green и Canary

У провайдера регистрируются поддомены для `blue` и `green`. У `ingress-nginx` уже есть внешний IP/hostname и порты 80/443 открыты.

* У каждого сервиса (backend, frontend, nginx) есть две версии (blue и green).
* В Helmfile одновременно задеплоены оба варианта.
* Переключение трафика делается через Service/Ingress: в продакшн идёт либо на blue, либо на green.
* QA может проверять новый релиз (green), пока пользователи работают со старым (blue). После проверки трафик переключается.

## Стратегии деплоя

**Blue/Green**

* В кластере всегда работают два слота: `blue` и `green`.  
* Продакшн-домен (`health.gurko.ru`) указывает только на один из них.  
* Второй слот используется для выката и проверки новой версии.  
* После тестов трафик переключается на новый слот, а старый остаётся в резерве для быстрого rollback и затем обновляется до стабильной версии.  

**Canary**

* Настраивается через аннотации `ingress-nginx`.  
* Часть трафика (например, 10%) направляется на новую версию, остальное — на текущую.  
* Позволяет проверить поведение релиза на боевой нагрузке без полного переключения.  

## Инструкция по деплою

## 1. Blue/Green деплой

Раскатать оба окружения параллельно:

```bash
make deploy-blue VERSION=1.0.0
make deploy-green VERSION=1.0.0
```

По умолчанию основным слотом является **Blue**: пользовательский трафик идёт в него, так как `alias-service` настроен с селектором `track=blue`.

## 2. Проверка нового релиза

* QA или разработчик проверяет сервисы `*-green` (или `*-blue`) в namespace `health-api`.
* Пока пользователи продолжают работать с текущим окружением.

## 3. Переключение трафика

Когда новый релиз прошёл проверку:

```bash
make switch-green
```

или

```bash
make switch-blue
```

Трафик мгновенно идёт в выбранное окружение, старое остаётся как резерв для отката.

## 4. Canary rollout

Для постепенного включения нового релиза:

```bash
make set-canary N=10
```

10% трафика пойдёт в новую версию через ingress-nginx.
Можно увеличивать долю (25, 50, 100) и отслеживать метрики.

## 5. Rollback сценарии

Если новый релиз нестабилен:

* **Blue/Green:** переключить трафик обратно (`make switch-blue` или `make switch-green`).
* **Canary:** уменьшить процент до `0` или удалить canary-релиз.

Если текущий релиз (`blue`) обновлён неудачной версией:

1. **Отключить canary (если включён):**

```bash
kubectl annotate svc ingress-nginx-controller -n ingress-nginx \
  nginx.ingress.kubernetes.io/canary-weight="0" --overwrite
```

2. **Откатить blue через Helm:**

```bash
helm -n health-api history backend-blue
helm -n health-api rollback backend-blue <REV>
helm -n health-api history frontend-blue
helm -n health-api rollback frontend-blue <REV>
helm -n health-api history nginx-blue
helm -n health-api rollback nginx-blue <REV>
```

3. **Или откатить на стабильный тег образа:**

```bash
export VERSION=v1.0.XX_stable
helmfile -f helmfile.prod.gotmpl apply --selector name=backend-blue
helmfile -f helmfile.prod.gotmpl apply --selector name=frontend-blue
helmfile -f helmfile.prod.gotmpl apply --selector name=nginx-blue
```

4. **Если green содержит стабильную версию — переключиться:**

```bash
make switch-green
```

5. **Если green удалён — раскатить его заново и переключиться:**

```bash
export VERSION=v1.0.XX_stable
helmfile -f helmfile.prod.gotmpl apply --selector name=backend-green
helmfile -f helmfile.prod.gotmpl apply --selector name=frontend-green
helmfile -f helmfile.prod.gotmpl apply --selector name=nginx-green
make switch-green
```

6. **После отката:** обновить неактивный цвет на стабильный, чтобы снова иметь два окружения для Blue/Green.

---

# Kubernetes Best Practices в Helm-чартах

В проекте реализованы все ключевые best practices из продовой практики топ-компаний:

1. **Probes**  
   readinessProbe, livenessProbe, startupProbe — контроль готовности, зависаний и инициализации.

2. **Resources**  
   `resources.requests` и `resources.limits` заданы — гарантия стабильности и поддержка HPA.

3. **HPA**  
   Автоматическое масштабирование по CPU и RAM, все параметры вынесены в values.

4. **SecurityContext**  
   `runAsNonRoot`, `runAsUser`, `readOnlyRootFilesystem` — запуск в непривилегированном режиме.

5. **ServiceAccount + RBAC**  
   Сервисы запускаются под отдельными serviceAccount с ограниченными правами (RBAC).

6. **PriorityClass**  
   Назначен `priorityClassName` для управления важностью подов.

7. **Affinity & Spread**  
   Реализованы affinity, nodeSelector и topologySpreadConstraints для балансировки нагрузки.

8. **Lifecycle Hooks**  
   `preStop`/`postStart` — корректное завершение/инициализация.

9. **Graceful Shutdown**  
   Установлен `terminationGracePeriodSeconds` для корректного завершения работы.

10. **ImagePullPolicy**  
   `IfNotPresent` в проде для стабильности, `Always` — только для dev/CI.

11. **InitContainers**  
   Используются для миграций и ожидания сервисов.

12. **Volumes / PVC**  
   Подключены тома, при необходимости — персистентные (PVC).

13. **RollingUpdate Strategy**  
   Гарантия безотказного деплоя: `maxSurge: 1`, `maxUnavailable: 0`.

14. **Annotations для rollout**  
   Используются `checksum/config`, `checksum/secret` — перезапуск при изменении.

15. **Tolerations**  
   Поддержка taints, где необходимо.

16. **Helm Helpers**  
   Используются шаблоны в `_helpers.tpl` для DRY, стандартизации имён и лейблов.

17. **Secrets (точечный доступ)**  
`POSTGRES_PASSWORD` подключён безопасно из Kubernetes Secret через `valueFrom.secretKeyRef`.

18. **Multienv Helmfile**  
   Используются `helmfile.dev.yaml` и `helmfile.prod.yaml` с разными наборами values-файлов (`values-dev/` и `values/`). Все чарты общие, окружения различаются только конфигурацией.

# Внедренные DevSecOps практики

Подход к организации проекта изначально выстроен вокруг безопасного паттерна Blue/Green + Canary. DevSecOps-практики встроены как обязательный слой контроля и автоматических проверок на уровне Helm/Helmfile.

**Для работы проверок требуются:** `helm`, `helmfile`, `helm-diff`, `trivy`, `checkov`, `conftest` (OPA), `gitleaks`, `make`, `pre-commit`

## Архитектура безопасности

* **.gitleaks.toml** — правила поиска секретов, исключения для Helm-шаблонов.
* **.trivyignore** — список ложноположительных срабатываний для сканера misconfigurations.
* **policy/helm/security.rego** — OPA/Conftest-политики (запрет privileged, обязательные ресурсы и др.).
* **policy/helm/security\_test.rego** — unit-тесты для политик.
* **.checkov.yaml** — конфиг Checkov для статического анализа Kubernetes-манифестов.
* **Makefile** — цели `lint`, `scan`, `opa` для запуска проверок одной командой.
* **.gitignore** — исключает временные и чувствительные артефакты: tar-образы чартов (`*.tgz`), локальные dev-values, отчёты сканеров, IDE-файлы и зашифрованные values (`*.enc.yaml`, `*.sops.yaml`).  

## Покрытие

### Базовые проверки

* **helm lint** — синтаксис и структура чартов.
* **kubeconform** — валидация against Kubernetes API.
  → Secure SDLC: раннее выявление ошибок.

### Линтеры и SAST

* **checkov**, **trivy config** — анализ Helm/Manifests на небезопасные паттерны.
* **kubesec** — проверка securityContext, capabilities.
  → Соответствие OWASP IaC Security и CIS Benchmarks.

### Policy-as-Code

* **OPA/Conftest** — строгие правила: запрет privileged, runAsNonRoot, ресурсы обязательны.
  → OWASP Top-10: A4 Insecure Design, A5 Security Misconfiguration.

### Конфигурации и безопасность секретов

* **helm-secrets / sops** — шифрование конфиденциальных values.
* **gitleaks** — поиск секретов в коде и коммитах.
  → OWASP: A2 Cryptographic Failures, A3 Injection, A5 Security Misconfiguration.

### Pre-commit

- **.pre-commit-config.yaml** — описывает хуки, которые запускают проверки (`yamllint`, `gitleaks`, `helm lint`, `trivy`, `checkov`, `conftest`) на каждом коммите.  
- Гарантирует, что ошибки и секреты не попадут в Git ещё до запуска CI/CD.  

### CI/CD и инфраструктура

* **Makefile** — единая точка запуска DevSecOps-проверок (`make lint`, `make scan`, `make opa`).
* **Helmfile diff** — dry-run перед раскаткой.
  → OWASP A1 Broken Access Control: минимум ручных действий и ошибок.

## Результат

Внедрены ключевые DevSecOps-практики: линтеры, SAST, Policy-as-Code, поиск секретов, секрет-менеджмент. Обеспечена защита от основных категорий OWASP Top-10 (Security Misconfiguration, Insecure Design, Cryptographic Failures, Broken Access Control, Secrets Management). Конфигурация воспроизводима и безопасна: никакие секреты или артефакты не попадают в Git.

## Запуск проверок

Все проверки объединены в команды:

```bash
make lint
make scan
make opa
```

### Соответствие OWASP Top-10

Краткий маппинг практик проекта на OWASP Top-10:

- **A1 Broken Access Control** → управление через `alias-service`, единый сервис `nginx`, минимизация ручных переключений.  
- **A2 Cryptographic Failures** → секреты не хранятся в values; поиск утечек через gitleaks; (опц.) helm-secrets/sops для шифрования.  
- **A3 Injection** → отсутствие hardcoded credentials; линтеры и статический анализ (helm lint, trivy config, checkov).  
- **A4 Insecure Design** → OPA/Conftest-политики: запрет privileged, обязательные ресурсы, runAsNonRoot.  
- **A5 Security Misconfiguration** → helm lint, kubeconform, checkov; deny by default для ingress/сервисов.  
- **A6 Vulnerable and Outdated Components** → фиксированные версии чартов и образов; сканирование через trivy.  
- **A7 Identification and Authentication Failures** → частично: секреты реестра GHCR хранятся безопасно, но отдельного RBAC для helm-инфры нет.  
- **A8 Software and Data Integrity Failures** → helmfile diff и CI/CD пайплайн; подписи образов (cosign при использовании GHCR).  
- **A9 Security Logging and Monitoring Failures** → частично: observability сервисы (jaeger, prometheus) присутствуют, но централизованное логирование (например, Loki) в планах.  
- **A10 SSRF** → неприменимо к Helm/Helmfile; контролируется на уровне приложения и WAF.  
