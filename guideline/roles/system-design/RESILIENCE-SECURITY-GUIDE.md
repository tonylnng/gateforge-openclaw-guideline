# Resilience & Security — GateForge Methodology

> **Class B — Methodology.** This guide is variant-agnostic. For variant-specific runtime deltas, read the active adaptation file:
>
> - Multi-agent: [`../../adaptation/MULTI-AGENT-ADAPTATION.md`](../../adaptation/MULTI-AGENT-ADAPTATION.md)
> - Single-agent: [`../../adaptation/SINGLE-AGENT-ADAPTATION.md`](../../adaptation/SINGLE-AGENT-ADAPTATION.md)



| Field | Value |
|-------|-------|
| **Class** | B — Methodology |
| **Owner** | GateForge guideline maintainers |
| **Audience** | Any GateForge agent in the relevant phase, regardless of variant |
| **Read-with** | `BLUEPRINT-GUIDE.md`, the active variant's `SOUL.md`, and the active `adaptation/*.md` |
| **Document Status** | Active |

> This guide is the authoritative reference for every resilience and security decision made by the System Designer agent. Every design deliverable **must** be validated against the checklists in this document before submission to the System Architect (VM-1).

---

## Table of Contents

1. [Local Resilience Patterns](#1-local-resilience-patterns)
2. [Security Measurement and Assessment](#2-security-measurement-and-assessment)
3. [IT Industry News Monitoring for System Design](#3-it-industry-news-monitoring-for-system-design)
4. [Database Resilience Design](#4-database-resilience-design)
5. [Kubernetes Resilience Configuration](#5-kubernetes-resilience-configuration)
6. [Design Review Checklist](#6-design-review-checklist)

---

## 1. Local Resilience Patterns

### 1.1 Circuit Breaker Pattern

The circuit breaker prevents cascading failures by monitoring calls to a downstream service and short-circuiting requests when the failure rate exceeds a threshold. It operates in three states:

| State       | Behaviour                                                                     |
|-------------|-------------------------------------------------------------------------------|
| **Closed**  | Requests pass through normally. Failures are counted.                         |
| **Open**    | All requests are rejected immediately with a fallback response (fast-fail).   |
| **Half-Open** | A limited number of probe requests are allowed through to test recovery.   |

**Transition rules:**

```
Closed ──(failures ≥ threshold)──▶ Open
Open   ──(timeout elapsed)───────▶ Half-Open
Half-Open ──(probe succeeds)─────▶ Closed
Half-Open ──(probe fails)────────▶ Open
```

#### NestJS Implementation with Opossum

[Opossum](https://github.com/nodeshift/opossum) is the recommended circuit breaker library for Node.js/NestJS ([npm: nestjs-resilience](https://npmjs.com/package/nestjs-resilience)).

```typescript
// circuit-breaker.service.ts
import { Injectable, Logger } from '@nestjs/common';
import CircuitBreaker from 'opossum';
import { HttpService } from '@nestjs/axios';

export interface CircuitBreakerConfig {
  timeout: number;            // Time in ms before a request is considered failed
  errorThresholdPercentage: number; // % of failures to trip the circuit
  resetTimeout: number;       // Time in ms before entering half-open
  volumeThreshold: number;    // Minimum requests before threshold is evaluated
  rollingCountTimeout: number; // Statistical window in ms
}

const DEFAULT_CONFIG: CircuitBreakerConfig = {
  timeout: 5000,
  errorThresholdPercentage: 50,
  resetTimeout: 30000,
  volumeThreshold: 10,
  rollingCountTimeout: 10000,
};

@Injectable()
export class CircuitBreakerService {
  private readonly logger = new Logger(CircuitBreakerService.name);
  private readonly breakers = new Map<string, CircuitBreaker>();

  constructor(private readonly httpService: HttpService) {}

  /**
   * Get or create a circuit breaker for a named downstream service.
   */
  getBreaker(serviceName: string, config?: Partial<CircuitBreakerConfig>): CircuitBreaker {
    if (this.breakers.has(serviceName)) {
      return this.breakers.get(serviceName)!;
    }

    const merged = { ...DEFAULT_CONFIG, ...config };

    const breaker = new CircuitBreaker(
      async (url: string) => {
        const response = await this.httpService.axiosRef.get(url);
        return response.data;
      },
      {
        timeout: merged.timeout,
        errorThresholdPercentage: merged.errorThresholdPercentage,
        resetTimeout: merged.resetTimeout,
        volumeThreshold: merged.volumeThreshold,
        rollingCountTimeout: merged.rollingCountTimeout,
        name: serviceName,
      },
    );

    // Observability hooks
    breaker.on('open', () =>
      this.logger.warn(`Circuit OPEN for [${serviceName}]`),
    );
    breaker.on('halfOpen', () =>
      this.logger.log(`Circuit HALF-OPEN for [${serviceName}]`),
    );
    breaker.on('close', () =>
      this.logger.log(`Circuit CLOSED for [${serviceName}]`),
    );
    breaker.on('fallback', () =>
      this.logger.warn(`Fallback triggered for [${serviceName}]`),
    );

    // Prometheus metrics integration
    breaker.on('success', () => {
      // Increment circuit_breaker_success_total{service=serviceName}
    });
    breaker.on('failure', () => {
      // Increment circuit_breaker_failure_total{service=serviceName}
    });

    this.breakers.set(serviceName, breaker);
    return breaker;
  }

  /**
   * Execute a call through the circuit breaker with an optional fallback.
   */
  async call<T>(
    serviceName: string,
    url: string,
    fallback?: () => T,
  ): Promise<T> {
    const breaker = this.getBreaker(serviceName);
    if (fallback) {
      breaker.fallback(fallback);
    }
    return breaker.fire(url) as Promise<T>;
  }
}
```

#### Recommended Thresholds per Service Tier

| Service Tier        | Timeout | Error Threshold | Reset Timeout | Volume Threshold |
|---------------------|---------|-----------------|---------------|------------------|
| **Critical** (auth, payments) | 3 000 ms | 30%          | 60 000 ms     | 5                |
| **Standard** (CRUD APIs)      | 5 000 ms | 50%          | 30 000 ms     | 10               |
| **Non-critical** (analytics)  | 10 000 ms| 70%          | 15 000 ms     | 20               |

---

### 1.2 Retry with Exponential Backoff and Jitter

Retries recover from transient failures. Exponential backoff prevents thundering-herd effects. Jitter spreads retry bursts across time ([Jean-Marc Möckel — Retry and Exponential Backoff in NestJS](https://jean-marc.io/blog/stop-breaking-your-apis-how-to-implement-proper-retry-and-exponential-backoff-in-nestjs)).

**Formula:**

```
delay = min(MAX_DELAY, BASE_DELAY × 2^attempt) × random(0.5, 1.0)
```

#### NestJS Implementation

```typescript
// exponential-backoff.service.ts
import { HttpService } from '@nestjs/axios';
import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import axios, { AxiosError, AxiosRequestConfig } from 'axios';

export interface RetryConfig {
  maxRetries: number;
  baseDelayMs: number;
  maxDelayMs: number;
  retryableStatuses: Set<number>;
}

const DEFAULT_RETRY_CONFIG: RetryConfig = {
  maxRetries: 5,
  baseDelayMs: 1_000,
  maxDelayMs: 30_000,
  retryableStatuses: new Set([
    HttpStatus.REQUEST_TIMEOUT,     // 408
    HttpStatus.TOO_MANY_REQUESTS,   // 429
    HttpStatus.BAD_GATEWAY,         // 502
    HttpStatus.SERVICE_UNAVAILABLE, // 503
    HttpStatus.GATEWAY_TIMEOUT,     // 504
  ]),
};

@Injectable()
export class ExponentialBackoffService {
  private readonly logger = new Logger(ExponentialBackoffService.name);

  constructor(private readonly httpService: HttpService) {}

  async execute<T>(
    config: AxiosRequestConfig,
    retryConfig: Partial<RetryConfig> = {},
  ): Promise<T> {
    const cfg = { ...DEFAULT_RETRY_CONFIG, ...retryConfig };

    for (let attempt = 0; attempt < cfg.maxRetries; attempt++) {
      try {
        const response = await this.httpService.axiosRef.request<T>(config);
        return response.data;
      } catch (error) {
        if (!this.isRetryable(error, cfg)) {
          throw error;
        }

        if (attempt === cfg.maxRetries - 1) {
          this.logger.error(
            `Max retries (${cfg.maxRetries}) exceeded for ${config.url}`,
          );
          throw error;
        }

        // Respect Retry-After header if present
        const retryAfterMs = this.parseRetryAfter(error as AxiosError);
        const delay = retryAfterMs ?? this.computeDelay(attempt, cfg);

        if (delay > cfg.maxDelayMs) {
          this.logger.warn(`Delay ${delay}ms exceeds max; aborting retries`);
          throw error;
        }

        this.logger.warn(
          `Retry ${attempt + 1}/${cfg.maxRetries} for ${config.url} in ${delay}ms`,
        );
        await this.sleep(delay);
      }
    }
    throw new Error('Unexpected: retry loop exited without return or throw');
  }

  private computeDelay(attempt: number, cfg: RetryConfig): number {
    const exponential = cfg.baseDelayMs * Math.pow(2, attempt);
    const capped = Math.min(exponential, cfg.maxDelayMs);
    // Full jitter: random between 50ms and capped value
    return Math.max(50, Math.floor(Math.random() * capped));
  }

  private isRetryable(error: unknown, cfg: RetryConfig): boolean {
    if (axios.isAxiosError(error)) {
      const status = error.response?.status ?? 0;
      if (cfg.retryableStatuses.has(status)) return true;
      // Network errors are always retryable
      const code = error.code;
      return ['ECONNABORTED', 'ECONNRESET', 'ETIMEDOUT', 'ENETUNREACH'].includes(
        code ?? '',
      );
    }
    return false;
  }

  private parseRetryAfter(error: AxiosError): number | undefined {
    const header = error.response?.headers?.['retry-after'];
    if (!header) return undefined;
    const seconds = Number(header);
    if (!Number.isNaN(seconds)) return seconds * 1000;
    const dateMs = Date.parse(header);
    if (!Number.isNaN(dateMs)) return Math.max(0, dateMs - Date.now());
    return undefined;
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
```

#### Retry Configuration Template

```json
{
  "retry": {
    "auth-service": { "maxRetries": 3, "baseDelayMs": 500, "maxDelayMs": 5000 },
    "payment-service": { "maxRetries": 5, "baseDelayMs": 1000, "maxDelayMs": 30000 },
    "notification-service": { "maxRetries": 2, "baseDelayMs": 200, "maxDelayMs": 2000 },
    "analytics-service": { "maxRetries": 1, "baseDelayMs": 100, "maxDelayMs": 1000 }
  }
}
```

---

### 1.3 Bulkhead Pattern

The bulkhead pattern isolates service call pools so that a failure in one downstream dependency does not consume all available connections and starve other services.

```typescript
// bulkhead.service.ts
import { Injectable, Logger } from '@nestjs/common';

interface BulkheadConfig {
  maxConcurrent: number;
  maxQueue: number;
  queueTimeoutMs: number;
}

@Injectable()
export class BulkheadService {
  private readonly logger = new Logger(BulkheadService.name);
  private readonly pools = new Map<
    string,
    { active: number; queue: Array<() => void>; config: BulkheadConfig }
  >();

  register(name: string, config: BulkheadConfig): void {
    this.pools.set(name, { active: 0, queue: [], config });
  }

  async execute<T>(name: string, fn: () => Promise<T>): Promise<T> {
    const pool = this.pools.get(name);
    if (!pool) throw new Error(`Bulkhead [${name}] not registered`);

    if (pool.active >= pool.config.maxConcurrent) {
      if (pool.queue.length >= pool.config.maxQueue) {
        throw new Error(`Bulkhead [${name}] queue full — rejected`);
      }

      // Wait in queue
      await new Promise<void>((resolve, reject) => {
        const timer = setTimeout(() => {
          const idx = pool.queue.indexOf(resolve);
          if (idx > -1) pool.queue.splice(idx, 1);
          reject(new Error(`Bulkhead [${name}] queue timeout`));
        }, pool.config.queueTimeoutMs);

        pool.queue.push(() => {
          clearTimeout(timer);
          resolve();
        });
      });
    }

    pool.active++;
    try {
      return await fn();
    } finally {
      pool.active--;
      if (pool.queue.length > 0) {
        const next = pool.queue.shift();
        next?.();
      }
    }
  }
}
```

#### Recommended Pool Sizes

| Service Pool          | Max Concurrent | Max Queue | Queue Timeout |
|-----------------------|----------------|-----------|---------------|
| **Database**          | 20             | 50        | 5 000 ms      |
| **Redis**             | 30             | 100       | 2 000 ms      |
| **External API**      | 10             | 20        | 10 000 ms     |
| **Internal gRPC**     | 25             | 40        | 3 000 ms      |

---

### 1.4 Timeout Pattern

| Scope              | Default   | Notes                                          |
|--------------------|-----------|------------------------------------------------|
| **Global HTTP**    | 30 000 ms | Nginx ingress `proxy-read-timeout`             |
| **Database query** | 10 000 ms | pg pool `statement_timeout`                    |
| **Redis command**  | 3 000 ms  | ioredis `commandTimeout`                       |
| **Inter-service**  | 5 000 ms  | Circuit breaker `timeout` per service          |
| **gRPC deadline**  | 5 000 ms  | Set via `deadline` metadata                    |
| **Startup probe**  | 120 000 ms| K8s `initialDelaySeconds` + `periodSeconds * failureThreshold` |

#### NestJS Global Timeout Interceptor

```typescript
// timeout.interceptor.ts
import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
  RequestTimeoutException,
} from '@nestjs/common';
import { Observable, throwError, TimeoutError } from 'rxjs';
import { catchError, timeout } from 'rxjs/operators';

@Injectable()
export class TimeoutInterceptor implements NestInterceptor {
  constructor(private readonly timeoutMs: number = 30_000) {}

  intercept(_context: ExecutionContext, next: CallHandler): Observable<any> {
    return next.handle().pipe(
      timeout(this.timeoutMs),
      catchError((err) =>
        err instanceof TimeoutError
          ? throwError(() => new RequestTimeoutException('Request timed out'))
          : throwError(() => err),
      ),
    );
  }
}
```

---

### 1.5 Fallback Pattern

Graceful degradation strategies when a primary service is unavailable:

| Strategy                | When to Use                                  | Example                                          |
|-------------------------|----------------------------------------------|--------------------------------------------------|
| **Cache fallback**      | Read-heavy, stale data acceptable            | Serve last-known product catalogue from Redis     |
| **Default response**    | Non-critical feature                         | Return empty recommendations array                |
| **Queue for later**     | Write operations that can be deferred        | Enqueue failed email sends to Redis Streams       |
| **Feature flag disable**| Full feature unavailable                     | Disable payment gateway; show "maintenance" UI    |
| **Alternative service** | Redundant providers available                | Fallback SMS provider when primary is down        |

```typescript
// fallback.decorator.ts — Decorator-based fallback for NestJS services
import { Logger } from '@nestjs/common';

export function WithFallback<T>(fallbackFn: () => T | Promise<T>) {
  const logger = new Logger('WithFallback');
  return function (
    _target: any,
    propertyKey: string,
    descriptor: PropertyDescriptor,
  ) {
    const original = descriptor.value;
    descriptor.value = async function (...args: any[]) {
      try {
        return await original.apply(this, args);
      } catch (error) {
        logger.warn(`Fallback triggered for ${propertyKey}: ${error}`);
        return fallbackFn();
      }
    };
    return descriptor;
  };
}

// Usage:
// @WithFallback(() => ({ items: [], source: 'cache' }))
// async getRecommendations(userId: string) { ... }
```

---

### 1.6 Rate Limiting

#### Token Bucket vs Sliding Window Comparison

| Algorithm              | Fairness | Burst Tolerance | Memory   | Best For                           |
|------------------------|----------|-----------------|----------|------------------------------------|
| **Fixed Window**       | Low      | High at edges   | Very Low | Simple internal limits             |
| **Sliding Window Log** | High     | Low             | High     | Strict fairness enforcement        |
| **Sliding Window Counter** | Medium–High | Low–Medium | Moderate | Scalable public APIs             |
| **Token Bucket**       | Medium–High | Controlled bursts | Low  | Developer-facing APIs              |

Source: [Arcjet — Rate Limiting Algorithms](https://blog.arcjet.com/rate-limiting-algorithms-token-bucket-vs-sliding-window-vs-fixed-window/)

#### NestJS Rate Limiting with Redis (Sliding Window)

```typescript
// rate-limiter.guard.ts
import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { HttpException, HttpStatus } from '@nestjs/common';
import Redis from 'ioredis';

@Injectable()
export class RateLimiterGuard implements CanActivate {
  private redis = new Redis({ host: 'redis-sentinel', port: 26379 });

  private readonly WINDOW_SIZE = 60; // seconds
  private readonly MAX_REQUESTS = 100;

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const key = `ratelimit:${request.ip}`;
    const now = Date.now();
    const windowStart = now - this.WINDOW_SIZE * 1000;

    const pipeline = this.redis.pipeline();
    pipeline.zremrangebyscore(key, 0, windowStart);
    pipeline.zcard(key);
    pipeline.zadd(key, now, now.toString());
    pipeline.expire(key, this.WINDOW_SIZE);
    const results = await pipeline.exec();

    const count = results?.[1]?.[1] as number;
    if (count >= this.MAX_REQUESTS) {
      throw new HttpException(
        {
          statusCode: HttpStatus.TOO_MANY_REQUESTS,
          message: 'Rate limit exceeded',
          retryAfter: this.WINDOW_SIZE,
        },
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    return true;
  }
}
```

#### Rate Limit Configuration by Endpoint

| Endpoint Category  | Window | Max Requests | Algorithm        |
|--------------------|--------|-------------|------------------|
| `/api/auth/login`  | 15 min | 5           | Fixed Window     |
| `/api/auth/register` | 1 hr | 3           | Fixed Window     |
| `/api/*` (general) | 1 min  | 100         | Sliding Window   |
| `/api/search`      | 1 min  | 30          | Token Bucket     |
| `/api/upload`      | 1 min  | 10          | Token Bucket     |
| `/webhook/*`       | 1 min  | 200         | Sliding Window   |

---

### 1.7 Health Check Probes

Kubernetes defines three probe types. All GateForge services **must** implement all three.

| Probe Type     | Purpose                                        | Endpoint          | Failure Action                    |
|----------------|------------------------------------------------|--------------------|-----------------------------------|
| **Liveness**   | Detect deadlocks / unrecoverable states        | `GET /health/live` | Pod is restarted                  |
| **Readiness**  | Confirm service can accept traffic             | `GET /health/ready`| Pod removed from Service endpoints|
| **Startup**    | Allow slow-starting containers to initialize   | `GET /health/startup` | Pod is killed after threshold  |

#### NestJS Health Module with Terminus

```typescript
// health.controller.ts
import { Controller, Get } from '@nestjs/common';
import {
  HealthCheck,
  HealthCheckService,
  TypeOrmHealthIndicator,
  MemoryHealthIndicator,
  DiskHealthIndicator,
} from '@nestjs/terminus';

@Controller('health')
export class HealthController {
  constructor(
    private health: HealthCheckService,
    private db: TypeOrmHealthIndicator,
    private memory: MemoryHealthIndicator,
    private disk: DiskHealthIndicator,
  ) {}

  @Get('live')
  @HealthCheck()
  liveness() {
    return this.health.check([
      // Liveness: only check process is alive + memory
      () => this.memory.checkHeap('memory_heap', 300 * 1024 * 1024), // 300 MB
    ]);
  }

  @Get('ready')
  @HealthCheck()
  readiness() {
    return this.health.check([
      // Readiness: check all dependencies
      () => this.db.pingCheck('database', { timeout: 3000 }),
      () => this.memory.checkHeap('memory_heap', 300 * 1024 * 1024),
      () =>
        this.disk.checkStorage('disk', {
          thresholdPercent: 0.9,
          path: '/',
        }),
    ]);
  }

  @Get('startup')
  @HealthCheck()
  startup() {
    return this.health.check([
      () => this.db.pingCheck('database', { timeout: 10000 }),
    ]);
  }
}
```

#### Kubernetes Probe Configuration

```yaml
# probes.yaml — Standard probe template for all GateForge services
livenessProbe:
  httpGet:
    path: /health/live
    port: 3000
  initialDelaySeconds: 15
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
  successThreshold: 1

readinessProbe:
  httpGet:
    path: /health/ready
    port: 3000
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
  successThreshold: 1

startupProbe:
  httpGet:
    path: /health/startup
    port: 3000
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 12    # 12 × 10s = 120s max startup time
  successThreshold: 1
```

---

### 1.8 Resilience Pattern Decision Matrix

Use this matrix to select the correct pattern for each failure mode:

| Failure Mode                  | Circuit Breaker | Retry | Bulkhead | Timeout | Fallback | Rate Limit |
|-------------------------------|:-:|:-:|:-:|:-:|:-:|:-:|
| Downstream service unavailable | ✅ | ✅ | ✅ |   | ✅ |    |
| Downstream service slow        | ✅ |   |   | ✅ | ✅ |    |
| Transient network error        |   | ✅ |   | ✅ |    |    |
| Dependency overload            | ✅ |   | ✅ |   |    | ✅ |
| Resource exhaustion (local)    |   |   | ✅ |   | ✅ |    |
| DDoS / abuse                   |   |   |   |   |    | ✅ |
| Database connection pool full  |   |   | ✅ | ✅ | ✅ |    |
| Cascading failure risk         | ✅ |   | ✅ | ✅ |    |    |

**Rule:** Always combine **Circuit Breaker + Timeout + Fallback** for any external dependency. Add **Retry** only for idempotent operations.

---

### 1.9 Redis High Availability Configuration

#### Redis Sentinel Mode

Use when the dataset fits in a single node's memory and you need HA without sharding.

```yaml
# redis-sentinel.yaml — Docker Compose snippet
services:
  redis-master:
    image: redis:7-alpine
    command: >
      redis-server
      --requirepass ${REDIS_PASSWORD}
      --maxmemory 2gb
      --maxmemory-policy allkeys-lru
      --appendonly yes
      --appendfsync everysec
    ports:
      - "6379:6379"
    volumes:
      - redis-master-data:/data

  redis-replica-1:
    image: redis:7-alpine
    command: >
      redis-server
      --replicaof redis-master 6379
      --masterauth ${REDIS_PASSWORD}
      --requirepass ${REDIS_PASSWORD}
      --appendonly yes
    depends_on:
      - redis-master

  redis-sentinel-1:
    image: redis:7-alpine
    command: >
      redis-sentinel /etc/redis/sentinel.conf
    volumes:
      - ./sentinel.conf:/etc/redis/sentinel.conf

# sentinel.conf
# sentinel monitor gateforge-master redis-master 6379 2
# sentinel down-after-milliseconds gateforge-master 5000
# sentinel failover-timeout gateforge-master 60000
# sentinel parallel-syncs gateforge-master 1
# sentinel auth-pass gateforge-master ${REDIS_PASSWORD}
```

#### Redis Cluster Mode

Use when data exceeds a single node's memory or you need write scaling ([Redis Cluster Architecture Guide](https://www.youngju.dev/blog/database/2026-03-12-redis-cluster-sentinel-high-availability-memory-optimization.en)).

```bash
# Create a 6-node cluster (3 masters + 3 replicas)
redis-cli --cluster create \
  10.0.1.20:7000 10.0.1.21:7001 10.0.1.22:7002 \
  10.0.1.20:7003 10.0.1.21:7004 10.0.1.22:7005 \
  --cluster-replicas 1 -a ${REDIS_PASSWORD}
```

#### Decision Criteria

| Criterion                            | Sentinel | Cluster  |
|--------------------------------------|----------|----------|
| Dataset fits in single node memory   | ✅       | ✅       |
| Dataset exceeds single node memory   | ❌       | ✅       |
| Write scaling needed                 | ❌       | ✅       |
| Multi-key transactions               | ✅       | ⚠️ hash tags |
| Operational complexity               | Low      | High     |
| Minimum nodes                        | 3 Sentinel + 1M + 1R | 6 (3M + 3R) |

---

### 1.10 PostgreSQL HA Configuration

See full details in [Section 4 — Database Resilience Design](#4-database-resilience-design).

---

## 2. Security Measurement and Assessment

### 2.1 Security Assessment Checklist for Every Design Deliverable

Every design document submitted by the System Designer **must** include a completed security assessment section. Use this checklist:

- [ ] **Authentication**: All endpoints specify authentication method (JWT, API key, mTLS)
- [ ] **Authorization**: RBAC model defined; principle of least privilege applied
- [ ] **Input validation**: All inputs have defined schemas (JSON Schema, class-validator DTOs)
- [ ] **Output encoding**: Response serialization prevents XSS and injection
- [ ] **Secrets management**: No hardcoded secrets; Vault/Sealed Secrets path documented
- [ ] **Transport security**: TLS 1.3 enforced; certificate rotation plan documented
- [ ] **Network segmentation**: NetworkPolicy defined for the namespace
- [ ] **Logging**: Security events logged in structured JSON (no PII in logs)
- [ ] **Error handling**: No stack traces or internal details leaked to clients
- [ ] **Dependency review**: `npm audit` shows zero HIGH/CRITICAL; Trivy scan passes
- [ ] **Container hardening**: Non-root user, read-only filesystem, capabilities dropped
- [ ] **Rate limiting**: Defined for all public-facing and auth endpoints
- [ ] **CORS**: Explicit allowlist; no wildcard origins in production
- [ ] **Rollback strategy**: Documented and tested

---

### 2.2 OWASP ASVS Checklist Adapted for NestJS

The [OWASP Application Security Verification Standard (ASVS)](https://www.pivotpointsecurity.com/owasp-asvs-version-4-0-controls-checklist-spreadsheet-5-benefits/) organises security into three verification levels. GateForge targets **Level 2** as the minimum for all services. The following table maps ASVS chapters to NestJS implementation controls:

| ASVS Chapter | Key Requirement | NestJS Implementation | Level |
|---|---|---|---|
| **V2: Authentication** | Multi-factor for admin | `@nestjs/passport` + TOTP strategy | L2 |
| **V2.1** | Password length ≥ 12 chars | `class-validator` `@MinLength(12)` on DTO | L1 |
| **V3: Session Management** | New session token on auth | `express-session` `regenerate()` on login | L1 |
| **V3.2** | Session timeout ≤ 30 min idle | `express-session` `cookie.maxAge` | L1 |
| **V4: Access Control** | Deny by default | `@UseGuards(AuthGuard, RolesGuard)` | L1 |
| **V4.1** | Enforce at server side | NestJS Guards (never trust client) | L1 |
| **V5: Input Validation** | Validate all inputs | `class-validator` + `ValidationPipe` global | L1 |
| **V5.3** | SQL injection prevention | TypeORM parameterised queries; never raw SQL concat | L1 |
| **V5.5** | XML entity injection prevention | Disable DTD parsing; use `fast-xml-parser` safely | L1 |
| **V6: Cryptography** | AES-256-GCM or ChaCha20 | `crypto` module; no MD5/SHA1 for security | L2 |
| **V7: Error Handling & Logging** | No sensitive data in errors | Global `ExceptionFilter` strips internals | L1 |
| **V7.1** | Structured logging | `@nestjs/common` Logger + Pino in JSON mode | L1 |
| **V8: Data Protection** | PII encrypted at rest | TypeORM column transformers with AES encryption | L2 |
| **V9: Communication** | TLS everywhere | Kubernetes TLS termination at ingress + mTLS mesh | L1 |
| **V10: Malicious Code** | Dependency integrity | `npm audit` + `package-lock.json` integrity | L2 |
| **V13: API Security** | JSON schema validation | `class-validator` + OpenAPI spec validation | L1 |
| **V14: Configuration** | Security headers set | Helmet.js middleware in NestJS | L1 |

Source: [SoftwareMill — Implementing OWASP ASVS](https://softwaremill.com/implementing-owasp-asvs/)

---

### 2.3 Security Headers Checklist

All GateForge services must set these headers. Use [Helmet.js](https://helmetjs.github.io/) as the baseline, then customize ([Barrion — Security Headers Guide](https://barrion.io/blog/security-headers-guide)):

```typescript
// main.ts — Security headers via Helmet
import helmet from 'helmet';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.use(
    helmet({
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'self'"],
          scriptSrc: ["'self'"],
          styleSrc: ["'self'", "'unsafe-inline'"],  // Tighten after CSS-in-JS audit
          imgSrc: ["'self'", 'data:', 'https://cdn.gateforge.io'],
          connectSrc: ["'self'", 'https://api.gateforge.io'],
          fontSrc: ["'self'"],
          objectSrc: ["'none'"],
          frameAncestors: ["'none'"],
          upgradeInsecureRequests: [],
        },
      },
      strictTransportSecurity: {
        maxAge: 63072000,       // 2 years
        includeSubDomains: true,
        preload: true,
      },
      xFrameOptions: { action: 'deny' },
      xContentTypeOptions: true,
      referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
      permissionsPolicy: {
        camera: [],
        microphone: [],
        geolocation: [],
        payment: [],
      },
    }),
  );
}
```

#### Security Headers Verification Checklist

| Header                          | Value                                               | Verify With                          |
|---------------------------------|------------------------------------------------------|--------------------------------------|
| `Strict-Transport-Security`     | `max-age=63072000; includeSubDomains; preload`       | [securityheaders.com](https://securityheaders.com) |
| `Content-Security-Policy`       | Restrictive directives (no `unsafe-eval`)            | Browser DevTools Console             |
| `X-Frame-Options`               | `DENY`                                               | Try embedding in iframe              |
| `X-Content-Type-Options`        | `nosniff`                                            | Response header inspection           |
| `Referrer-Policy`               | `strict-origin-when-cross-origin`                    | Cross-origin navigation test         |
| `Permissions-Policy`            | `camera=(), microphone=(), geolocation=()`           | Feature detection test               |
| `X-XSS-Protection`              | `0` (deprecated; rely on CSP)                        | Header present check                 |
| `Cross-Origin-Embedder-Policy`  | `require-corp`                                       | SharedArrayBuffer test               |
| `Cross-Origin-Opener-Policy`    | `same-origin`                                        | Window reference test                |

Source: [DCHost — HTTP Security Headers Guide](https://www.dchost.com/blog/en/http-security-headers-guide-how-to-correctly-set-hsts-csp-x-frame-options-and-referrer-policy/)

---

### 2.4 TLS Configuration Best Practices

```yaml
# nginx-ingress TLS configuration
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gateforge-ingress
  annotations:
    nginx.ingress.kubernetes.io/ssl-protocols: "TLSv1.3"
    nginx.ingress.kubernetes.io/ssl-ciphers: "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256"
    nginx.ingress.kubernetes.io/ssl-prefer-server-ciphers: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/hsts: "true"
    nginx.ingress.kubernetes.io/hsts-max-age: "63072000"
    nginx.ingress.kubernetes.io/hsts-include-subdomains: "true"
    nginx.ingress.kubernetes.io/hsts-preload: "true"
spec:
  tls:
    - hosts:
        - api.gateforge.io
        - app.gateforge.io
      secretName: gateforge-tls
```

**Certificate rotation with cert-manager:**

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: gateforge-cert
  namespace: production
spec:
  secretName: gateforge-tls
  duration: 2160h     # 90 days
  renewBefore: 720h   # Renew 30 days before expiry
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - api.gateforge.io
    - app.gateforge.io
```

---

### 2.5 Network Segmentation: Kubernetes NetworkPolicy

```yaml
# 1. Default deny all traffic in production namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress

---
# 2. Allow DNS resolution
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53

---
# 3. Allow same-namespace communication
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}
  egress:
    - to:
        - podSelector: {}

---
# 4. Allow ingress controller traffic to exposed services
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-controller
  namespace: production
spec:
  podSelector:
    matchLabels:
      expose: "true"
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
      ports:
        - protocol: TCP
          port: 3000

---
# 5. Allow monitoring namespace to scrape metrics
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
      ports:
        - protocol: TCP
          port: 9090
```

Source: [OneUptime — Kubernetes Namespace Isolation](https://oneuptime.com/blog/post/2026-01-30-kubernetes-namespace-isolation/view)

---

### 2.6 Secrets Management Workflow

GateForge uses a **two-tier** approach:

| Tier | Tool | Use Case |
|------|------|----------|
| **Standard** | Sealed Secrets | Application secrets (DB passwords, API keys) committed to Git encrypted |
| **Enterprise** | HashiCorp Vault | Dynamic secrets (DB credentials), PKI, encryption-as-a-service |

Source: [OneUptime — Kubernetes Secrets with Vault or Sealed Secrets](https://oneuptime.com/blog/post/2026-01-06-kubernetes-secrets-vault-sealed-secrets/view)

#### Sealed Secrets Workflow (Default)

```bash
# 1. Create a plain secret (never apply directly!)
kubectl create secret generic db-creds \
  --from-literal=username=admin \
  --from-literal=password=$(openssl rand -base64 32) \
  --dry-run=client -o yaml > secret.yaml

# 2. Encrypt with kubeseal (safe to commit)
kubeseal --format yaml --scope strict < secret.yaml > sealed-secret.yaml

# 3. Commit encrypted secret
git add sealed-secret.yaml
git commit -m "feat: add encrypted db credentials"

# 4. Apply — controller decrypts in-cluster
kubectl apply -f sealed-secret.yaml

# 5. Verify
kubectl get secret db-creds -o jsonpath='{.data.username}' | base64 -d
```

#### Vault Integration (For Dynamic Secrets)

```yaml
# vault-secret-provider.yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-db-creds
  namespace: production
spec:
  provider: vault
  parameters:
    roleName: "gateforge-api"
    vaultAddress: "http://vault.vault.svc:8200"
    objects: |
      - objectName: "db-username"
        secretPath: "secret/data/gateforge/db"
        secretKey: "username"
      - objectName: "db-password"
        secretPath: "secret/data/gateforge/db"
        secretKey: "password"
  secretObjects:
    - secretName: gateforge-db-creds
      type: Opaque
      data:
        - objectName: db-username
          key: DB_USERNAME
        - objectName: db-password
          key: DB_PASSWORD
```

**Decision criteria:**

| Feature             | Sealed Secrets | Vault     |
|---------------------|---------------|-----------|
| Complexity          | Low           | High      |
| Dynamic secrets     | No            | Yes       |
| Secret rotation     | Manual        | Automatic |
| Audit logging       | No            | Yes       |
| Multi-cluster       | Per-cluster   | Centralized |
| GitOps friendly     | Excellent     | Good      |

---

### 2.7 Container Security

Every GateForge container **must** follow these hardening rules ([Dynatrace — Kubernetes Security Contexts](https://www.dynatrace.com/news/blog/kubernetes-security-best-practices-security-context/)):

```yaml
# secure-deployment-template.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gateforge-api
  namespace: production
spec:
  template:
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 3000
        fsGroup: 3000
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: api
          image: ghcr.io/gateforge/api:1.0.0
          securityContext:
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
          resources:
            requests:
              cpu: "200m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            - name: cache
              mountPath: /home/node/.cache
      volumes:
        - name: tmp
          emptyDir: {}
        - name: cache
          emptyDir: {}
```

#### Container Security Checklist

| Control                        | Setting                          | Required |
|--------------------------------|----------------------------------|----------|
| Non-root user                  | `runAsNonRoot: true`             | ✅       |
| Specific UID                   | `runAsUser: 1000`                | ✅       |
| Read-only root filesystem      | `readOnlyRootFilesystem: true`   | ✅       |
| No privilege escalation        | `allowPrivilegeEscalation: false`| ✅       |
| Drop all capabilities          | `capabilities.drop: [ALL]`       | ✅       |
| Seccomp profile                | `seccompProfile.type: RuntimeDefault` | ✅  |
| Resource limits set            | CPU + Memory limits defined      | ✅       |
| No hostPath volumes            | Never mount host filesystem      | ✅       |
| No privileged mode             | `privileged: false`              | ✅       |
| Automount SA token disabled    | Unless needed for Vault/K8s API  | ✅       |

---

### 2.8 Dependency Vulnerability Scanning Pipeline

#### GitHub Actions Workflow

```yaml
# .github/workflows/security-scan.yml
name: Security Scan

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 0 * * *'   # Daily scan for new CVEs

jobs:
  npm-audit:
    name: npm Audit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - run: npm audit --audit-level=high
        continue-on-error: false

  trivy-fs:
    name: Trivy Filesystem Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Scan dependencies
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: '.'
          format: 'sarif'
          output: 'trivy-fs.sarif'
          severity: 'HIGH,CRITICAL'
      - name: Upload to GitHub Security
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: 'trivy-fs.sarif'

  trivy-image:
    name: Trivy Container Scan
    runs-on: ubuntu-latest
    needs: [npm-audit]
    steps:
      - uses: actions/checkout@v4
      - name: Build image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: false
          load: true
          tags: gateforge-api:${{ github.sha }}
      - name: Scan image
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'gateforge-api:${{ github.sha }}'
          format: 'table'
          exit-code: '1'
          ignore-unfixed: true
          vuln-type: 'os,library'
          severity: 'HIGH,CRITICAL'

  trivy-iac:
    name: Trivy IaC Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Scan IaC
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'config'
          scan-ref: '.'
          severity: 'MEDIUM,HIGH,CRITICAL'
          exit-code: '1'

  security-gate:
    name: Security Gate
    needs: [npm-audit, trivy-fs, trivy-image, trivy-iac]
    runs-on: ubuntu-latest
    steps:
      - run: echo "All security scans passed"
```

Source: [OneUptime — Trivy in CI/CD](https://oneuptime.com/blog/post/2026-02-02-trivy-cicd/view)

---

### 2.9 Penetration Test Checklist

Before each major release, validate the following:

| Category | Test | Tool | Pass Criteria |
|---|---|---|---|
| **Authentication** | Brute-force login | Hydra / Burp | Rate limiting blocks after 5 attempts |
| **Authentication** | JWT manipulation | jwt.io / jwt_tool | Modified tokens rejected; signature verified |
| **Authorization** | IDOR (Insecure Direct Object Reference) | Manual / Burp | Cannot access other users' resources |
| **Authorization** | Privilege escalation | Manual | Non-admin cannot access admin endpoints |
| **Injection** | SQL injection | SQLMap | No injection vectors found |
| **Injection** | NoSQL injection | Manual | Parameterised queries prevent injection |
| **Injection** | XSS (stored, reflected, DOM) | OWASP ZAP | CSP blocks inline scripts; no reflections |
| **Injection** | Command injection | Manual | No shell execution with user input |
| **Transport** | TLS version | SSLyze / testssl.sh | Only TLS 1.3 accepted |
| **Transport** | Certificate validity | openssl s_client | Valid chain, strong cipher, correct SAN |
| **API** | Rate limiting bypass | curl scripting | Rate limits enforced across bypass techniques |
| **API** | Mass assignment | Burp | Extra fields in request ignored |
| **API** | CORS misconfiguration | curl | No wildcard origins; only allowlisted |
| **Infrastructure** | Container escape | Manual / kube-hunter | Non-root, read-only FS prevents escape |
| **Infrastructure** | Network segmentation | nmap from other pods | NetworkPolicy blocks cross-namespace traffic |
| **Data** | PII exposure in logs | Log review | No PII in structured JSON logs |
| **Data** | Backup encryption | Manual | Backups encrypted at rest |

---

### 2.10 Security Scoring Model

Quantify the security posture of each design with a weighted score (0–100):

| Category (Weight)           | Criteria                                                            | Score |
|-----------------------------|---------------------------------------------------------------------|-------|
| **Authentication (15%)**    | MFA available, strong password policy, token lifecycle managed      | 0–100 |
| **Authorization (15%)**     | RBAC implemented, least privilege, deny-by-default                  | 0–100 |
| **Input Validation (10%)**  | All inputs validated, schema-based, no raw SQL                      | 0–100 |
| **Transport Security (10%)**| TLS 1.3, valid certs, HSTS, no mixed content                       | 0–100 |
| **Secrets Management (10%)**| No hardcoded secrets, rotation plan, Vault/Sealed Secrets           | 0–100 |
| **Container Security (10%)**| Non-root, read-only FS, capabilities dropped, resource limits       | 0–100 |
| **Network Segmentation (10%)**| NetworkPolicies, default-deny, ingress-only exposure             | 0–100 |
| **Dependency Health (10%)**| Zero HIGH/CRITICAL CVEs, Trivy passes, npm audit clean             | 0–100 |
| **Logging & Monitoring (5%)**| Structured logging, no PII, security events tracked               | 0–100 |
| **Incident Readiness (5%)** | Rollback plan, incident response documented                       | 0–100 |

**Overall Score = Σ (Category Score × Weight)**

| Score Range | Rating     | Action                          |
|-------------|------------|---------------------------------|
| 90–100      | Excellent  | Approve for production          |
| 75–89       | Good       | Approve with minor remediations |
| 60–74       | Fair       | Remediate before deployment     |
| < 60        | Poor       | Redesign required               |

---

### 2.11 Threat Modeling: STRIDE for Microservices

Apply [STRIDE](https://www.practical-devsecops.com/what-is-stride-threat-model/) to every new service or API boundary:

#### STRIDE Categories

| Threat                     | Description                            | Property Violated | Mitigation                                |
|----------------------------|----------------------------------------|-------------------|-------------------------------------------|
| **S**poofing               | Impersonating another user/service     | Authentication    | JWT + mTLS, short-lived tokens, MFA       |
| **T**ampering              | Modifying data in transit or at rest   | Integrity         | TLS, signed payloads, DB checksums        |
| **R**epudiation            | Denying having performed an action     | Non-repudiation   | Audit logs, signed events, immutable logs |
| **I**nformation Disclosure | Exposing data to unauthorized parties  | Confidentiality   | Encryption, access control, log scrubbing |
| **D**enial of Service      | Making service unavailable             | Availability      | Rate limiting, circuit breakers, HPA      |
| **E**levation of Privilege | Gaining unauthorized access level      | Authorization     | RBAC, input validation, least privilege   |

Source: [Jit.io — STRIDE Threat Model Guide](https://www.jit.io/resources/app-security/stride-threat-model-a-complete-guide)

#### STRIDE Threat Modeling Workflow

```
1. DECOMPOSE the system
   ├── Identify all microservices and their boundaries
   ├── Draw Data Flow Diagrams (DFD)
   ├── Mark trust boundaries (ingress, inter-service, DB, external APIs)
   └── List all entry points and data stores

2. ANALYSE each component through STRIDE lens
   ├── For each service/API endpoint, ask:
   │   ├── Can identity be spoofed?
   │   ├── Can data be tampered with?
   │   ├── Can actions be repudiated?
   │   ├── Can data be disclosed?
   │   ├── Can the service be denied?
   │   └── Can privileges be elevated?
   └── Document all identified threats

3. SCORE threats using DREAD or CVSS
   ├── Damage potential (1-10)
   ├── Reproducibility (1-10)
   ├── Exploitability (1-10)
   ├── Affected users (1-10)
   └── Discoverability (1-10)

4. MITIGATE
   ├── Map each threat to a security control
   ├── Assign owner and timeline
   └── Document in design deliverable

5. VERIFY
   ├── Security controls implemented
   ├── Penetration test covers identified threats
   └── Residual risk accepted by Architect
```

#### STRIDE Template for a Microservice

```markdown
### Threat Model: [Service Name]

| # | Threat Category | Threat Description | Risk (H/M/L) | Mitigation | Owner | Status |
|---|-----------------|-------------------|---------------|------------|-------|--------|
| 1 | Spoofing        | Forged JWT token  | High          | RS256 + short expiry + token rotation | Auth team | ✅ |
| 2 | Tampering       | Modified request body | Medium    | Request signing + schema validation | API team | ✅ |
| 3 | Repudiation     | User denies action | Low          | Immutable audit log with timestamps | Platform | ✅ |
| 4 | Info Disclosure | PII in error messages | High      | Global exception filter strips internals | Dev | ⬜ |
| 5 | DoS             | Unbounded queries | Medium        | Rate limiting + query complexity limit | API team | ✅ |
| 6 | Elevation       | Admin API accessible | High       | RBAC guard + network policy | Security | ✅ |
```

---

### 2.12 Security Incident Response Plan Template

```markdown
# Security Incident Response Plan — [Service Name]

## 1. Detection
- [ ] Alert received from: Prometheus / Trivy / WAF / Manual report
- [ ] Incident severity classified: CRITICAL / HIGH / MEDIUM / LOW
- [ ] Incident ID assigned: SEC-YYYY-MM-DD-NNN

## 2. Triage (Target: < 15 minutes)
- [ ] Confirm incident is real (not false positive)
- [ ] Identify affected services and data
- [ ] Identify blast radius (users, data, systems)
- [ ] Notify incident commander: the end-user

## 3. Containment (Target: < 1 hour for CRITICAL)
- [ ] Isolate affected service (scale to 0 or block ingress)
- [ ] Rotate compromised credentials
- [ ] Block attacker IP/token at WAF/ingress level
- [ ] Preserve evidence (logs, pod state, network captures)

## 4. Eradication
- [ ] Identify root cause
- [ ] Patch vulnerability
- [ ] Rebuild affected containers from clean images
- [ ] Re-scan with Trivy to confirm fix

## 5. Recovery
- [ ] Deploy patched version through standard CI/CD
- [ ] Verify service health via readiness probes
- [ ] Gradually restore traffic (canary → full rollout)
- [ ] Monitor for recurrence (72-hour watch)

## 6. Post-Incident
- [ ] Write post-mortem within 48 hours
- [ ] Update threat model with new findings
- [ ] Create follow-up tasks for systemic improvements
- [ ] Update this guide if new patterns needed
- [ ] Notify affected users if data breach (GDPR/PDPO requirement)

## Response Time Targets (MTTR)
| Severity | Detection → Triage | Triage → Containment | Full Resolution |
|----------|-------------------|---------------------|-----------------|
| CRITICAL | < 15 min          | < 1 hour            | < 4 hours       |
| HIGH     | < 30 min          | < 4 hours           | < 24 hours      |
| MEDIUM   | < 2 hours         | < 1 day             | < 1 week        |
| LOW      | < 1 day           | < 1 week            | < 1 month       |
```

Source: [OWASP — Security Metrics & Monitoring](https://owasp.org/www-project-agentic-skills-top-10/metrics-monitoring.html)

---

## 3. IT Industry News Monitoring for System Design

### 3.1 Why Continuous Awareness Matters

The System Designer agent operates in a rapidly evolving threat landscape. New vulnerabilities (CVEs), framework-breaking changes, and architectural best practices emerge weekly. Failing to track these can lead to:

- **Designs based on deprecated or vulnerable patterns** (e.g., using a library with a known RCE)
- **Missing Kubernetes or Docker security patches** that require infrastructure redesign
- **Compliance gaps** when new regulations mandate specific controls
- **Missed optimization opportunities** from new platform features

The Designer must maintain awareness as a **continuous background activity**, not a one-time exercise.

---

### 3.2 Key Sources to Monitor

| Source | URL | Frequency | Focus |
|--------|-----|-----------|-------|
| **NVD (National Vulnerability Database)** | https://nvd.nist.gov/ | Daily | All CVEs with CVSS scores |
| **GitHub Security Advisories** | https://github.com/advisories | Daily | npm, Docker, language-specific |
| **OWASP Updates** | https://owasp.org/www-project-top-ten/ | Monthly | Application security standards |
| **Node.js Security Releases** | https://nodejs.org/en/blog/vulnerability | Per release | Runtime vulnerabilities |
| **Docker Security Bulletins** | https://docs.docker.com/security/ | Weekly | Container runtime issues |
| **Kubernetes Security Announcements** | https://kubernetes.io/docs/reference/issues-security/official-cve-feed/ | Weekly | K8s CVEs and patches |
| **AWS/GCP/Azure Security Bulletins** | Provider-specific | Weekly | Cloud infrastructure issues |
| **TypeScript Release Notes** | https://devblogs.microsoft.com/typescript/ | Per release | Language-level changes |
| **React Security** | https://github.com/facebook/react/security/advisories | Per release | Frontend framework issues |
| **NestJS Releases** | https://github.com/nestjs/nest/releases | Per release | Backend framework security fixes |
| **Redis Security** | https://redis.io/docs/latest/operate/oss_and_stack/management/security/ | Monthly | Data store vulnerabilities |
| **PostgreSQL Security** | https://www.postgresql.org/support/security/ | Monthly | Database vulnerabilities |

---

### 3.3 Monitoring Workflow

The Designer agent should follow this cadence:

```
┌─────────────────────────────────────────────────────┐
│              DAILY (Automated)                       │
│  • Check GitHub Security Advisories for npm deps     │
│  • Review NVD feed for CRITICAL/HIGH CVEs            │
│  • Check Node.js security releases                   │
│  • Run `npm audit` on all projects                   │
└───────────────────────┬─────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────┐
│              WEEKLY (Semi-automated)                  │
│  • Review Kubernetes security announcements           │
│  • Check Docker security bulletins                    │
│  • Scan container images with Trivy                   │
│  • Review Redis/PostgreSQL security pages             │
│  • Update dependency versions if patches available    │
└───────────────────────┬─────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────┐
│              MONTHLY (Manual review)                  │
│  • Review OWASP updates and new advisories            │
│  • Assess new framework releases for security impact  │
│  • Update STRIDE threat models for changed services   │
│  • Run full penetration test suite                    │
│  • Review and update this guide                       │
└─────────────────────────────────────────────────────┘
```

---

### 3.4 RSS/Webhook Integration Patterns

#### GitHub Actions Scheduled Security Scan

```yaml
# .github/workflows/cve-monitor.yml
name: CVE Monitor

on:
  schedule:
    - cron: '0 8 * * *'   # Daily at 08:00 UTC

jobs:
  check-advisories:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - name: npm audit
        run: |
          npm audit --json > audit-results.json || true
          CRITICAL=$(cat audit-results.json | jq '.metadata.vulnerabilities.critical')
          HIGH=$(cat audit-results.json | jq '.metadata.vulnerabilities.high')
          if [ "$CRITICAL" -gt 0 ] || [ "$HIGH" -gt 0 ]; then
            echo "⚠️ Found $CRITICAL critical, $HIGH high vulnerabilities"
            # Send notification to Slack/webhook
            curl -X POST "${{ secrets.SLACK_WEBHOOK }}" \
              -H 'Content-type: application/json' \
              -d "{\"text\":\"🔴 Security Alert: $CRITICAL critical, $HIGH high vulnerabilities found in dependencies\"}"
          fi

      - name: Trivy scan
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: '.'
          severity: 'HIGH,CRITICAL'
          format: 'json'
          output: 'trivy-results.json'
```

#### RSS Feed Aggregation Script

```typescript
// cve-monitor.ts — Runs as a scheduled NestJS cron job
import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import Parser from 'rss-parser';

interface CVEFeed {
  name: string;
  url: string;
  keywords: string[];
}

const FEEDS: CVEFeed[] = [
  {
    name: 'NVD Recent',
    url: 'https://nvd.nist.gov/feeds/xml/cve/misc/nvd-rss-analyzed.xml',
    keywords: ['node', 'javascript', 'typescript', 'docker', 'kubernetes', 'redis', 'postgresql', 'nginx'],
  },
  {
    name: 'Node.js Blog',
    url: 'https://nodejs.org/en/feed/vulnerability.xml',
    keywords: ['security', 'vulnerability', 'cve'],
  },
];

@Injectable()
export class CVEMonitorService {
  private readonly logger = new Logger(CVEMonitorService.name);
  private readonly parser = new Parser();

  @Cron(CronExpression.EVERY_DAY_AT_8AM)
  async checkFeeds(): Promise<void> {
    for (const feed of FEEDS) {
      try {
        const parsed = await this.parser.parseURL(feed.url);
        const relevant = parsed.items.filter((item) =>
          feed.keywords.some((kw) =>
            (item.title + item.contentSnippet)?.toLowerCase().includes(kw),
          ),
        );

        if (relevant.length > 0) {
          this.logger.warn(
            `[${feed.name}] Found ${relevant.length} relevant items`,
          );
          // Send to notification service / create Lobster pipeline task
          for (const item of relevant) {
            await this.notifyTeam({
              source: feed.name,
              title: item.title ?? 'Unknown',
              link: item.link ?? '',
              published: item.pubDate ?? '',
            });
          }
        }
      } catch (error) {
        this.logger.error(`Failed to fetch ${feed.name}: ${error}`);
      }
    }
  }

  private async notifyTeam(alert: {
    source: string;
    title: string;
    link: string;
    published: string;
  }): Promise<void> {
    // Integration point: Slack webhook, email, or Lobster pipeline task
    this.logger.warn(`SECURITY ALERT: [${alert.source}] ${alert.title} — ${alert.link}`);
  }
}
```

---

### 3.5 Decision Template: When a New Vulnerability Requires Design Change

```markdown
# CVE Impact Assessment — [CVE-YYYY-NNNNN]

## Summary
| Field          | Value                                    |
|----------------|------------------------------------------|
| CVE ID         | CVE-YYYY-NNNNN                           |
| CVSS Score     | X.X (Critical/High/Medium/Low)           |
| Affected Component | [package@version / service / runtime] |
| Published      | YYYY-MM-DD                               |
| Exploit Available | Yes / No / PoC                        |

## Impact on GateForge
- [ ] Is the vulnerable component used in GateForge? → If No, close.
- [ ] Is the vulnerability reachable in our usage? → If No, document and monitor.
- [ ] What is the blast radius? (Which services, data, users affected?)
- [ ] Is there a patch available?
- [ ] Does the patch require a design change?

## Action Plan
| Action                          | Owner      | Deadline   | Status |
|---------------------------------|------------|------------|--------|
| Update dependency to patched version | Dev team | +24h     | ⬜     |
| Test patch in UAT               | QC team    | +48h       | ⬜     |
| Update container base image     | DevOps     | +24h       | ⬜     |
| Design change (if needed)       | Designer   | +72h       | ⬜     |
| Blueprint update proposal       | Designer   | +72h       | ⬜     |
| Production deployment           | Operator   | After QC   | ⬜     |

## Design Change Required?
- [ ] **No** — Dependency update only (patch version bump)
- [ ] **Minor** — Configuration change (e.g., disable a feature, add a header)
- [ ] **Major** — Architectural change (e.g., replace a library, change auth flow)

If Major: Submit design change as new TASK to System Architect.
```

---

### 3.6 CVE Severity Assessment Criteria

The [Common Vulnerability Scoring System (CVSS)](https://www.crowdstrike.com/en-us/cybersecurity-101/exposure-management/common-vulnerability-scoring-system-cvss/) provides a standardized severity score:

| CVSS Score | Severity   | GateForge SLA          |
|------------|------------|------------------------|
| 9.0–10.0   | **Critical** | Fix within 24 hours   |
| 7.0–8.9    | **High**     | Fix within 7 days     |
| 4.0–6.9    | **Medium**   | Fix within 30 days    |
| 0.1–3.9    | **Low**      | Fix within 90 days    |
| 0.0        | **None**     | No action required     |

**CVSS Base Metrics to evaluate:**

| Metric | Question | Impact on Score |
|--------|----------|-----------------|
| Attack Vector (AV) | Network / Adjacent / Local / Physical? | Network = highest |
| Attack Complexity (AC) | Low / High? | Low = higher score |
| Privileges Required (PR) | None / Low / High? | None = highest |
| User Interaction (UI) | None / Required? | None = highest |
| Scope (S) | Changed / Unchanged? | Changed = higher |
| Confidentiality (C) | None / Low / High? | High = highest |
| Integrity (I) | None / Low / High? | High = highest |
| Availability (A) | None / Low / High? | High = highest |

Source: [CyCognito — CVSS Scoring](https://www.cycognito.com/learn/vulnerability-management/cvss-scoring/)

---

### 3.7 Example Workflow: CVE → Design Revision

```
Day 0: CVE-2026-12345 published — Critical RCE in express@4.19.0
  │
  ├── Daily CVE monitor picks up from NVD RSS feed
  ├── npm audit flags HIGH vulnerability
  └── Trivy container scan fails in CI/CD
  │
Day 0 (+2h): Impact Assessment
  ├── GateForge API uses express@4.19.0 ✅ (affected)
  ├── Vulnerability is reachable via HTTP request ✅
  ├── CVSS 9.8 — Critical, network-exploitable
  └── Patch available: express@4.19.1
  │
Day 0 (+4h): Containment
  ├── WAF rule deployed to block exploit pattern
  └── Rate limiting tightened on affected endpoints
  │
Day 0 (+8h): Fix
  ├── Dependency updated: express@4.19.1
  ├── Trivy scan passes
  ├── npm audit clean
  └── Container image rebuilt
  │
Day 1: Deployment
  ├── Deployed to UAT, QC verification passes
  ├── Canary deployment to production (10%)
  └── Full rollout after 2-hour observation
  │
Day 2: Post-Incident
  ├── Post-mortem written
  ├── No design change needed (dependency patch only)
  └── Blueprint not affected — close ticket
```

---

## 4. Database Resilience Design

### 4.1 PostgreSQL HA Patterns

#### Architecture Comparison

| Strategy | RPO | RTO | Complexity | Best For |
|----------|-----|-----|------------|----------|
| Backup restore (pg_basebackup) | Hours | Hours | Low | Dev/staging |
| Async streaming replication + manual failover | Seconds–minutes | 5–30 min | Medium | Budget-constrained |
| Sync streaming replication + manual failover | Zero | 5–30 min | Medium | Data-critical, small team |
| **Patroni (async)** | Seconds | 10–30 sec | High | **Production standard** |
| **Patroni (sync)** | Zero | 10–30 sec | High | **Financial/critical data** |
| pg_auto_failover | Configurable | 10–30 sec | Medium | Simpler alternative to Patroni |

Source: [DEV Community — PostgreSQL HA: Patroni, Replication and Failover](https://dev.to/philip_mcclarence_2ef9475/postgresql-high-availability-patroni-replication-and-failover-patterns-4f6k)

**GateForge recommendation: Patroni with async replication** for standard services, **Patroni with sync replication** for payment/auth data.

#### Patroni Configuration

```yaml
# patroni.yml — GateForge PostgreSQL HA
scope: gateforge-db
namespace: /gateforge/
name: pg-node1

restapi:
  listen: 0.0.0.0:8008
  connect_address: 10.0.1.30:8008

etcd3:
  hosts: 10.0.1.40:2379,10.0.1.41:2379,10.0.1.42:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576   # 1 MB — won't promote a lagging replica
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        max_wal_senders: 10
        max_replication_slots: 10
        wal_keep_size: 1GB
        hot_standby_feedback: "on"
        max_connections: 200
        shared_buffers: 2GB
        effective_cache_size: 6GB
        work_mem: 64MB
        maintenance_work_mem: 512MB
        wal_log_hints: "on"           # Required for pg_rewind
        archive_mode: "on"
        archive_command: 'wal-g wal-push %p'
        archive_timeout: 300

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator Tailscale VPN (100.x.x.x) scram-sha-256
    - host all all Tailscale VPN (100.x.x.x) scram-sha-256

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 10.0.1.30:5432
  data_dir: /var/lib/postgresql/16/main
  authentication:
    replication:
      username: replicator
      password: "${REPLICATION_PASSWORD}"
    superuser:
      username: postgres
      password: "${POSTGRES_PASSWORD}"
    rewind:
      username: postgres
      password: "${POSTGRES_PASSWORD}"
  parameters:
    unix_socket_directories: '/var/run/postgresql'
  create_replica_methods:
    - basebackup
  basebackup:
    max-rate: '100M'
    checkpoint: 'fast'

tags:
  nofailover: false
  noloadbalance: false
```

Source: [OneUptime — PostgreSQL Patroni HA](https://oneuptime.com/blog/post/2026-01-21-postgresql-patroni-ha/view)

---

### 4.2 Connection Pooling (PgBouncer)

PgBouncer sits between the application and PostgreSQL, managing connection pooling and providing failover routing ([GitLab Docs — PostgreSQL Replication and Failover](https://docs.gitlab.com/administration/postgresql/replication_and_failover/)).

```ini
# pgbouncer.ini — GateForge configuration
[databases]
gateforge_production = host=127.0.0.1 port=5432 dbname=gateforge_production
gateforge_production_readonly = host=pg-replica-1 port=5432 dbname=gateforge_production

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt

; Connection pooling settings
pool_mode = transaction          ; Best for most web apps
default_pool_size = 20           ; Connections per user/database pair
min_pool_size = 5                ; Keep minimum connections warm
reserve_pool_size = 5            ; Extra connections for burst
reserve_pool_timeout = 3         ; Seconds before using reserve pool

; Timeouts
server_connect_timeout = 5       ; Connection timeout to PostgreSQL
server_idle_timeout = 600        ; Close idle server connections after 10 min
server_lifetime = 3600           ; Reconnect to server after 1 hour
client_idle_timeout = 300        ; Close idle client connections after 5 min
query_timeout = 30               ; Kill queries running > 30 seconds

; Limits
max_client_conn = 1000           ; Maximum client connections
max_db_connections = 100         ; Maximum connections per database

; Logging
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
stats_period = 60
```

#### Connection Pool Sizing Formula

```
optimal_pool_size = (core_count * 2) + effective_spindle_count
```

For GateForge (8-core server, SSD):

```
optimal_pool_size = (8 * 2) + 1 = 17 ≈ 20
```

---

### 4.3 Backup Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                    BACKUP STRATEGY                                │
│                                                                   │
│  ┌─────────┐    Continuous    ┌──────────┐    Daily    ┌───────┐ │
│  │ Primary │ ──── WAL ────▶  │ WAL      │ ──────────▶ │  S3   │ │
│  │ PG Node │    Shipping     │ Archive  │  Base       │Bucket │ │
│  └─────────┘                 └──────────┘  Backup     └───────┘ │
│                                                                   │
│  RPO: ~5 minutes (archive_timeout = 300s)                        │
│  RTO: < 30 minutes (base backup + WAL replay)                   │
│  Retention: 30 days of base backups + WAL                        │
└─────────────────────────────────────────────────────────────────┘
```

#### WAL Archiving Configuration

```sql
-- postgresql.conf additions for WAL archiving
wal_level = replica
archive_mode = on
archive_command = 'wal-g wal-push %p'
archive_timeout = 300            -- Force archive every 5 minutes
max_wal_senders = 3
max_replication_slots = 3
```

Source: [OneUptime — PostgreSQL PITR with WAL-G](https://oneuptime.com/blog/post/2026-02-09-postgresql-pitr-walg-kubernetes/view)

#### Automated Base Backup (Kubernetes CronJob)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pg-base-backup
  namespace: production
spec:
  schedule: "0 2 * * *"        # Daily at 02:00 UTC
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: ghcr.io/gateforge/pg-backup:16
              command:
                - bash
                - -c
                - |
                  echo "Starting base backup..."
                  wal-g backup-push /var/lib/postgresql/data/pgdata
                  echo "Backup completed. Listing backups:"
                  wal-g backup-list
                  # Retain last 30 backups
                  wal-g delete retain 30 --confirm
              env:
                - name: WALG_S3_PREFIX
                  value: s3://gateforge-backups/pg-wal-archive
                - name: AWS_REGION
                  value: us-east-1
                - name: PGDATA
                  value: /var/lib/postgresql/data/pgdata
                - name: PGHOST
                  value: /var/run/postgresql
              volumeMounts:
                - name: data
                  mountPath: /var/lib/postgresql/data
          restartPolicy: OnFailure
          volumes:
            - name: data
              persistentVolumeClaim:
                claimName: data-postgres-primary-0
```

#### Point-in-Time Recovery Procedure

```bash
# 1. Stop the target PostgreSQL instance
pg_ctl -D $PGDATA stop

# 2. Restore the latest base backup
wal-g backup-fetch $PGDATA LATEST

# 3. Create recovery signal file
touch $PGDATA/recovery.signal

# 4. Configure recovery target
cat > $PGDATA/postgresql.auto.conf <<EOF
restore_command = 'wal-g wal-fetch %f %p'
recovery_target_time = '2026-04-07 00:30:00+08'   # Recover to this point
recovery_target_action = 'promote'
EOF

# 5. Start PostgreSQL — it will replay WAL to target time
pg_ctl -D $PGDATA start

# 6. Verify recovery
psql -c "SELECT pg_is_in_recovery();"  -- Should return 'false' after promotion
```

---

### 4.4 Redis HA Configuration

#### Sentinel vs Cluster Decision Criteria

| Criterion                            | Sentinel  | Cluster   |
|--------------------------------------|-----------|-----------|
| Data fits in single node memory      | ✅        | ✅        |
| Data exceeds single node memory      | ❌        | ✅        |
| Write scaling needed                 | ❌        | ✅ (multi-master) |
| Multi-key transactions (MULTI/EXEC)  | ✅        | ⚠️ (same hash slot only) |
| Operational complexity               | Low–Med   | High      |
| Minimum node count                   | 3 Sentinel + 1M + 1R = 5 | 6 (3M + 3R) |
| Pub/Sub across all data              | ✅        | ⚠️ (shard-local by default) |
| Best for                             | Session, cache, small datasets | Large-scale data + HA |

Source: [Baeldung — Redis Sentinel vs Clustering](https://www.baeldung.com/redis-sentinel-vs-clustering)

**GateForge recommendation:** Start with **Sentinel** for session/cache. Migrate to **Cluster** only if data exceeds single-node memory or write throughput requires sharding.

#### Redis Persistence Configuration

```
# Hybrid persistence (recommended for GateForge)
# RDB: periodic snapshots for fast restart
# AOF: append-only file for durability

# RDB settings
save 900 1         # Snapshot if ≥1 write in 900 seconds
save 300 10        # Snapshot if ≥10 writes in 300 seconds
save 60 10000      # Snapshot if ≥10000 writes in 60 seconds
rdbcompression yes
rdbchecksum yes

# AOF settings
appendonly yes
appendfsync everysec         # Fsync every second (best balance)
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Memory management
maxmemory 2gb
maxmemory-policy allkeys-lru   # LRU eviction for cache use case
```

| Persistence Mode | Durability | Performance | Recovery Speed | Best For |
|---|---|---|---|---|
| RDB only | Low (data since last snapshot lost) | High | Fast | Cache-only |
| AOF only | High (< 1 sec data loss with `everysec`) | Medium | Slow (replay) | Critical data |
| **RDB + AOF (hybrid)** | **High** | **Medium** | **Fast** | **Production default** |

---

### 4.5 Database Failover Testing Checklist

Run these tests **monthly** and before any major release:

- [ ] **Planned switchover**: `patronictl switchover` completes in < 30 seconds
- [ ] **Simulate primary failure**: `systemctl stop postgresql` on primary → replica promotes automatically
- [ ] **Replication lag**: Verify lag < 1 MB during normal operations (`pg_stat_replication`)
- [ ] **PgBouncer reconnect**: After failover, PgBouncer routes to new primary within `server_login_retry` period
- [ ] **Application reconnect**: NestJS app reconnects and resumes operations without manual intervention
- [ ] **Old primary rejoin**: After recovery, old primary can rejoin as replica via `pg_rewind`
- [ ] **WAL archiving**: Verify WAL files are being archived to S3 continuously
- [ ] **PITR test**: Restore from backup to a specific point in time on a separate instance
- [ ] **Redis Sentinel failover**: Kill master → Sentinel promotes replica in < 10 seconds
- [ ] **Redis data integrity**: Verify no data loss after failover (for AOF-enabled instances)

---

### 4.6 Data Integrity Validation After Failover

```sql
-- PostgreSQL: Verify data checksums
SELECT datname, checksum_failures, checksum_last_failure
FROM pg_stat_database
WHERE checksum_failures > 0;

-- Verify replication status on new primary
SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
       (sent_lsn - replay_lsn) AS replication_lag_bytes
FROM pg_stat_replication;

-- Verify timeline after promotion
SELECT timeline_id, pg_current_wal_lsn();

-- Application-level integrity check
SELECT COUNT(*) FROM critical_table WHERE updated_at > NOW() - INTERVAL '5 minutes';
```

```bash
# Redis: Verify data integrity after failover
redis-cli -h new-master -a $REDIS_PASSWORD INFO replication
redis-cli -h new-master -a $REDIS_PASSWORD DBSIZE
redis-cli -h new-master -a $REDIS_PASSWORD DEBUG OBJECT some_critical_key
```

---

## 5. Kubernetes Resilience Configuration

### 5.1 Pod Disruption Budgets (PDB)

PDBs prevent voluntary disruptions (node drains, rolling updates) from taking down too many pods simultaneously ([OneUptime — PDB Strategies](https://oneuptime.com/blog/post/2026-01-30-kubernetes-pdb-strategies/view)).

```yaml
# PDB for stateless API service (4 replicas)
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: gateforge-api-pdb
  namespace: production
spec:
  maxUnavailable: 1     # At most 1 pod down during disruption
  selector:
    matchLabels:
      app: gateforge-api

---
# PDB for PostgreSQL StatefulSet (3 replicas, quorum-based)
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: postgres-pdb
  namespace: production
spec:
  minAvailable: 2       # Maintain quorum (n/2 + 1 for n=3)
  selector:
    matchLabels:
      app: postgres

---
# PDB for Redis Sentinel (3 sentinels)
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: redis-sentinel-pdb
  namespace: production
spec:
  minAvailable: 2       # Maintain sentinel quorum
  selector:
    matchLabels:
      app: redis-sentinel
```

#### PDB Strategy Matrix

| Workload Type                 | Strategy        | Value               | Rationale                           |
|-------------------------------|-----------------|---------------------|-------------------------------------|
| Stateless web (4+ replicas)   | maxUnavailable  | 1 or 25%            | Allow rolling updates               |
| HPA-managed (5–50 pods)       | maxUnavailable  | 20%                 | Scale-aware                         |
| Database cluster (3 replicas) | minAvailable    | 2 (quorum = n/2+1)  | Maintain write quorum               |
| Singleton (1 replica)         | maxUnavailable  | 0                   | Prevent any disruption              |
| Message queue (3 replicas)    | minAvailable    | 2                   | Maintain message durability         |

**Key rule:** `PDB minAvailable` must be **less than** `HPA minReplicas` to always allow at least one disruption.

---

### 5.2 Horizontal Pod Autoscaler (HPA)

```yaml
# hpa-api.yaml — GateForge API autoscaler
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: gateforge-api-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: gateforge-api
  minReplicas: 3
  maxReplicas: 20
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60     # Wait 60s before scaling up
      policies:
        - type: Percent
          value: 100                      # Double pods
          periodSeconds: 60
        - type: Pods
          value: 4                        # Add up to 4 pods
          periodSeconds: 60
      selectPolicy: Max
    scaleDown:
      stabilizationWindowSeconds: 300    # Wait 5 min before scaling down
      policies:
        - type: Percent
          value: 25                       # Remove 25% of pods
          periodSeconds: 120
      selectPolicy: Min                   # Conservative scale-down
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
    # Custom metric: request latency P99
    - type: Pods
      pods:
        metric:
          name: http_request_duration_seconds_p99
        target:
          type: AverageValue
          averageValue: "500m"             # 500ms P99 threshold
```

---

### 5.3 Resource Quotas and Limit Ranges

```yaml
# resource-quota.yaml — Production namespace limits
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "20"
    requests.memory: 40Gi
    limits.cpu: "40"
    limits.memory: 80Gi
    pods: "100"
    persistentvolumeclaims: "20"
    services: "30"
    services.loadbalancers: "5"

---
# limit-range.yaml — Default and max resource limits per container
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: production
spec:
  limits:
    - type: Container
      default:           # Applied if no limits specified
        cpu: "500m"
        memory: 512Mi
      defaultRequest:    # Applied if no requests specified
        cpu: "100m"
        memory: 128Mi
      max:               # Hard ceiling
        cpu: "2"
        memory: 4Gi
      min:               # Minimum allocation
        cpu: "50m"
        memory: 64Mi
    - type: Pod
      max:
        cpu: "4"
        memory: 8Gi
```

---

### 5.4 Readiness Gates for Zero-Downtime Deployments

```yaml
# deployment-rolling.yaml — Zero-downtime rolling update strategy
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gateforge-api
  namespace: production
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1              # Create 1 extra pod during update
      maxUnavailable: 0        # Never reduce below current count
  template:
    metadata:
      labels:
        app: gateforge-api
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - name: api
          image: ghcr.io/gateforge/api:1.0.0
          ports:
            - containerPort: 3000
          # Startup probe: allow up to 120s for initialization
          startupProbe:
            httpGet:
              path: /health/startup
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 12
          # Readiness probe: only route traffic when ready
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 3
          # Liveness probe: restart if deadlocked
          livenessProbe:
            httpGet:
              path: /health/live
              port: 3000
            initialDelaySeconds: 15
            periodSeconds: 10
            failureThreshold: 3
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 5"]  # Allow in-flight requests to drain
```

---

### 5.5 Rolling Update Strategy Configuration

| Parameter          | Stateless API | StatefulSet (DB) | Background Worker |
|--------------------|---------------|------------------|-------------------|
| `maxSurge`         | 1 (25%)       | N/A (ordered)    | 1                 |
| `maxUnavailable`   | 0             | N/A              | 1                 |
| `terminationGracePeriodSeconds` | 30 | 120          | 60                |
| `minReadySeconds`  | 10            | 30               | 5                 |

---

### 5.6 Node Affinity and Anti-Affinity Rules

```yaml
# Spread API pods across availability zones and nodes
spec:
  affinity:
    # Prefer different nodes for resilience
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchLabels:
                app: gateforge-api
            topologyKey: kubernetes.io/hostname
      # Require different zones for critical services
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app: gateforge-api
              tier: critical
          topologyKey: topology.kubernetes.io/zone

    # Place pods on specific node types
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: node-type
                operator: In
                values:
                  - application
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 80
          preference:
            matchExpressions:
              - key: topology.kubernetes.io/zone
                operator: In
                values:
                  - us-east-1a
                  - us-east-1b
```

Source: [Growin — Resilient Backends with Kubernetes](https://www.growin.com/blog/resilient-backends-kubernetes-2025/)

---

### 5.7 Priority Classes for Critical Services

```yaml
# priority-classes.yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: gateforge-critical
value: 1000000
globalDefault: false
description: "Critical services: API gateway, auth, database proxies"

---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: gateforge-standard
value: 500000
globalDefault: true
description: "Standard workloads: CRUD services, workers"

---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: gateforge-low
value: 100000
globalDefault: false
description: "Low priority: batch jobs, analytics, log processors"
```

Usage in deployment:

```yaml
spec:
  template:
    spec:
      priorityClassName: gateforge-critical
```

| Priority Class        | Value     | Services                                |
|-----------------------|-----------|-----------------------------------------|
| `gateforge-critical`  | 1 000 000 | API gateway, auth service, DB proxies   |
| `gateforge-standard`  | 500 000   | CRUD APIs, business logic services      |
| `gateforge-low`       | 100 000   | Batch jobs, analytics, log processors   |

---

## 6. Design Review Checklist

The System Designer **must** verify every item below before submitting any design deliverable to the System Architect (VM-1). This checklist is the quality gate for all design outputs.

### 6.1 Architecture & Resilience

- [ ] Service boundaries clearly defined (DDD bounded contexts)
- [ ] API contracts specified (OpenAPI 3.x with JSON Schema validation)
- [ ] Circuit breaker configured for all external dependencies (Section 1.1)
- [ ] Retry policy defined with exponential backoff + jitter (Section 1.2)
- [ ] Bulkhead pattern applied for resource isolation (Section 1.3)
- [ ] Timeout values documented for all service calls (Section 1.4)
- [ ] Fallback strategies defined for each failure mode (Section 1.5)
- [ ] Rate limiting configured for public and auth endpoints (Section 1.6)
- [ ] Health probes (liveness, readiness, startup) implemented (Section 1.7)
- [ ] Resilience pattern selection justified per decision matrix (Section 1.8)

### 6.2 Database

- [ ] PostgreSQL HA topology documented (primary + replicas) (Section 4.1)
- [ ] Connection pooling configured (PgBouncer) (Section 4.2)
- [ ] Backup strategy defined (WAL archiving + base backups) (Section 4.3)
- [ ] Point-in-time recovery procedure documented and tested (Section 4.3)
- [ ] Redis HA mode selected and justified (Sentinel vs Cluster) (Section 4.4)
- [ ] Database migrations are reversible (up/down)
- [ ] Indexing strategy documented for query patterns
- [ ] Data retention and archival policy defined

### 6.3 Security (Mandatory for Every Deliverable)

- [ ] Security assessment checklist completed (Section 2.1)
- [ ] OWASP ASVS Level 2 requirements mapped (Section 2.2)
- [ ] Security headers configured via Helmet.js (Section 2.3)
- [ ] TLS 1.3 enforced with cert-manager rotation (Section 2.4)
- [ ] NetworkPolicies defined (default-deny + explicit allows) (Section 2.5)
- [ ] Secrets management path documented (Sealed Secrets / Vault) (Section 2.6)
- [ ] Container hardening applied (non-root, read-only FS, dropped capabilities) (Section 2.7)
- [ ] Dependency scanning pipeline configured (npm audit + Trivy) (Section 2.8)
- [ ] STRIDE threat model completed for new services (Section 2.11)
- [ ] Security score ≥ 75 (Section 2.10)

### 6.4 Kubernetes

- [ ] PodDisruptionBudgets defined for all deployments (Section 5.1)
- [ ] HPA configured with appropriate metrics and scale-down stabilization (Section 5.2)
- [ ] Resource quotas and limit ranges set for namespace (Section 5.3)
- [ ] Zero-downtime deployment strategy configured (Section 5.4)
- [ ] Pod anti-affinity rules spread pods across nodes/zones (Section 5.6)
- [ ] Priority classes assigned appropriately (Section 5.7)

### 6.5 Rollback Strategy (Mandatory for Every Deliverable)

- [ ] Rollback procedure documented step-by-step
- [ ] Database migration has a tested `down` migration
- [ ] Previous container image tag recorded for instant rollback
- [ ] Feature flags available to disable new functionality without redeployment
- [ ] Rollback tested in UAT before production deployment
- [ ] Rollback time target documented (< 5 minutes for critical services)

### 6.6 Performance Impact Assessment

- [ ] Expected request volume documented (peak RPS)
- [ ] Latency targets defined (P50, P95, P99)
- [ ] Resource requirements estimated (CPU, memory, storage)
- [ ] Load test plan defined for new endpoints
- [ ] Database query performance assessed (EXPLAIN ANALYZE for new queries)
- [ ] Cache strategy defined (TTL, invalidation, warm-up)

### 6.7 Observability

- [ ] Prometheus metrics exported for key operations
- [ ] Grafana dashboard defined or updated
- [ ] Structured JSON logging with correlation IDs
- [ ] Alert rules defined for SLI/SLO thresholds
- [ ] Distributed tracing spans for cross-service calls

### 6.8 Cross-References to Blueprint

- [ ] Design references specific Blueprint sections
- [ ] Proposed changes to `architecture.md` documented
- [ ] Dependencies on other tasks noted (`TASK-YYY`)
- [ ] Estimated effort classified (S/M/L/XL)
- [ ] Feature branch created: `design/TASK-XXX-description`

---

## Appendix A: Quick Reference — Resilience Defaults

| Parameter                        | Default Value              |
|----------------------------------|----------------------------|
| Circuit breaker error threshold  | 50%                        |
| Circuit breaker reset timeout    | 30 000 ms                  |
| Retry max attempts               | 5                          |
| Retry base delay                 | 1 000 ms                   |
| Retry max delay                  | 30 000 ms                  |
| Bulkhead max concurrent (DB)     | 20                         |
| Global HTTP timeout              | 30 000 ms                  |
| Database query timeout           | 10 000 ms                  |
| Redis command timeout            | 3 000 ms                   |
| Health check interval            | 10 s (liveness), 5 s (readiness) |
| HPA min replicas                 | 3                          |
| HPA max replicas                 | 20                         |
| HPA CPU target                   | 70%                        |
| PDB maxUnavailable (API)         | 1                          |
| PDB minAvailable (DB)            | 2                          |
| Rate limit (general API)         | 100 req/min                |
| Rate limit (auth)                | 5 req/15 min               |

---

## Appendix B: Tool & Library Reference

| Tool / Library       | Purpose                          | Version | Link |
|----------------------|----------------------------------|---------|------|
| Opossum              | Circuit breaker for Node.js      | 8.x     | [GitHub](https://github.com/nodeshift/opossum) |
| nestjs-resilience    | NestJS resilience patterns       | Latest  | [npm](https://npmjs.com/package/nestjs-resilience) |
| Helmet.js            | Security headers middleware      | 7.x     | [helmetjs.github.io](https://helmetjs.github.io/) |
| @nestjs/terminus     | Health checks                    | 10.x    | [NestJS Docs](https://docs.nestjs.com/recipes/terminus) |
| class-validator      | Input validation DTOs            | 0.14.x  | [GitHub](https://github.com/typestack/class-validator) |
| Trivy                | Container & dependency scanner   | Latest  | [trivy.dev](https://trivy.dev/) |
| kubeseal             | Sealed Secrets CLI               | Latest  | [GitHub](https://github.com/bitnami-labs/sealed-secrets) |
| Patroni              | PostgreSQL HA orchestration      | 3.x     | [GitHub](https://github.com/zalando/patroni) |
| PgBouncer            | Connection pooler                | 1.22.x  | [pgbouncer.org](https://www.pgbouncer.org/) |
| WAL-G                | PostgreSQL backup tool           | 3.x     | [GitHub](https://github.com/wal-g/wal-g) |
| cert-manager         | TLS certificate automation       | 1.14.x  | [cert-manager.io](https://cert-manager.io/) |
| Prometheus           | Metrics collection               | 2.x     | [prometheus.io](https://prometheus.io/) |
| Grafana              | Metrics visualization            | 10.x    | [grafana.com](https://grafana.com/) |
| ioredis              | Redis client for Node.js         | 5.x     | [GitHub](https://github.com/redis/ioredis) |

---

## Appendix C: Related Documents

| Document                    | Location                                     | Owner             |
|-----------------------------|----------------------------------------------|-------------------|
| Blueprint (Master)          | `blueprint.md`                               | System Architect  |
| Architecture                | `architecture.md`                            | System Architect  |
| Coding Standards            | `coding-standards.md`                        | System Architect  |
| SOUL Configuration          | `openclaw-configs/vm-2-designer/SOUL.md`     | the end-user           |
| Infrastructure Designs      | `infrastructure/`                            | System Designer   |
| This Guide                  | `openclaw-configs/vm-2-designer/RESILIENCE-SECURITY-GUIDE.md` | the end-user |

---

---

## Appendix: Managed Output Documents

The System Designer is responsible for producing and maintaining the following documents in the Blueprint repository's `design/` directory.

### Document Ownership Map

| Document | Path in Blueprint Repo | When to Create | When to Update |
|----------|----------------------|----------------|----------------|
| Infrastructure Design | `design/infrastructure-design.md` | When Architect dispatches infrastructure task | When K8s, Docker, CI/CD, or network design changes |
| Security Design | `design/security-design.md` | At project start (mandatory) | After every security assessment, new threat, or penetration test |
| Resilience Design | `design/resilience-design.md` | When Architect dispatches resilience task | When patterns, failover, or HA configuration changes |
| Database Design | `design/database-design.md` | When data model is defined | When schema, indexes, replication, or Redis topology changes |
| Monitoring Design | `design/monitoring-design.md` | During infrastructure design | When metrics, dashboards, alerts, or SLIs change |

### Output Rules

1. **Every design document must include**: Rollback strategy, security assessment, change log
2. **Use the templates** from `gateforge-blueprint-template/design/` (`tonylnng/gateforge-blueprint-template`, read-only) — do not invent new formats
3. **Include Mermaid diagrams** for all architecture visualisations
4. **Structured report to Architect**: After completing any design document, produce a JSON report:

```json
{
  "taskId": "TASK-NNN",
  "type": "design",
  "status": "completed",
  "documentsUpdated": ["design/infrastructure-design.md", "design/security-design.md"],
  "securityAssessment": "included",
  "rollbackStrategy": "included",
  "proposedBlueprintChanges": ["architecture/technical-architecture.md#section-3"],
  "openQuestions": [],
  "reviewRequired": true
}
```

5. **Git commit convention**: `docs(design): <description>` (e.g., `docs(design): add K8s namespace isolation policy`)

---

*End of document. This guide must be reviewed and updated monthly by the System Designer agent. All changes require approval from the System Architect (VM-1).*
