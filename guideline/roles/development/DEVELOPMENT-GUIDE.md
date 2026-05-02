# Development Standards & Best Practices — GateForge Methodology

> **Class B — Methodology.** This guide is variant-agnostic. For variant-specific runtime deltas, read the active adaptation file:
>
> - Multi-agent: [`../../adaptation/MULTI-AGENT-ADAPTATION.md`](../../adaptation/MULTI-AGENT-ADAPTATION.md)
> - Single-agent: [`../../adaptation/SINGLE-AGENT-ADAPTATION.md`](../../adaptation/SINGLE-AGENT-ADAPTATION.md)


---

## Table of Contents

1. [Web Application Development Best Practices](#1-web-application-development-best-practices)
2. [Mobile App Development Best Practices](#2-mobile-app-development-best-practices)
3. [Coding Standards](#3-coding-standards)
4. [Application Logging Mechanism Guide](#4-application-logging-mechanism-guide)
5. [Developer Task Workflow](#5-developer-task-workflow)

---

## 1. Web Application Development Best Practices

### 1.1 NestJS Project Structure

GateForge backend services are built with [NestJS](https://docs.nestjs.com/), a progressive Node.js framework that leverages TypeScript and supports modular, testable architecture. Every microservice must follow this layered structure.

#### Core Building Blocks

| Building Block | Purpose | Decorator / Class |
|---|---|---|
| **Module** | Organizes related components into a cohesive block | `@Module()` |
| **Controller** | Handles incoming HTTP requests and returns responses | `@Controller()` |
| **Service** | Contains business logic, injected into controllers | `@Injectable()` |
| **DTO** | Defines the shape of data for request/response validation | Plain class + `class-validator` |
| **Guard** | Determines if a request should be handled (auth, roles) | `@Injectable()` + `CanActivate` |
| **Interceptor** | Transforms data before/after route handler execution | `@Injectable()` + `NestInterceptor` |
| **Pipe** | Transforms/validates input data before handler | `@Injectable()` + `PipeTransform` |
| **Filter** | Catches and handles exceptions globally or per-route | `@Catch()` + `ExceptionFilter` |

#### Microservices Folder Structure Convention

```
project-root/
├── apps/
│   ├── api-gateway/                  # HTTP gateway (public-facing)
│   │   ├── src/
│   │   │   ├── main.ts
│   │   │   ├── app.module.ts
│   │   │   ├── common/
│   │   │   │   ├── guards/
│   │   │   │   │   ├── jwt-auth.guard.ts
│   │   │   │   │   └── roles.guard.ts
│   │   │   │   ├── interceptors/
│   │   │   │   │   ├── logging.interceptor.ts
│   │   │   │   │   ├── transform.interceptor.ts
│   │   │   │   │   └── timeout.interceptor.ts
│   │   │   │   ├── filters/
│   │   │   │   │   ├── all-exceptions.filter.ts
│   │   │   │   │   └── validation-exception.filter.ts
│   │   │   │   ├── pipes/
│   │   │   │   │   └── parse-uuid.pipe.ts
│   │   │   │   ├── decorators/
│   │   │   │   │   ├── current-user.decorator.ts
│   │   │   │   │   └── roles.decorator.ts
│   │   │   │   └── middleware/
│   │   │   │       ├── cors.middleware.ts
│   │   │   │       └── helmet.middleware.ts
│   │   │   └── modules/
│   │   │       ├── auth/
│   │   │       │   ├── auth.module.ts
│   │   │       │   ├── auth.controller.ts
│   │   │       │   ├── auth.service.ts
│   │   │       │   ├── dto/
│   │   │       │   │   ├── login.dto.ts
│   │   │       │   │   └── register.dto.ts
│   │   │       │   ├── strategies/
│   │   │       │   │   ├── jwt.strategy.ts
│   │   │       │   │   └── refresh-token.strategy.ts
│   │   │       │   └── auth.controller.spec.ts
│   │   │       └── users/
│   │   │           ├── users.module.ts
│   │   │           ├── users.controller.ts
│   │   │           ├── users.service.ts
│   │   │           ├── dto/
│   │   │           │   ├── create-user.dto.ts
│   │   │           │   └── update-user.dto.ts
│   │   │           ├── entities/
│   │   │           │   └── user.entity.ts
│   │   │           └── users.controller.spec.ts
│   │   └── tsconfig.app.json
│   │
│   ├── user-service/                 # Microservice: user domain
│   │   ├── src/
│   │   │   ├── main.ts
│   │   │   ├── user-service.module.ts
│   │   │   ├── user-service.controller.ts
│   │   │   ├── user-service.service.ts
│   │   │   ├── dto/
│   │   │   ├── entities/
│   │   │   └── repositories/
│   │   └── tsconfig.app.json
│   │
│   ├── order-service/                # Microservice: order domain
│   │   └── src/ ...
│   │
│   └── notification-service/         # Microservice: notifications
│       └── src/ ...
│
├── libs/                             # Shared libraries across services
│   ├── common/
│   │   ├── src/
│   │   │   ├── constants/
│   │   │   │   └── index.ts
│   │   │   ├── decorators/
│   │   │   ├── dto/
│   │   │   │   └── pagination.dto.ts
│   │   │   ├── enums/
│   │   │   ├── exceptions/
│   │   │   │   ├── app.exception.ts
│   │   │   │   └── business-error.codes.ts
│   │   │   ├── interfaces/
│   │   │   ├── types/
│   │   │   └── utils/
│   │   └── tsconfig.lib.json
│   └── database/
│       ├── src/
│       │   ├── database.module.ts
│       │   ├── migrations/
│       │   └── seeds/
│       └── tsconfig.lib.json
│
├── docker-compose.yml
├── nest-cli.json
├── package.json
├── tsconfig.json
└── .env.example
```

> **Rule:** Each microservice maps to a single bounded context (Domain-Driven Design). Services communicate via TCP transport, Redis, or message brokers — never by direct database sharing.  
> Reference: [Talent500 NestJS Microservices Guide](https://talent500.com/blog/nestjs-microservices-guide/), [Telerik NestJS Microservices](https://www.telerik.com/blogs/build-microservice-architecture-nestjs)

---

### 1.2 Dependency Injection Patterns in NestJS

NestJS uses a provider-based DI container. All injectable classes must be decorated with `@Injectable()` and registered in their module's `providers` array.

#### Standard Constructor Injection

```typescript
// users.service.ts
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User } from './entities/user.entity';

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User)
    private readonly userRepository: Repository<User>,
  ) {}

  /**
   * Find a user by their unique identifier.
   * @param id - The UUID of the user
   * @returns The user entity or null if not found
   * @throws NotFoundException if user does not exist
   */
  async findById(id: string): Promise<User | null> {
    return this.userRepository.findOne({ where: { id } });
  }
}
```

#### Custom Provider (Factory Pattern)

```typescript
// config.provider.ts
import { Provider } from '@nestjs/common';

export const DATABASE_CONFIG = 'DATABASE_CONFIG';

export const databaseConfigProvider: Provider = {
  provide: DATABASE_CONFIG,
  useFactory: () => ({
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432', 10),
    database: process.env.DB_NAME || 'gateforge',
  }),
};

// Usage in service:
@Injectable()
export class DatabaseService {
  constructor(
    @Inject(DATABASE_CONFIG)
    private readonly config: DatabaseConfig,
  ) {}
}
```

#### Async Provider (for external connections)

```typescript
// redis.provider.ts
export const REDIS_CLIENT = 'REDIS_CLIENT';

export const redisProvider: Provider = {
  provide: REDIS_CLIENT,
  useFactory: async (): Promise<Redis> => {
    const client = new Redis({
      host: process.env.REDIS_HOST,
      port: parseInt(process.env.REDIS_PORT || '6379', 10),
    });
    await client.ping();
    return client;
  },
};
```

**DI Checklist:**
- [ ] All services use `@Injectable()` decorator
- [ ] Dependencies are injected via constructor, never instantiated with `new`
- [ ] Use `@Inject()` for non-class tokens (strings, symbols)
- [ ] Module `exports` array includes any provider needed by other modules
- [ ] Circular dependencies are resolved with `forwardRef()`
- [ ] Use `@Optional()` for non-critical optional dependencies

---

### 1.3 API Design: RESTful Conventions

#### URL Structure

```
BASE_URL/api/v1/{resource}
```

| Method | Endpoint | Purpose | Status Code |
|--------|----------|---------|-------------|
| `GET` | `/api/v1/users` | List users (paginated) | `200 OK` |
| `GET` | `/api/v1/users/:id` | Get single user | `200 OK` |
| `POST` | `/api/v1/users` | Create user | `201 Created` |
| `PATCH` | `/api/v1/users/:id` | Partial update | `200 OK` |
| `PUT` | `/api/v1/users/:id` | Full replace | `200 OK` |
| `DELETE` | `/api/v1/users/:id` | Soft-delete user | `204 No Content` |

#### Versioning

Always version APIs with a URL prefix. Register versioned controllers:

```typescript
// main.ts
app.setGlobalPrefix('api');
app.enableVersioning({
  type: VersioningType.URI,
  defaultVersion: '1',
});

// users.controller.ts
@Controller({ path: 'users', version: '1' })
export class UsersControllerV1 { /* ... */ }

@Controller({ path: 'users', version: '2' })
export class UsersControllerV2 { /* ... */ }
```

#### Pagination, Filtering & Sorting

```typescript
// dto/pagination-query.dto.ts
import { IsOptional, IsPositive, IsInt, Min, Max, IsString, IsEnum } from 'class-validator';
import { Type } from 'class-transformer';

export enum SortOrder {
  ASC = 'ASC',
  DESC = 'DESC',
}

export class PaginationQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page: number = 1;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit: number = 20;

  @IsOptional()
  @IsString()
  sortBy?: string;

  @IsOptional()
  @IsEnum(SortOrder)
  sortOrder: SortOrder = SortOrder.DESC;

  @IsOptional()
  @IsString()
  search?: string;

  get skip(): number {
    return (this.page - 1) * this.limit;
  }
}
```

**Standard Paginated Response:**

```typescript
// interfaces/paginated-response.interface.ts
export interface PaginatedResponse<T> {
  data: T[];
  meta: {
    page: number;
    limit: number;
    totalItems: number;
    totalPages: number;
    hasNextPage: boolean;
    hasPreviousPage: boolean;
  };
}
```

Usage in a service:

```typescript
async findAll(query: PaginationQueryDto): Promise<PaginatedResponse<User>> {
  const [data, totalItems] = await this.userRepository.findAndCount({
    skip: query.skip,
    take: query.limit,
    order: query.sortBy ? { [query.sortBy]: query.sortOrder } : { createdAt: 'DESC' },
  });

  const totalPages = Math.ceil(totalItems / query.limit);

  return {
    data,
    meta: {
      page: query.page,
      limit: query.limit,
      totalItems,
      totalPages,
      hasNextPage: query.page < totalPages,
      hasPreviousPage: query.page > 1,
    },
  };
}
```

---

### 1.4 Error Handling

#### Standard Error Response Schema

All API errors must conform to this structure:

```json
{
  "statusCode": 400,
  "code": "VALIDATION_ERROR",
  "message": "One or more validation errors occurred",
  "errors": [
    { "field": "email", "message": "email must be a valid email address" }
  ],
  "timestamp": "2026-04-07T01:00:00.000Z",
  "path": "/api/v1/users",
  "traceId": "abc123-def456"
}
```

#### Custom Exception Classes

```typescript
// libs/common/src/exceptions/app.exception.ts
import { HttpException, HttpStatus } from '@nestjs/common';

export class AppException extends HttpException {
  public readonly code: string;
  public readonly details?: Record<string, unknown>;

  constructor(
    code: string,
    message: string,
    statusCode: HttpStatus = HttpStatus.INTERNAL_SERVER_ERROR,
    details?: Record<string, unknown>,
  ) {
    super({ message, code, details }, statusCode);
    this.code = code;
    this.details = details;
  }
}

// Concrete exception classes
export class EntityNotFoundException extends AppException {
  constructor(entity: string, id: string) {
    super(
      'ENTITY_NOT_FOUND',
      `${entity} with id '${id}' was not found`,
      HttpStatus.NOT_FOUND,
      { entity, id },
    );
  }
}

export class BusinessRuleViolationException extends AppException {
  constructor(rule: string, details?: Record<string, unknown>) {
    super(
      'BUSINESS_RULE_VIOLATION',
      rule,
      HttpStatus.UNPROCESSABLE_ENTITY,
      details,
    );
  }
}

export class DuplicateEntityException extends AppException {
  constructor(entity: string, field: string, value: string) {
    super(
      'DUPLICATE_ENTITY',
      `${entity} with ${field} '${value}' already exists`,
      HttpStatus.CONFLICT,
      { entity, field, value },
    );
  }
}
```

#### Global Exception Filter

Reference: [OneUptime — Custom Exception Filters in NestJS](https://oneuptime.com/blog/post/2026-01-25-custom-exception-filters-nestjs/view)

```typescript
// common/filters/all-exceptions.filter.ts
import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { AppException } from '@libs/common/exceptions/app.exception';

interface ErrorResponse {
  statusCode: number;
  code: string;
  message: string;
  errors?: Array<{ field: string; message: string }>;
  timestamp: string;
  path: string;
  traceId?: string;
}

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    const status = this.getStatus(exception);
    const errorResponse = this.buildErrorResponse(exception, request, status);

    // Log with appropriate severity
    if (status >= 500) {
      this.logger.error(
        `${request.method} ${request.url} — ${status}`,
        exception instanceof Error ? exception.stack : String(exception),
      );
    } else {
      this.logger.warn(`${request.method} ${request.url} — ${status}`);
    }

    response.status(status).json(errorResponse);
  }

  private getStatus(exception: unknown): number {
    if (exception instanceof HttpException) return exception.getStatus();
    return HttpStatus.INTERNAL_SERVER_ERROR;
  }

  private buildErrorResponse(
    exception: unknown,
    request: Request,
    status: number,
  ): ErrorResponse {
    const base: ErrorResponse = {
      statusCode: status,
      code: 'INTERNAL_ERROR',
      message: 'An unexpected error occurred',
      timestamp: new Date().toISOString(),
      path: request.url,
      traceId: request.headers['x-trace-id'] as string,
    };

    if (exception instanceof AppException) {
      base.code = exception.code;
      base.message = (exception.getResponse() as { message: string }).message;
    } else if (exception instanceof HttpException) {
      const res = exception.getResponse();
      base.code = `HTTP_${status}`;
      if (typeof res === 'string') {
        base.message = res;
      } else if (typeof res === 'object' && res !== null) {
        const obj = res as Record<string, unknown>;
        base.message = (obj.message as string) || base.message;
        if (Array.isArray(obj.message)) {
          base.errors = (obj.message as string[]).map((msg) => ({
            field: msg.split(' ')[0],
            message: msg,
          }));
          base.message = 'Validation failed';
          base.code = 'VALIDATION_ERROR';
        }
      }
    } else if (exception instanceof Error) {
      base.message = exception.message;
    }

    return base;
  }
}
```

**Registration in `main.ts`:**

```typescript
// main.ts
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });

  app.useGlobalFilters(new AllExceptionsFilter());

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: true },
    }),
  );

  await app.listen(3000);
}
bootstrap();
```

---

### 1.5 Validation: class-validator & DTO Design

#### DTO Design Principles

- One DTO per operation (`CreateUserDto`, `UpdateUserDto`, `UserResponseDto`)
- Use `PartialType`, `PickType`, `OmitType` from `@nestjs/mapped-types` for derivation
- Never expose entity models directly as API responses

```typescript
// dto/create-user.dto.ts
import {
  IsString,
  IsEmail,
  IsNotEmpty,
  MinLength,
  MaxLength,
  Matches,
  IsOptional,
  IsEnum,
} from 'class-validator';

export enum UserRole {
  ADMIN = 'admin',
  USER = 'user',
  MODERATOR = 'moderator',
}

export class CreateUserDto {
  @IsString()
  @IsNotEmpty()
  @MinLength(2)
  @MaxLength(50)
  readonly firstName: string;

  @IsString()
  @IsNotEmpty()
  @MinLength(2)
  @MaxLength(50)
  readonly lastName: string;

  @IsEmail()
  @IsNotEmpty()
  readonly email: string;

  @IsString()
  @MinLength(8)
  @MaxLength(128)
  @Matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]+$/, {
    message: 'Password must contain uppercase, lowercase, number, and special character',
  })
  readonly password: string;

  @IsOptional()
  @IsEnum(UserRole)
  readonly role?: UserRole = UserRole.USER;
}

// dto/update-user.dto.ts
import { PartialType, OmitType } from '@nestjs/mapped-types';
import { CreateUserDto } from './create-user.dto';

export class UpdateUserDto extends PartialType(
  OmitType(CreateUserDto, ['password'] as const),
) {}
```

#### Custom Validator Example

```typescript
// validators/is-unique.validator.ts
import {
  ValidatorConstraint,
  ValidatorConstraintInterface,
  ValidationArguments,
  registerDecorator,
  ValidationOptions,
} from 'class-validator';
import { Injectable } from '@nestjs/common';
import { DataSource } from 'typeorm';

@ValidatorConstraint({ async: true })
@Injectable()
export class IsUniqueConstraint implements ValidatorConstraintInterface {
  constructor(private readonly dataSource: DataSource) {}

  async validate(value: string, args: ValidationArguments): Promise<boolean> {
    const [entity, field] = args.constraints;
    const repository = this.dataSource.getRepository(entity);
    const record = await repository.findOne({ where: { [field]: value } });
    return !record;
  }

  defaultMessage(args: ValidationArguments): string {
    const [entity, field] = args.constraints;
    return `${entity} with this ${field} already exists`;
  }
}

export function IsUnique(entity: string, field: string, options?: ValidationOptions) {
  return function (object: object, propertyName: string) {
    registerDecorator({
      target: object.constructor,
      propertyName,
      options,
      constraints: [entity, field],
      validator: IsUniqueConstraint,
    });
  };
}
```

---

### 1.6 Database Access Patterns

#### TypeORM Repository Pattern

```typescript
// repositories/user.repository.ts
import { Injectable } from '@nestjs/common';
import { DataSource, Repository } from 'typeorm';
import { User } from '../entities/user.entity';

@Injectable()
export class UserRepository extends Repository<User> {
  constructor(private readonly dataSource: DataSource) {
    super(User, dataSource.createEntityManager());
  }

  async findByEmail(email: string): Promise<User | null> {
    return this.findOne({ where: { email }, relations: ['profile'] });
  }

  async findActiveUsers(page: number, limit: number): Promise<[User[], number]> {
    return this.findAndCount({
      where: { isActive: true },
      skip: (page - 1) * limit,
      take: limit,
      order: { createdAt: 'DESC' },
    });
  }
}
```

#### Transaction Pattern

```typescript
// services/order.service.ts
@Injectable()
export class OrderService {
  constructor(private readonly dataSource: DataSource) {}

  /**
   * Create an order with line items within a single transaction.
   * If any step fails, the entire operation is rolled back.
   * @param dto - The order creation data
   * @returns The created order with line items
   * @throws BusinessRuleViolationException if inventory is insufficient
   */
  async createOrder(dto: CreateOrderDto): Promise<Order> {
    return this.dataSource.transaction(async (manager) => {
      // 1. Create order header
      const order = manager.create(Order, {
        userId: dto.userId,
        status: OrderStatus.PENDING,
      });
      await manager.save(order);

      // 2. Create line items and decrement inventory
      for (const item of dto.items) {
        const product = await manager.findOne(Product, {
          where: { id: item.productId },
          lock: { mode: 'pessimistic_write' },
        });

        if (!product || product.stock < item.quantity) {
          throw new BusinessRuleViolationException(
            `Insufficient stock for product ${item.productId}`,
          );
        }

        product.stock -= item.quantity;
        await manager.save(product);

        const lineItem = manager.create(OrderLineItem, {
          orderId: order.id,
          productId: item.productId,
          quantity: item.quantity,
          unitPrice: product.price,
        });
        await manager.save(lineItem);
      }

      return manager.findOne(Order, {
        where: { id: order.id },
        relations: ['lineItems', 'lineItems.product'],
      });
    });
  }
}
```

#### Prisma Alternative Pattern

```typescript
// services/user.service.ts (Prisma)
@Injectable()
export class UserService {
  constructor(private readonly prisma: PrismaService) {}

  async createWithProfile(dto: CreateUserDto): Promise<User> {
    return this.prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          email: dto.email,
          firstName: dto.firstName,
          lastName: dto.lastName,
          passwordHash: await hashPassword(dto.password),
          profile: {
            create: { bio: dto.bio || '' },
          },
        },
        include: { profile: true },
      });
      return user;
    });
  }
}
```

---

### 1.7 Caching: Redis Integration

#### Cache-Aside Pattern

```typescript
// services/product.service.ts
import { Injectable, Inject } from '@nestjs/common';
import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { Cache } from 'cache-manager';

const PRODUCT_CACHE_TTL = 300; // 5 minutes in seconds
const PRODUCT_CACHE_PREFIX = 'product';

@Injectable()
export class ProductService {
  constructor(
    @Inject(CACHE_MANAGER) private readonly cacheManager: Cache,
    private readonly productRepository: ProductRepository,
  ) {}

  /**
   * Retrieve a product by ID with cache-aside pattern.
   * Checks cache first; on miss, reads from DB and populates cache.
   * @param id - Product UUID
   * @returns Product entity
   */
  async findById(id: string): Promise<Product> {
    const cacheKey = `${PRODUCT_CACHE_PREFIX}:${id}`;

    // 1. Check cache
    const cached = await this.cacheManager.get<Product>(cacheKey);
    if (cached) return cached;

    // 2. Cache miss — read from database
    const product = await this.productRepository.findById(id);
    if (!product) throw new EntityNotFoundException('Product', id);

    // 3. Populate cache
    await this.cacheManager.set(cacheKey, product, PRODUCT_CACHE_TTL);

    return product;
  }

  /**
   * Update product and invalidate cache.
   */
  async update(id: string, dto: UpdateProductDto): Promise<Product> {
    const product = await this.productRepository.update(id, dto);

    // Invalidate the specific key AND any list caches
    await this.cacheManager.del(`${PRODUCT_CACHE_PREFIX}:${id}`);
    await this.cacheManager.del(`${PRODUCT_CACHE_PREFIX}:list:*`);

    return product;
  }
}
```

#### Redis Module Registration

```typescript
// app.module.ts
import { CacheModule } from '@nestjs/cache-manager';
import * as redisStore from 'cache-manager-redis-yet';

@Module({
  imports: [
    CacheModule.registerAsync({
      isGlobal: true,
      useFactory: () => ({
        store: redisStore,
        host: process.env.REDIS_HOST || 'localhost',
        port: parseInt(process.env.REDIS_PORT || '6379', 10),
        ttl: 60, // default TTL in seconds
        max: 1000, // maximum number of items in cache
      }),
    }),
  ],
})
export class AppModule {}
```

**Cache Invalidation Checklist:**
- [ ] Invalidate on write (create, update, delete)
- [ ] Use namespaced keys: `{service}:{entity}:{id}`
- [ ] Set TTL on all cache entries (never cache forever)
- [ ] Log cache hits/misses at DEBUG level
- [ ] Use cache stampede protection for high-traffic keys

---

### 1.8 Authentication: JWT Guard with Refresh Token Rotation

```typescript
// strategies/jwt.strategy.ts
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';

export interface JwtPayload {
  sub: string;       // user ID
  email: string;
  role: string;
  iat: number;
  exp: number;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy, 'jwt') {
  constructor(private readonly usersService: UsersService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: process.env.JWT_ACCESS_SECRET,
    });
  }

  async validate(payload: JwtPayload) {
    const user = await this.usersService.findById(payload.sub);
    if (!user || !user.isActive) {
      throw new UnauthorizedException('User not found or inactive');
    }
    return { userId: payload.sub, email: payload.email, role: payload.role };
  }
}

// auth.service.ts — Token generation with refresh rotation
@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    private readonly usersService: UsersService,
    @Inject(REDIS_CLIENT) private readonly redis: Redis,
  ) {}

  async generateTokenPair(user: User): Promise<TokenPairDto> {
    const payload: Omit<JwtPayload, 'iat' | 'exp'> = {
      sub: user.id,
      email: user.email,
      role: user.role,
    };

    const accessToken = this.jwtService.sign(payload, {
      secret: process.env.JWT_ACCESS_SECRET,
      expiresIn: '15m',
    });

    const refreshToken = this.jwtService.sign(payload, {
      secret: process.env.JWT_REFRESH_SECRET,
      expiresIn: '7d',
    });

    // Store refresh token hash in Redis for rotation tracking
    await this.redis.set(
      `refresh:${user.id}`,
      hashToken(refreshToken),
      'EX',
      7 * 24 * 3600,
    );

    return { accessToken, refreshToken };
  }

  async refreshTokens(oldRefreshToken: string): Promise<TokenPairDto> {
    const payload = this.jwtService.verify<JwtPayload>(oldRefreshToken, {
      secret: process.env.JWT_REFRESH_SECRET,
    });

    // Verify the token matches what's stored (rotation check)
    const storedHash = await this.redis.get(`refresh:${payload.sub}`);
    if (!storedHash || storedHash !== hashToken(oldRefreshToken)) {
      // Possible token reuse attack — invalidate all sessions
      await this.redis.del(`refresh:${payload.sub}`);
      throw new UnauthorizedException('Refresh token reuse detected');
    }

    const user = await this.usersService.findById(payload.sub);
    return this.generateTokenPair(user);
  }
}
```

---

### 1.9 CORS & Security Middleware

```typescript
// main.ts
import helmet from 'helmet';
import * as compression from 'compression';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });

  // Security headers
  app.use(helmet());

  // Compression
  app.use(compression());

  // CORS configuration
  app.enableCors({
    origin: [
      process.env.FRONTEND_URL || 'http://localhost:3000',
      /\.gateforge\.io$/,  // Allow all GateForge subdomains
    ],
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: [
      'Content-Type',
      'Authorization',
      'X-Request-ID',
      'X-Trace-ID',
    ],
    credentials: true,
    maxAge: 86400, // 24 hours preflight cache
  });

  // Rate limiting
  app.use(
    rateLimit({
      windowMs: 15 * 60 * 1000, // 15 minutes
      max: 100,                   // limit each IP to 100 requests per window
      standardHeaders: true,
      legacyHeaders: false,
    }),
  );

  await app.listen(process.env.PORT || 3000);
}
```

---

### 1.10 Performance: Lazy Loading & Response Caching

#### Lazy Loading Modules

```typescript
// app.module.ts — Lazy load heavy modules
@Module({
  imports: [
    // Eagerly loaded core modules
    AuthModule,
    UsersModule,
    // Lazy loaded via router
    RouterModule.register([
      {
        path: 'reports',
        module: ReportsModule,  // Only loaded when /reports is hit
      },
    ]),
  ],
})
export class AppModule {}
```

#### Response Caching with Interceptor

```typescript
// interceptors/cache.interceptor.ts
import { CacheInterceptor, CacheTTL, CacheKey } from '@nestjs/cache-manager';

@Controller('products')
export class ProductsController {
  @Get()
  @UseInterceptors(CacheInterceptor)
  @CacheTTL(60) // Cache for 60 seconds
  @CacheKey('products-list')
  async findAll(@Query() query: PaginationQueryDto) {
    return this.productsService.findAll(query);
  }
}
```

---

### 1.11 React Frontend Best Practices

#### Component Architecture (Atomic Design)

```
src/
├── components/
│   ├── atoms/                # Basic building blocks
│   │   ├── Button/
│   │   │   ├── button.tsx
│   │   │   ├── button.styles.ts
│   │   │   ├── button.test.tsx
│   │   │   └── index.ts
│   │   ├── Input/
│   │   ├── Badge/
│   │   └── Spinner/
│   ├── molecules/            # Combinations of atoms
│   │   ├── SearchBar/
│   │   ├── FormField/
│   │   └── Card/
│   ├── organisms/            # Complex UI sections
│   │   ├── Header/
│   │   ├── DataTable/
│   │   └── Sidebar/
│   └── templates/            # Page-level layout patterns
│       ├── DashboardLayout/
│       └── AuthLayout/
├── features/                 # Feature-based modules
│   ├── auth/
│   │   ├── components/
│   │   ├── hooks/
│   │   ├── services/
│   │   └── store/
│   └── dashboard/
├── hooks/                    # Global custom hooks
│   ├── use-debounce.ts
│   ├── use-local-storage.ts
│   └── use-media-query.ts
├── services/                 # API layer
│   ├── api-client.ts
│   ├── user.service.ts
│   └── product.service.ts
├── store/                    # Global state (Zustand)
│   ├── auth.store.ts
│   └── ui.store.ts
├── types/                    # Shared TypeScript types
├── utils/                    # Utility functions
├── config/                   # App configuration
├── app.tsx
├── router.tsx
└── index.tsx
```

Reference: [LinkedIn — Ultimate React Folder Structure 2025](https://www.linkedin.com/pulse/ultimate-react-folder-structure-2025-sujan-adhikari-zxvzf)

#### State Management: Zustand vs Redux Toolkit

| Criterion | Zustand | Redux Toolkit |
|-----------|---------|---------------|
| Bundle size | ~1 KB | ~11 KB |
| Boilerplate | Minimal | Moderate (slices, store) |
| DevTools | Via middleware | Built-in |
| Best for | Local/feature state, small-medium apps | Complex global state, large teams |
| Learning curve | Low | Medium |
| Middleware | Simple | Rich (thunk, saga, listener) |

**Use Zustand** for most GateForge features. **Use Redux Toolkit** only if the feature has complex state machines, undo/redo, or needs time-travel debugging.

```typescript
// store/auth.store.ts — Zustand example
import { create } from 'zustand';
import { devtools, persist } from 'zustand/middleware';

interface AuthState {
  user: User | null;
  accessToken: string | null;
  isAuthenticated: boolean;
  login: (user: User, token: string) => void;
  logout: () => void;
  updateUser: (updates: Partial<User>) => void;
}

export const useAuthStore = create<AuthState>()(
  devtools(
    persist(
      (set) => ({
        user: null,
        accessToken: null,
        isAuthenticated: false,

        login: (user, accessToken) =>
          set({ user, accessToken, isAuthenticated: true }, false, 'auth/login'),

        logout: () =>
          set(
            { user: null, accessToken: null, isAuthenticated: false },
            false,
            'auth/logout',
          ),

        updateUser: (updates) =>
          set(
            (state) => ({
              user: state.user ? { ...state.user, ...updates } : null,
            }),
            false,
            'auth/updateUser',
          ),
      }),
      { name: 'auth-storage' },
    ),
  ),
);
```

#### API Layer Abstraction (TanStack Query)

Reference: [DEV Community — Mastering React Query in 2025](https://dev.to/jdavissoftware/mastering-react-query-in-2025-a-deep-dive-into-data-fetching-for-modern-apps-22jf), [Refine — React Query vs TanStack Query vs SWR](https://refine.dev/blog/react-query-vs-tanstack-query-vs-swr-2025/)

```typescript
// services/api-client.ts
import axios, { AxiosInstance, AxiosError } from 'axios';
import { useAuthStore } from '@/store/auth.store';

const apiClient: AxiosInstance = axios.create({
  baseURL: import.meta.env.VITE_API_URL || 'http://localhost:3000/api/v1',
  timeout: 15000,
  headers: { 'Content-Type': 'application/json' },
});

// Request interceptor — attach auth token
apiClient.interceptors.request.use((config) => {
  const token = useAuthStore.getState().accessToken;
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// Response interceptor — handle 401 refresh
apiClient.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const originalRequest = error.config;
    if (error.response?.status === 401 && !originalRequest._retry) {
      originalRequest._retry = true;
      try {
        const { data } = await axios.post('/api/v1/auth/refresh');
        useAuthStore.getState().login(data.user, data.accessToken);
        originalRequest.headers.Authorization = `Bearer ${data.accessToken}`;
        return apiClient(originalRequest);
      } catch {
        useAuthStore.getState().logout();
        window.location.href = '/login';
      }
    }
    return Promise.reject(error);
  },
);

export default apiClient;

// hooks/use-users.ts — TanStack Query hook
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import apiClient from '@/services/api-client';

export const userKeys = {
  all: ['users'] as const,
  lists: () => [...userKeys.all, 'list'] as const,
  list: (filters: Record<string, unknown>) => [...userKeys.lists(), filters] as const,
  details: () => [...userKeys.all, 'detail'] as const,
  detail: (id: string) => [...userKeys.details(), id] as const,
};

export function useUsers(filters: PaginationQueryDto) {
  return useQuery({
    queryKey: userKeys.list(filters),
    queryFn: () => apiClient.get('/users', { params: filters }).then((r) => r.data),
    staleTime: 30_000,        // Consider data fresh for 30 seconds
    placeholderData: (prev) => prev, // Keep previous data while fetching
  });
}

export function useUser(id: string) {
  return useQuery({
    queryKey: userKeys.detail(id),
    queryFn: () => apiClient.get(`/users/${id}`).then((r) => r.data),
    enabled: !!id,
  });
}

export function useCreateUser() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (dto: CreateUserDto) =>
      apiClient.post('/users', dto).then((r) => r.data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: userKeys.lists() });
    },
  });
}
```

#### Error Boundaries

```tsx
// components/error-boundary.tsx
import { Component, ErrorInfo, ReactNode } from 'react';

interface ErrorBoundaryProps {
  children: ReactNode;
  fallback?: ReactNode;
  onError?: (error: Error, errorInfo: ErrorInfo) => void;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  state: ErrorBoundaryState = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    this.props.onError?.(error, errorInfo);
    // Send to monitoring service
    console.error('[ErrorBoundary]', { error, componentStack: errorInfo.componentStack });
  }

  render() {
    if (this.state.hasError) {
      return (
        this.props.fallback || (
          <div role="alert" className="error-fallback">
            <h2>Something went wrong</h2>
            <p>{this.state.error?.message}</p>
            <button onClick={() => this.setState({ hasError: false, error: null })}>
              Try again
            </button>
          </div>
        )
      );
    }
    return this.props.children;
  }
}
```

#### Performance Optimization

```tsx
// Memoized component — use only when profiling shows re-render cost
const ExpensiveList = React.memo<{ items: Item[] }>(({ items }) => {
  return (
    <ul>
      {items.map((item) => (
        <li key={item.id}>{item.name}</li>
      ))}
    </ul>
  );
});

// useMemo — expensive computation
function Dashboard({ data }: { data: SalesData[] }) {
  const chartData = useMemo(() => {
    return data.map((d) => ({
      label: d.month,
      value: d.revenue - d.costs,
    }));
  }, [data]);

  return <Chart data={chartData} />;
}

// useCallback — stable callback reference for child components
function ParentComponent() {
  const [filter, setFilter] = useState('');

  const handleFilterChange = useCallback((value: string) => {
    setFilter(value);
  }, []);

  return <FilterInput onChange={handleFilterChange} />;
}

// Code splitting with React.lazy
const ReportsPage = React.lazy(() => import('./pages/reports-page'));

function App() {
  return (
    <Suspense fallback={<PageSkeleton />}>
      <Routes>
        <Route path="/reports" element={<ReportsPage />} />
      </Routes>
    </Suspense>
  );
}
```

Reference: [Strapi — React & Next.js Best Practices 2025](https://strapi.io/blog/react-and-nextjs-in-2025-modern-best-practices)

#### Accessibility (WCAG AA)

| Requirement | Implementation |
|---|---|
| Semantic HTML | Use `<main>`, `<nav>`, `<section>`, `<article>`, `<aside>`, `<header>`, `<footer>` |
| Interactive elements | Use `<button>` for actions, `<a>` for navigation — never `<div onClick>` |
| ARIA attributes | `aria-label` for icon buttons, `aria-live="polite"` for dynamic content, `aria-expanded` for collapsibles |
| Keyboard navigation | All interactive elements focusable, visible focus ring, `Escape` closes modals |
| Color contrast | Minimum 4.5:1 for normal text, 3:1 for large text |
| Form labels | Every `<input>` has an associated `<label>` with `htmlFor` |
| Alt text | All `<img>` tags have descriptive `alt` attributes |
| Skip links | Add "Skip to main content" link as first focusable element |

```tsx
// Accessible modal example
function Modal({ isOpen, onClose, title, children }: ModalProps) {
  const dialogRef = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (isOpen) dialog?.showModal();
    else dialog?.close();
  }, [isOpen]);

  return (
    <dialog
      ref={dialogRef}
      aria-labelledby="modal-title"
      aria-modal="true"
      onClose={onClose}
    >
      <h2 id="modal-title">{title}</h2>
      <div role="document">{children}</div>
      <button onClick={onClose} aria-label="Close dialog">
        Close
      </button>
    </dialog>
  );
}
```

---

## 2. Mobile App Development Best Practices

### 2.1 React Native Project Structure

Reference: [Tricentis — React Native Project Structure](https://www.tricentis.com/learn/react-native-project-structure), [DEV Community — React Native Folder Structure](https://dev.to/ersuman/the-ultimate-guide-to-the-best-folder-structure-in-react-native-dc4)

GateForge mobile apps use a **feature-based** structure:

```
mobile-app/
├── src/
│   ├── app/                          # App entry & providers
│   │   ├── app.tsx
│   │   ├── providers.tsx             # All context providers composed
│   │   └── navigation/
│   │       ├── root-navigator.tsx
│   │       ├── auth-navigator.tsx
│   │       ├── main-navigator.tsx
│   │       └── types.ts             # Navigation param list types
│   ├── features/                     # Feature modules
│   │   ├── auth/
│   │   │   ├── screens/
│   │   │   │   ├── login-screen.tsx
│   │   │   │   └── register-screen.tsx
│   │   │   ├── components/
│   │   │   │   └── social-login-button.tsx
│   │   │   ├── hooks/
│   │   │   │   └── use-auth.ts
│   │   │   └── services/
│   │   │       └── auth.service.ts
│   │   ├── dashboard/
│   │   │   ├── screens/
│   │   │   ├── components/
│   │   │   └── hooks/
│   │   └── settings/
│   ├── shared/                       # Shared across features
│   │   ├── components/               # Reusable UI components
│   │   │   ├── button.tsx
│   │   │   ├── text-input.tsx
│   │   │   └── loading-overlay.tsx
│   │   ├── hooks/
│   │   │   ├── use-network-status.ts
│   │   │   └── use-secure-storage.ts
│   │   ├── services/
│   │   │   ├── api-client.ts
│   │   │   ├── storage.service.ts
│   │   │   └── notification.service.ts
│   │   ├── utils/
│   │   │   ├── format-date.ts
│   │   │   └── validation.ts
│   │   ├── constants/
│   │   │   ├── colors.ts
│   │   │   ├── spacing.ts
│   │   │   └── api-routes.ts
│   │   └── types/
│   │       ├── api.types.ts
│   │       └── navigation.types.ts
│   ├── assets/
│   │   ├── images/
│   │   ├── fonts/
│   │   └── animations/              # Lottie files
│   └── config/
│       ├── env.ts
│       └── app.config.ts
├── android/
├── ios/
├── __tests__/
├── app.json
├── metro.config.js
├── babel.config.js
├── tsconfig.json
└── package.json
```

---

### 2.2 Cross-Platform Strategy

Reference: [NextNative — Mobile Development Best Practices](https://nextnative.dev/blog/mobile-development-best-practices), [Mind IT Systems — Cross-Platform Best Practices](https://minditsystems.com/best-practices-for-cross-platform-mobile-app-development/)

| Layer | Strategy |
|-------|----------|
| **Business logic** | 100% shared — hooks, services, utilities |
| **UI components** | 90% shared — use `Platform.select()` for minor differences |
| **Navigation** | Shared structure, platform-specific transitions |
| **Native modules** | Platform-specific when needed (biometrics, notifications) |
| **Styling** | Shared design tokens, platform-adaptive spacing |

**Decision rule for platform-specific code:**

```typescript
// Shared component with platform adaptations
import { Platform, StyleSheet } from 'react-native';

const styles = StyleSheet.create({
  container: {
    paddingTop: Platform.select({ ios: 44, android: 0 }),
    ...Platform.select({
      ios: { shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.1 },
      android: { elevation: 4 },
    }),
  },
});

// For larger divergences, use .ios.tsx / .android.tsx file extensions
// Example: date-picker.ios.tsx and date-picker.android.tsx
```

---

### 2.3 Navigation (React Navigation)

```typescript
// navigation/types.ts — Type-safe navigation params
export type RootStackParamList = {
  Auth: undefined;
  Main: undefined;
};

export type AuthStackParamList = {
  Login: undefined;
  Register: undefined;
  ForgotPassword: { email?: string };
};

export type MainTabParamList = {
  Dashboard: undefined;
  Orders: undefined;
  Profile: undefined;
};

export type OrdersStackParamList = {
  OrderList: { status?: string };
  OrderDetail: { orderId: string };
};

// navigation/root-navigator.tsx
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { useAuthStore } from '@/shared/hooks/use-auth';
import { linking } from './deep-linking';

const Stack = createNativeStackNavigator<RootStackParamList>();

export function RootNavigator() {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);

  return (
    <NavigationContainer linking={linking}>
      <Stack.Navigator screenOptions={{ headerShown: false }}>
        {isAuthenticated ? (
          <Stack.Screen name="Main" component={MainNavigator} />
        ) : (
          <Stack.Screen
            name="Auth"
            component={AuthNavigator}
            options={{ animationTypeForReplace: 'pop' }}
          />
        )}
      </Stack.Navigator>
    </NavigationContainer>
  );
}
```

---

### 2.4 Secure Storage

```typescript
// services/secure-storage.service.ts
import * as Keychain from 'react-native-keychain';

const SERVICE_NAME = 'com.gateforge.mobile';

export const SecureStorage = {
  /**
   * Store a key-value pair in the device keychain.
   * @param key - The identifier for the stored value
   * @param value - The secret value to store
   */
  async set(key: string, value: string): Promise<void> {
    await Keychain.setGenericPassword(key, value, { service: `${SERVICE_NAME}.${key}` });
  },

  /**
   * Retrieve a value from the device keychain.
   * @param key - The identifier to look up
   * @returns The stored value, or null if not found
   */
  async get(key: string): Promise<string | null> {
    const credentials = await Keychain.getGenericPassword({ service: `${SERVICE_NAME}.${key}` });
    return credentials ? credentials.password : null;
  },

  /** Remove a value from the device keychain. */
  async remove(key: string): Promise<void> {
    await Keychain.resetGenericPassword({ service: `${SERVICE_NAME}.${key}` });
  },

  /** Store authentication tokens securely. */
  async setTokens(accessToken: string, refreshToken: string): Promise<void> {
    await this.set('accessToken', accessToken);
    await this.set('refreshToken', refreshToken);
  },

  /** Retrieve authentication tokens. */
  async getTokens(): Promise<{ accessToken: string | null; refreshToken: string | null }> {
    const [accessToken, refreshToken] = await Promise.all([
      this.get('accessToken'),
      this.get('refreshToken'),
    ]);
    return { accessToken, refreshToken };
  },

  /** Clear all authentication tokens. */
  async clearTokens(): Promise<void> {
    await Promise.all([this.remove('accessToken'), this.remove('refreshToken')]);
  },
};
```

**Security rules:**
- [ ] Never store secrets in AsyncStorage (unencrypted)
- [ ] Use `react-native-keychain` for tokens, API keys, user credentials
- [ ] Enable biometric protection for high-sensitivity data
- [ ] Clear tokens on logout and app uninstall detection
- [ ] Use `SECURITY_LEVEL.SECURE_HARDWARE` when available

---

### 2.5 API Communication: Axios Interceptors & Token Refresh

```typescript
// services/api-client.ts
import axios, { AxiosInstance, AxiosError, InternalAxiosRequestConfig } from 'axios';
import { SecureStorage } from './secure-storage.service';
import { ENV } from '@/config/env';

let isRefreshing = false;
let failedQueue: Array<{
  resolve: (token: string) => void;
  reject: (error: Error) => void;
}> = [];

const processQueue = (error: Error | null, token: string | null = null) => {
  failedQueue.forEach((promise) => {
    if (error) promise.reject(error);
    else if (token) promise.resolve(token);
  });
  failedQueue = [];
};

const apiClient: AxiosInstance = axios.create({
  baseURL: ENV.API_BASE_URL,
  timeout: 15000,
  headers: { 'Content-Type': 'application/json' },
});

// Request interceptor
apiClient.interceptors.request.use(async (config: InternalAxiosRequestConfig) => {
  const tokens = await SecureStorage.getTokens();
  if (tokens.accessToken) {
    config.headers.Authorization = `Bearer ${tokens.accessToken}`;
  }
  return config;
});

// Response interceptor with queue-based token refresh
apiClient.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const originalRequest = error.config as InternalAxiosRequestConfig & { _retry?: boolean };

    if (error.response?.status !== 401 || originalRequest._retry) {
      return Promise.reject(error);
    }

    if (isRefreshing) {
      return new Promise((resolve, reject) => {
        failedQueue.push({
          resolve: (token: string) => {
            originalRequest.headers.Authorization = `Bearer ${token}`;
            resolve(apiClient(originalRequest));
          },
          reject,
        });
      });
    }

    originalRequest._retry = true;
    isRefreshing = true;

    try {
      const tokens = await SecureStorage.getTokens();
      const { data } = await axios.post(`${ENV.API_BASE_URL}/auth/refresh`, {
        refreshToken: tokens.refreshToken,
      });

      await SecureStorage.setTokens(data.accessToken, data.refreshToken);
      processQueue(null, data.accessToken);

      originalRequest.headers.Authorization = `Bearer ${data.accessToken}`;
      return apiClient(originalRequest);
    } catch (refreshError) {
      processQueue(refreshError as Error, null);
      await SecureStorage.clearTokens();
      // Trigger navigation to login screen
      return Promise.reject(refreshError);
    } finally {
      isRefreshing = false;
    }
  },
);

export default apiClient;
```

---

### 2.6 Offline-First Architecture

Reference: [OneUptime — Offline-First Architecture in React Native](https://oneuptime.com/blog/post/2026-01-15-react-native-offline-architecture/view)

#### Architecture Layers

```
┌──────────────────────────────────┐
│         UI Components            │
├──────────────────────────────────┤
│     TanStack Query (cache)       │
├──────────────────────────────────┤
│     Sync Queue Manager           │  ← Queues mutations while offline
├──────────────────────────────────┤
│   WatermelonDB (local SQLite)    │  ← Single source of truth for UI
├──────────────────────────────────┤
│     Network Status Monitor       │  ← Triggers sync when online
├──────────────────────────────────┤
│         REST API Server          │
└──────────────────────────────────┘
```

#### Network Monitor Hook

```typescript
// hooks/use-network-status.ts
import { useState, useEffect } from 'react';
import NetInfo, { NetInfoState } from '@react-native-community/netinfo';

export function useNetworkStatus() {
  const [isConnected, setIsConnected] = useState(true);
  const [connectionType, setConnectionType] = useState<string | null>(null);

  useEffect(() => {
    const unsubscribe = NetInfo.addEventListener((state: NetInfoState) => {
      setIsConnected(state.isConnected ?? false);
      setConnectionType(state.type);
    });
    return unsubscribe;
  }, []);

  return { isConnected, connectionType };
}
```

#### Sync Queue

```typescript
// services/sync-queue.service.ts
interface QueuedOperation {
  id: string;
  method: 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  endpoint: string;
  body?: Record<string, unknown>;
  createdAt: string;
  retryCount: number;
}

class SyncQueueService {
  private queue: QueuedOperation[] = [];
  private readonly MAX_RETRIES = 3;

  async enqueue(operation: Omit<QueuedOperation, 'id' | 'createdAt' | 'retryCount'>): Promise<void> {
    const op: QueuedOperation = {
      ...operation,
      id: generateUUID(),
      createdAt: new Date().toISOString(),
      retryCount: 0,
    };
    this.queue.push(op);
    await this.persistQueue();
  }

  async processQueue(): Promise<void> {
    const pending = [...this.queue];

    for (const operation of pending) {
      try {
        await apiClient.request({
          method: operation.method,
          url: operation.endpoint,
          data: operation.body,
        });
        this.queue = this.queue.filter((op) => op.id !== operation.id);
      } catch (error) {
        operation.retryCount += 1;
        if (operation.retryCount >= this.MAX_RETRIES) {
          // Move to dead-letter queue
          this.queue = this.queue.filter((op) => op.id !== operation.id);
          await this.moveToDeadLetter(operation);
        }
      }
    }
    await this.persistQueue();
  }

  private async persistQueue(): Promise<void> {
    await AsyncStorage.setItem('sync_queue', JSON.stringify(this.queue));
  }

  private async moveToDeadLetter(operation: QueuedOperation): Promise<void> {
    const deadLetters = JSON.parse(
      (await AsyncStorage.getItem('dead_letter_queue')) || '[]',
    );
    deadLetters.push({ ...operation, failedAt: new Date().toISOString() });
    await AsyncStorage.setItem('dead_letter_queue', JSON.stringify(deadLetters));
  }
}

export const syncQueue = new SyncQueueService();
```

---

### 2.7 Performance Optimization

#### FlatList Best Practices

```tsx
// components/optimized-list.tsx
import { FlatList, FlatListProps } from 'react-native';

function OptimizedList<T extends { id: string }>({
  data,
  renderItem,
  ...props
}: FlatListProps<T>) {
  return (
    <FlatList
      data={data}
      renderItem={renderItem}
      keyExtractor={(item) => item.id}
      // Performance optimizations
      removeClippedSubviews={true}           // Unmount off-screen items
      maxToRenderPerBatch={10}                // Render 10 items per batch
      updateCellsBatchingPeriod={50}          // Batch period in ms
      windowSize={5}                          // Render 5 screens worth of content
      initialNumToRender={10}                 // Initial render count
      getItemLayout={(_, index) => ({         // Skip measurement if fixed height
        length: ITEM_HEIGHT,
        offset: ITEM_HEIGHT * index,
        index,
      })}
      // Pull-to-refresh
      onEndReachedThreshold={0.5}
      {...props}
    />
  );
}
```

#### Image Caching

```typescript
// Use react-native-fast-image for automatic disk/memory caching
import FastImage from 'react-native-fast-image';

<FastImage
  source={{
    uri: imageUrl,
    priority: FastImage.priority.normal,
    cache: FastImage.cacheControl.immutable,  // Cache indefinitely
  }}
  resizeMode={FastImage.resizeMode.cover}
  style={{ width: 100, height: 100 }}
/>
```

**Performance Checklist:**
- [ ] Use `FlatList` or `FlashList` instead of `ScrollView` for long lists
- [ ] Enable `removeClippedSubviews` for large lists
- [ ] Use `React.memo` on list item components
- [ ] Provide `getItemLayout` when item heights are fixed
- [ ] Use `react-native-fast-image` for image caching
- [ ] Minimize bridge crossings — batch native calls
- [ ] Use Hermes engine (enabled by default in modern RN)
- [ ] Profile with React DevTools and Flipper

---

### 2.8 Platform-Specific UI Considerations

| Aspect | iOS (Human Interface Guidelines) | Android (Material Design) |
|--------|----------------------------------|---------------------------|
| Navigation | Tab bar at bottom, back gesture swipe | Bottom navigation bar, hardware back button |
| Typography | San Francisco font family | Roboto font family |
| Buttons | Rounded rectangles, no shadows | Contained/outlined with elevation |
| Modals | Slide up from bottom | Full-screen or centered dialog |
| Status bar | Light content on dark backgrounds | Material You dynamic theming |
| Safe areas | Respect notch and home indicator | Respect system bars and cutouts |
| Haptics | Taptic engine feedback on actions | Vibration patterns |
| Loading | System activity indicator | Circular progress indicator |

Reference: [DEV Community — Mobile App Development Guide 2025](https://dev.to/sajan_kumarsingh_b556129/the-complete-guide-to-mobile-app-development-in-2025-native-cross-platform-and-hybrid-approaches-50om)

---

### 2.9 Push Notifications

```typescript
// services/notification.service.ts
import messaging from '@react-native-firebase/messaging';
import { Platform } from 'react-native';
import notifee, { AndroidImportance } from '@notifee/react-native';

export class NotificationService {
  /** Request permission and register the device token. */
  async initialize(): Promise<string | null> {
    // Request permission (required on iOS)
    const authStatus = await messaging().requestPermission();
    const enabled =
      authStatus === messaging.AuthorizationStatus.AUTHORIZED ||
      authStatus === messaging.AuthorizationStatus.PROVISIONAL;

    if (!enabled) return null;

    // Get FCM token
    const token = await messaging().getToken();

    // Create Android notification channel
    if (Platform.OS === 'android') {
      await notifee.createChannel({
        id: 'default',
        name: 'Default',
        importance: AndroidImportance.HIGH,
        vibration: true,
      });
    }

    // Listen for token refresh
    messaging().onTokenRefresh(async (newToken) => {
      await this.registerTokenOnServer(newToken);
    });

    // Register with backend
    await this.registerTokenOnServer(token);
    return token;
  }

  /** Handle foreground messages. */
  setupForegroundHandler(): void {
    messaging().onMessage(async (remoteMessage) => {
      await notifee.displayNotification({
        title: remoteMessage.notification?.title || 'GateForge',
        body: remoteMessage.notification?.body || '',
        android: { channelId: 'default', pressAction: { id: 'default' } },
      });
    });
  }

  /** Handle background/quit messages. */
  static setupBackgroundHandler(): void {
    messaging().setBackgroundMessageHandler(async (remoteMessage) => {
      // Process data-only messages silently
      console.log('[Background Message]', remoteMessage.data);
    });
  }

  private async registerTokenOnServer(token: string): Promise<void> {
    await apiClient.post('/devices', {
      token,
      platform: Platform.OS,
      appVersion: APP_VERSION,
    });
  }
}
```

---

### 2.10 Deep Linking

```typescript
// navigation/deep-linking.ts
import { LinkingOptions } from '@react-navigation/native';
import { RootStackParamList } from './types';

export const linking: LinkingOptions<RootStackParamList> = {
  prefixes: ['gateforge://', 'https://app.gateforge.io'],

  config: {
    screens: {
      Auth: {
        screens: {
          Login: 'login',
          Register: 'register',
          ForgotPassword: 'forgot-password',
        },
      },
      Main: {
        screens: {
          Dashboard: 'dashboard',
          Orders: {
            screens: {
              OrderList: 'orders',
              OrderDetail: 'orders/:orderId',
            },
          },
          Profile: 'profile',
        },
      },
    },
  },

  // Handle incoming URLs that need auth check
  getStateFromPath: (path, options) => {
    // Custom logic for protected routes
    return undefined; // fall back to default
  },
};
```

---

### 2.11 App Update Strategy (CodePush OTA)

```typescript
// app/app.tsx
import codePush, { CodePushOptions } from 'react-native-code-push';

const codePushOptions: CodePushOptions = {
  checkFrequency: codePush.CheckFrequency.ON_APP_RESUME,
  installMode: codePush.InstallMode.ON_NEXT_RESTART,
  mandatoryInstallMode: codePush.InstallMode.IMMEDIATE,
  minimumBackgroundDuration: 60 * 5, // 5 minutes
};

function App() {
  const [updateAvailable, setUpdateAvailable] = useState(false);

  useEffect(() => {
    codePush.sync(
      {
        installMode: codePush.InstallMode.ON_NEXT_RESTART,
        updateDialog: {
          title: 'Update Available',
          optionalUpdateMessage: 'A new update is available. Install now?',
          optionalInstallButtonLabel: 'Install',
          optionalIgnoreButtonLabel: 'Later',
        },
      },
      (status) => {
        if (status === codePush.SyncStatus.UPDATE_INSTALLED) {
          setUpdateAvailable(true);
        }
      },
    );
  }, []);

  return <RootNavigator />;
}

export default codePush(codePushOptions)(App);
```

**OTA Update Rules:**
- [ ] Only JS bundle and assets can be updated via CodePush
- [ ] Native code changes require a full app store release
- [ ] Always test OTA updates on staging environment first
- [ ] Maintain rollback capability for every CodePush release
- [ ] Use deployment keys: `Staging` for UAT, `Production` for live
- [ ] Set mandatory updates for critical security patches

---

### 2.12 Testing Strategy

| Test Type | Tool | Scope |
|-----------|------|-------|
| Unit tests | Jest | Services, hooks, utilities |
| Component tests | React Native Testing Library | Individual components |
| Integration tests | Detox / Maestro | Full screen flows |
| E2E tests (iOS) | Detox on real device or Simulator | Critical user journeys |
| E2E tests (Android) | Detox on real device or Emulator | Critical user journeys |

**Testing rule:** Always test on real devices before release. Emulators cannot catch:
- Touch/gesture sensitivity issues
- Camera and biometric behavior
- Push notification delivery
- Performance under real network conditions
- Battery and memory constraints

---

## 3. Coding Standards

### 3.1 TypeScript Strict Mode Configuration

```jsonc
// tsconfig.json
{
  "compilerOptions": {
    // Strict type checking
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "strictFunctionTypes": true,
    "strictPropertyInitialization": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,

    // Module resolution
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "isolatedModules": true,

    // Output
    "target": "ES2022",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./src",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "incremental": true,

    // Path aliases
    "baseUrl": ".",
    "paths": {
      "@libs/*": ["libs/*/src"],
      "@app/*": ["apps/api-gateway/src/*"],
      "@/*": ["src/*"]
    },

    // Additional safety
    "forceConsistentCasingInFileNames": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "**/*.spec.ts"]
}
```

---

### 3.2 Naming Conventions

Reference: [AWS Prescriptive Guidance — TypeScript Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/best-practices-cdk-typescript-iac/typescript-best-practices.html)

| Element | Convention | Example |
|---------|-----------|---------|
| Variables | `camelCase` | `userName`, `orderCount` |
| Functions | `camelCase` | `getUserById`, `calculateTotal` |
| Parameters | `camelCase` | `userId`, `pageSize` |
| Classes | `PascalCase` | `UserService`, `OrderController` |
| Interfaces | `PascalCase` (no `I` prefix) | `UserProfile`, `ApiResponse` |
| Types | `PascalCase` | `ResponseStatus`, `TokenPair` |
| Enums | `PascalCase` (members too) | `HttpStatusCode.NotFound` |
| Global constants | `UPPER_SNAKE_CASE` | `MAX_RETRY_ATTEMPTS`, `API_BASE_URL` |
| File names | `kebab-case` | `user-service.ts`, `create-user.dto.ts` |
| Folder names | `kebab-case` | `user-management/`, `order-processing/` |
| Test files | `kebab-case.spec.ts` | `user-service.spec.ts` |
| Boolean variables | `is`/`has`/`should` prefix | `isActive`, `hasPermission` |
| Event handlers | `handle` prefix or `on` prefix | `handleSubmit`, `onUserCreated` |

**File naming patterns for NestJS:**

```
user.module.ts
user.controller.ts
user.service.ts
user.repository.ts
user.entity.ts
create-user.dto.ts
update-user.dto.ts
user-response.dto.ts
jwt-auth.guard.ts
roles.guard.ts
logging.interceptor.ts
all-exceptions.filter.ts
parse-uuid.pipe.ts
```

---

### 3.3 Import Ordering Convention

Imports must be ordered in four groups, separated by blank lines:

```typescript
// 1. Built-in Node.js modules
import { readFile } from 'fs/promises';
import * as path from 'path';

// 2. External packages (npm modules)
import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';

// 3. Internal packages (workspace libs, path aliases)
import { AppException } from '@libs/common/exceptions';
import { PaginatedResponse } from '@libs/common/interfaces';

// 4. Relative imports (current module)
import { User } from './entities/user.entity';
import { CreateUserDto } from './dto/create-user.dto';
```

**ESLint enforces this automatically** — see ESLint config in section 3.10.

---

### 3.4 Code Documentation (JSDoc)

Every public function, method, class, and exported type must have JSDoc:

```typescript
/**
 * Service responsible for user account management operations.
 *
 * @example
 * ```typescript
 * const userService = moduleRef.get(UserService);
 * const user = await userService.findById('uuid-123');
 * ```
 */
@Injectable()
export class UserService {
  /**
   * Finds a user by their unique identifier.
   *
   * @param id - The UUID of the user to find
   * @returns The user entity with profile relation loaded
   * @throws {EntityNotFoundException} When no user exists with the given ID
   *
   * @example
   * ```typescript
   * const user = await userService.findById('550e8400-e29b-41d4-a716-446655440000');
   * console.log(user.email); // 'john@example.com'
   * ```
   */
  async findById(id: string): Promise<User> {
    const user = await this.userRepository.findOne({
      where: { id },
      relations: ['profile'],
    });

    if (!user) {
      throw new EntityNotFoundException('User', id);
    }

    return user;
  }

  /**
   * Soft-deletes a user account and revokes all active sessions.
   *
   * @param id - The UUID of the user to deactivate
   * @param performedBy - The admin user ID performing the action (for audit)
   * @returns void
   * @throws {EntityNotFoundException} When the user does not exist
   * @throws {BusinessRuleViolationException} When trying to deactivate the last admin
   */
  async deactivate(id: string, performedBy: string): Promise<void> {
    // Implementation
  }
}
```

---

### 3.5 Function Design Principles

| Rule | Description |
|------|-------------|
| **Single Responsibility** | Each function does exactly one thing |
| **Max 30 lines** | If longer, extract helper functions |
| **Pure functions preferred** | Given the same inputs, always return the same output with no side effects |
| **Max 3 parameters** | Use an options object for more |
| **Early returns** | Handle error cases first, then the happy path |
| **No nested ternaries** | Use `if`/`else` for complex conditions |
| **Descriptive names** | Function name describes what it does: `verb` + `noun` |

```typescript
// BAD: multiple responsibilities, too long, unclear
function processData(data: any) {
  // ... 60 lines of mixed validation, transformation, and saving
}

// GOOD: separated concerns
function validateOrderInput(dto: CreateOrderDto): ValidationResult {
  // 10 lines: validate
}

function calculateOrderTotal(items: OrderItem[]): number {
  // 5 lines: pure computation
}

async function persistOrder(order: Order): Promise<Order> {
  // 10 lines: save to DB
}
```

---

### 3.6 Error Handling Standards

**Rules:**
1. **Never swallow errors** — every `catch` must log or re-throw
2. **Always use typed errors** — use custom `AppException` subclasses
3. **No `try/catch` around single awaits unless handling specifically** — let the global filter handle unexpected errors
4. **Include context** — error messages must include what operation failed and what entity was involved

```typescript
// BAD: swallowed error
try {
  await sendEmail(user.email, template);
} catch (e) {
  // silently ignored
}

// BAD: generic error
throw new Error('Something went wrong');

// GOOD: structured error with context
try {
  await sendEmail(user.email, template);
} catch (error) {
  this.logger.error(
    { userId: user.id, template: template.name, error },
    'Failed to send email',
  );
  throw new AppException(
    'EMAIL_SEND_FAILED',
    `Failed to send ${template.name} email to user ${user.id}`,
    HttpStatus.SERVICE_UNAVAILABLE,
    { userId: user.id, templateName: template.name },
  );
}
```

---

### 3.7 Conventional Commits

All commit messages must follow [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

| Type | When to Use | Example |
|------|-------------|---------|
| `feat` | New feature | `feat(users): add email verification endpoint` |
| `fix` | Bug fix | `fix(orders): correct total calculation for discounts` |
| `refactor` | Code change that neither fixes nor adds | `refactor(auth): extract token generation to separate service` |
| `docs` | Documentation only | `docs(api): update OpenAPI spec for users endpoint` |
| `test` | Adding or fixing tests | `test(orders): add integration tests for checkout flow` |
| `chore` | Build process, tooling, dependencies | `chore(deps): update NestJS to v11.2` |
| `perf` | Performance improvement | `perf(queries): add index on orders.user_id column` |
| `style` | Formatting, missing semicolons, etc. | `style: fix ESLint warnings in user module` |
| `ci` | CI configuration changes | `ci: add caching to GitHub Actions pipeline` |

**Breaking changes:**
```
feat(api)!: change user response format

BREAKING CHANGE: The `fullName` field has been split into `firstName` and `lastName`.
Migration guide: Update all API consumers to use the new field names.
```

---

### 3.8 Git Branching

```
main              ← Production (protected, deploy via CI)
  └── develop     ← Integration branch (protected)
       ├── feature/TASK-001-user-auth
       ├── feature/TASK-002-order-service
       ├── fix/TASK-010-login-redirect
       └── refactor/TASK-015-extract-base-service
```

| Branch Type | Pattern | Merges Into |
|-------------|---------|-------------|
| Feature | `feature/TASK-XXX-short-description` | `develop` |
| Bug fix | `fix/TASK-XXX-short-description` | `develop` |
| Hotfix | `hotfix/TASK-XXX-short-description` | `main` + `develop` |
| Refactor | `refactor/TASK-XXX-short-description` | `develop` |

**Rules:**
- Always branch from `develop` (unless hotfix)
- Developer agents push to feature branch only — **never merge**
- System Architect or Operator handles merge operations

---

### 3.9 PR Checklist

Every pull request must satisfy **all** items before requesting review:

- [ ] Code compiles with zero TypeScript errors (`tsc --noEmit`)
- [ ] All existing tests pass (`npm test`)
- [ ] New/modified code has corresponding unit tests (minimum 80% coverage for new code)
- [ ] API documentation updated (OpenAPI spec) if endpoints changed
- [ ] JSDoc added for all public functions and types
- [ ] No secrets, credentials, or environment-specific values in code
- [ ] ESLint passes with zero errors (`npm run lint`)
- [ ] Prettier formatting applied (`npm run format`)
- [ ] No `console.log` statements in production code
- [ ] No `any` types (use `unknown` + type narrowing instead)
- [ ] No magic numbers (extract to named constants)
- [ ] Conventional commit messages used
- [ ] Branch named correctly: `feature/TASK-XXX-description`
- [ ] Integration points documented in task report JSON

---

### 3.10 ESLint + Prettier Configuration

#### ESLint Configuration

```jsonc
// .eslintrc.json
{
  "root": true,
  "parser": "@typescript-eslint/parser",
  "parserOptions": {
    "project": "./tsconfig.json",
    "sourceType": "module"
  },
  "plugins": [
    "@typescript-eslint",
    "import",
    "unused-imports"
  ],
  "extends": [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
    "plugin:@typescript-eslint/recommended-requiring-type-checking",
    "plugin:import/typescript",
    "prettier"
  ],
  "rules": {
    // TypeScript
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/explicit-function-return-type": ["warn", {
      "allowExpressions": true,
      "allowTypedFunctionExpressions": true
    }],
    "@typescript-eslint/no-unused-vars": "off",
    "unused-imports/no-unused-imports": "error",
    "unused-imports/no-unused-vars": ["warn", {
      "argsIgnorePattern": "^_",
      "varsIgnorePattern": "^_"
    }],
    "@typescript-eslint/naming-convention": [
      "error",
      { "selector": "variable", "format": ["camelCase", "UPPER_CASE", "PascalCase"] },
      { "selector": "function", "format": ["camelCase", "PascalCase"] },
      { "selector": "typeLike", "format": ["PascalCase"] },
      { "selector": "enumMember", "format": ["PascalCase", "UPPER_CASE"] }
    ],
    "@typescript-eslint/no-floating-promises": "error",
    "@typescript-eslint/await-thenable": "error",

    // Imports
    "import/order": ["error", {
      "groups": ["builtin", "external", "internal", "parent", "sibling", "index"],
      "pathGroups": [
        { "pattern": "@libs/**", "group": "internal", "position": "before" },
        { "pattern": "@app/**", "group": "internal", "position": "before" }
      ],
      "newlines-between": "always",
      "alphabetize": { "order": "asc", "caseInsensitive": true }
    }],

    // General
    "no-console": ["error", { "allow": ["warn", "error"] }],
    "no-magic-numbers": ["warn", {
      "ignore": [0, 1, -1],
      "ignoreArrayIndexes": true,
      "enforceConst": true
    }],
    "prefer-const": "error",
    "no-var": "error",
    "eqeqeq": ["error", "always"]
  },
  "ignorePatterns": ["dist/", "node_modules/", "*.js"]
}
```

#### Prettier Configuration

```jsonc
// .prettierrc
{
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100,
  "tabWidth": 2,
  "semi": true,
  "bracketSpacing": true,
  "arrowParens": "always",
  "endOfLine": "lf",
  "quoteProps": "as-needed"
}
```

---

### 3.11 Enum vs Union Type Decision

| Use **Enum** when... | Use **Union Type** when... |
|---|---|
| Value needs reverse mapping (number enums) | Values are simple string literals |
| Used in switch statements with exhaustiveness | Used for function parameter constraints |
| Needs iteration over members | No runtime representation needed |
| Used across service boundaries (API contracts) | Internal-only type constraint |
| Stored in database columns | Inferred from existing data |

```typescript
// Enum: Used in API responses and database columns
export enum OrderStatus {
  Pending = 'pending',
  Processing = 'processing',
  Shipped = 'shipped',
  Delivered = 'delivered',
  Cancelled = 'cancelled',
}

// Union type: Internal type constraint
export type SortDirection = 'ASC' | 'DESC';
export type LogLevel = 'fatal' | 'error' | 'warn' | 'info' | 'debug' | 'trace';
```

---

### 3.12 Barrel Exports (index.ts)

Use barrel exports to simplify imports from modules. Each feature folder should have an `index.ts`:

```typescript
// features/users/index.ts (barrel export)
export { UsersModule } from './users.module';
export { UsersService } from './users.service';
export { User } from './entities/user.entity';
export { CreateUserDto } from './dto/create-user.dto';
export { UpdateUserDto } from './dto/update-user.dto';
export type { UserResponseDto } from './dto/user-response.dto';

// Usage from another module:
import { UsersService, User, CreateUserDto } from '@app/features/users';
```

**Barrel export rules:**
- [ ] Every feature folder has an `index.ts`
- [ ] Only export public API — internal implementation stays unexported
- [ ] Re-export types with `export type` to enable `isolatedModules`
- [ ] Do NOT create barrel exports for deeply nested utility files (causes circular dependencies)
- [ ] `libs/common/src/index.ts` exports all shared utilities

---

## 4. Application Logging Mechanism Guide

### 4.1 Why Structured Logging Matters

In a microservices architecture like GateForge (5 VMs, multiple agent services), logs are the primary diagnostic tool. Unstructured text logs are:
- Impossible to query at scale
- Difficult to correlate across services
- Unparseable by log aggregation systems

**Structured JSON logging** makes every log entry a queryable data point.

Reference: [Dash0 — Microservices Observability](https://www.dash0.com/knowledge/microservices-observability), [Observo AI — Log Management in Microservices](https://www.observo.ai/post/log-management-and-observability-in-microservices)

---

### 4.2 Logging Library: Pino (Recommended)

Reference: [BetterStack — Pino vs Winston](https://betterstack.com/community/guides/scaling-nodejs/pino-vs-winston/), [DEV Community — Pino vs Winston](https://dev.to/wallacefreitas/pino-vs-winston-choosing-the-right-logger-for-your-nodejs-application-369n)

| Feature | Pino | Winston |
|---------|------|---------|
| **Performance** | 5x faster (async, minimal overhead) | Slower (synchronous by default) |
| **Output format** | JSON-first (structured by default) | Text-first (JSON optional) |
| **Transport** | Worker threads (non-blocking) | In-process (blocking) |
| **NestJS integration** | `nestjs-pino` (first-class) | `nest-winston` (community) |
| **Bundle size** | Lightweight | Heavier |
| **Best for** | High-throughput microservices | Legacy apps needing flexibility |

**GateForge standard: Use Pino via `nestjs-pino`** for all NestJS services.

Reference: [GitHub — nestjs-pino](https://github.com/iamolegga/nestjs-pino), [Tom Ray — NestJS Logger with Pino](https://www.tomray.dev/nestjs-logging)

---

### 4.3 Log Levels and When to Use Each

| Level | Numeric | When to Use | Examples | Production? |
|-------|---------|-------------|----------|-------------|
| `FATAL` | 60 | System cannot continue, process will exit | Database connection permanently lost, out of memory | Yes |
| `ERROR` | 50 | Operation failed, requires attention | Payment processing failed, external API unreachable | Yes |
| `WARN` | 40 | Unexpected condition, system continues | Deprecated API called, high memory usage, retry attempt | Yes |
| `INFO` | 30 | Significant business events | User login, order placed, payment processed, deployment started | Yes |
| `DEBUG` | 20 | Diagnostic information for developers | SQL queries, cache hits/misses, request/response bodies | No (staging only) |
| `TRACE` | 10 | Fine-grained debugging | Function entry/exit, loop iterations, variable values | No (local dev only) |

**Rule:** Production log level is `INFO`. Never set production to `DEBUG` or `TRACE` — it creates excessive log volume and may expose sensitive data.

---

### 4.4 Structured Log Schema

Every log entry must conform to this JSON schema:

```json
{
  "timestamp": "2026-04-07T01:12:00.000Z",
  "level": "info",
  "service": "user-service",
  "version": "1.2.0",
  "environment": "production",
  "traceId": "4bf92f3577b34da6a3ce929d0e0e4736",
  "spanId": "00f067aa0ba902b7",
  "requestId": "req-550e8400",
  "message": "User authenticated successfully",
  "context": "AuthService",
  "userId": "user-123",
  "duration": 45,
  "metadata": {
    "method": "POST",
    "path": "/api/v1/auth/login",
    "statusCode": 200,
    "userAgent": "GateForge-Mobile/1.0"
  }
}
```

**Field descriptions:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `timestamp` | ISO-8601 string | Yes | When the event occurred |
| `level` | string | Yes | Log level (fatal, error, warn, info, debug, trace) |
| `service` | string | Yes | Name of the microservice |
| `version` | string | Yes | Service version (from package.json) |
| `environment` | string | Yes | `development`, `staging`, `production` |
| `traceId` | string | Yes | OpenTelemetry trace ID for request correlation |
| `spanId` | string | No | OpenTelemetry span ID |
| `requestId` | string | No | Unique ID per HTTP request (from `X-Request-ID` header) |
| `message` | string | Yes | Human-readable description of the event |
| `context` | string | Yes | Class or module name where the log was emitted |
| `userId` | string | No | Authenticated user ID (if applicable) |
| `duration` | number | No | Operation duration in milliseconds |
| `metadata` | object | No | Additional structured data |

---

### 4.5 Correlation ID / Trace ID Propagation

Reference: [SigNoz — OpenTelemetry Trace ID vs Span ID](https://signoz.io/comparisons/opentelemetry-trace-id-vs-span-id/), [OneUptime — Distributed Tracing NestJS](https://oneuptime.com/blog/post/2026-02-17-distributed-tracing-nestjs-cloud-run-opentelemetry-cloud-trace/view)

#### How it works across GateForge services:

```
Client Request
    │
    │  X-Request-ID: req-123
    │  traceparent: 00-4bf92f35...-00f067aa...-01
    ▼
┌──────────────┐
│ API Gateway  │ ← Creates trace if none exists
│ (VM-3)       │
└──────┬───────┘
       │  Propagates traceparent header
       ▼
┌──────────────┐     ┌────────────────┐
│ User Service │ ──▶ │ Order Service  │
│ (VM-3)       │     │ (VM-3)         │
└──────────────┘     └────────────────┘
       │                     │
       ▼                     ▼
   [PostgreSQL]          [PostgreSQL]
```

#### OpenTelemetry Setup

```typescript
// tracing.ts — Must be imported BEFORE NestJS bootstraps
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { Resource } from '@opentelemetry/resources';
import { ATTR_SERVICE_NAME, ATTR_SERVICE_VERSION } from '@opentelemetry/semantic-conventions';

const sdk = new NodeSDK({
  resource: new Resource({
    [ATTR_SERVICE_NAME]: process.env.SERVICE_NAME || 'api-gateway',
    [ATTR_SERVICE_VERSION]: process.env.SERVICE_VERSION || '1.0.0',
  }),
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_ENDPOINT || 'http://localhost:4318/v1/traces',
  }),
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-http': {
        ignoreIncomingRequestHook: (req) =>
          req.url === '/health' || req.url === '/ready',
      },
    }),
  ],
});

sdk.start();
console.log('OpenTelemetry tracing initialized');

process.on('SIGTERM', () => {
  sdk.shutdown().then(() => process.exit(0));
});
```

#### Middleware to Inject Trace ID into Logs

```typescript
// middleware/trace-context.middleware.ts
import { Injectable, NestMiddleware } from '@nestjs/common';
import { Request, Response, NextFunction } from 'express';
import { trace, context } from '@opentelemetry/api';
import { v4 as uuidv4 } from 'uuid';

@Injectable()
export class TraceContextMiddleware implements NestMiddleware {
  use(req: Request, _res: Response, next: NextFunction): void {
    // Get or create request ID
    const requestId = (req.headers['x-request-id'] as string) || uuidv4();
    req.headers['x-request-id'] = requestId;

    // Extract trace ID from OpenTelemetry context
    const activeSpan = trace.getActiveSpan();
    const traceId = activeSpan?.spanContext().traceId || 'no-trace';
    const spanId = activeSpan?.spanContext().spanId || 'no-span';

    // Attach to request for downstream use
    (req as any).traceId = traceId;
    (req as any).spanId = spanId;
    (req as any).requestId = requestId;

    next();
  }
}
```

---

### 4.6 What to Log vs What NOT to Log

#### What to Log

| Category | Examples |
|----------|---------|
| **Request/Response** | Method, URL, status code, response time (sanitized bodies) |
| **Errors** | Full stack traces for 5xx, structured messages for 4xx |
| **Business events** | User registration, order placement, payment success/failure |
| **Security events** | Login attempts (success/failure), permission denied, token refresh |
| **Performance** | Slow queries (>500ms), high memory usage, cache hit ratios |
| **System lifecycle** | Service start/stop, health check failures, connection pool events |

#### What NOT to Log

| Never Log | Reason |
|-----------|--------|
| Passwords (plain or hashed) | Security risk |
| JWT tokens or refresh tokens | Session hijacking risk |
| Credit card numbers | PCI-DSS violation |
| Personal Identifiable Information (PII) | GDPR/privacy violation |
| API keys or secrets | Credential exposure |
| Full request bodies with sensitive fields | Data leakage |
| Database connection strings | Infrastructure exposure |

---

### 4.7 Log Redaction Patterns

```typescript
// utils/log-redaction.ts

/** Fields to automatically redact in log output. */
export const REDACT_PATHS = [
  'req.headers.authorization',
  'req.headers.cookie',
  'req.body.password',
  'req.body.confirmPassword',
  'req.body.creditCardNumber',
  'req.body.cvv',
  'req.body.ssn',
  'req.body.token',
  'req.body.refreshToken',
  'res.body.accessToken',
  'res.body.refreshToken',
  '*.password',
  '*.secret',
  '*.apiKey',
  '*.creditCard',
];

// Usage in Pino config
const pinoConfig = {
  redact: {
    paths: REDACT_PATHS,
    censor: '[REDACTED]',
  },
};
```

---

### 4.8 Pino Configuration for NestJS

Reference: [GitHub — nestjs-pino](https://github.com/iamolegga/nestjs-pino), [Tom Ray — NestJS Logging](https://www.tomray.dev/nestjs-logging)

```typescript
// app.module.ts
import { Module } from '@nestjs/common';
import { LoggerModule } from 'nestjs-pino';
import { REDACT_PATHS } from './utils/log-redaction';

@Module({
  imports: [
    LoggerModule.forRoot({
      pinoHttp: {
        // Log level based on environment
        level: process.env.LOG_LEVEL || (process.env.NODE_ENV === 'production' ? 'info' : 'debug'),

        // Structured JSON in production, pretty-print in development
        transport: process.env.NODE_ENV !== 'production'
          ? {
              target: 'pino-pretty',
              options: {
                colorize: true,
                singleLine: false,
                translateTime: 'SYS:yyyy-mm-dd HH:MM:ss.l',
              },
            }
          : undefined,

        // Redact sensitive fields
        redact: {
          paths: REDACT_PATHS,
          censor: '[REDACTED]',
        },

        // Custom serializers
        serializers: {
          req: (req) => ({
            id: req.id,
            method: req.method,
            url: req.url,
            query: req.query,
            remoteAddress: req.remoteAddress,
          }),
          res: (res) => ({
            statusCode: res.statusCode,
          }),
        },

        // Add custom fields to every log entry
        customProps: (req) => ({
          service: process.env.SERVICE_NAME || 'api-gateway',
          version: process.env.SERVICE_VERSION || '1.0.0',
          environment: process.env.NODE_ENV || 'development',
          traceId: (req as any).traceId || req.headers['x-trace-id'] || 'none',
          requestId: req.headers['x-request-id'] || req.id,
        }),

        // Generate request IDs
        genReqId: (req) =>
          (req.headers['x-request-id'] as string) || require('crypto').randomUUID(),

        // Auto-logging configuration
        autoLogging: {
          ignore: (req) => req.url === '/health' || req.url === '/ready',
        },
      },
    }),
  ],
})
export class AppModule {}
```

**Bootstrap with Pino:**

```typescript
// main.ts
import { NestFactory } from '@nestjs/core';
import { Logger, LoggerErrorInterceptor } from 'nestjs-pino';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });

  // Use Pino as the application logger
  app.useLogger(app.get(Logger));

  // Automatically log errors with stack traces
  app.useGlobalInterceptors(new LoggerErrorInterceptor());

  await app.listen(3000);
}
bootstrap();
```

---

### 4.9 Request/Response Logging Interceptor

```typescript
// interceptors/logging.interceptor.ts
import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
  Logger,
} from '@nestjs/common';
import { Observable, tap } from 'rxjs';
import { Request, Response } from 'express';

@Injectable()
export class RequestLoggingInterceptor implements NestInterceptor {
  private readonly logger = new Logger('HTTP');

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const ctx = context.switchToHttp();
    const request = ctx.getRequest<Request>();
    const startTime = Date.now();

    const { method, url, ip } = request;
    const userAgent = request.get('user-agent') || 'unknown';
    const controller = context.getClass().name;
    const handler = context.getHandler().name;

    this.logger.log({
      message: 'Incoming request',
      method,
      url,
      ip,
      userAgent,
      controller,
      handler,
      traceId: (request as any).traceId,
    });

    return next.handle().pipe(
      tap({
        next: () => {
          const response = ctx.getResponse<Response>();
          const duration = Date.now() - startTime;

          this.logger.log({
            message: 'Request completed',
            method,
            url,
            statusCode: response.statusCode,
            duration,
            controller,
            handler,
            traceId: (request as any).traceId,
          });
        },
        error: (error) => {
          const duration = Date.now() - startTime;

          this.logger.error({
            message: 'Request failed',
            method,
            url,
            statusCode: error.status || 500,
            duration,
            errorName: error.name,
            errorMessage: error.message,
            controller,
            handler,
            traceId: (request as any).traceId,
          });
        },
      }),
    );
  }
}
```

---

### 4.10 Log Aggregation & Retention

#### Stack: Loki + Grafana (GateForge Standard)

GateForge uses Grafana Loki for log aggregation, integrated with Prometheus for metrics and Grafana for visualization.

```yaml
# docker-compose.logging.yml
services:
  loki:
    image: grafana/loki:latest
    ports:
      - "3100:3100"
    volumes:
      - loki-data:/loki
    command: -config.file=/etc/loki/local-config.yaml

  promtail:
    image: grafana/promtail:latest
    volumes:
      - /var/log:/var/log:ro
      - ./promtail-config.yml:/etc/promtail/config.yml
    command: -config.file=/etc/promtail/config.yml

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-data:/var/lib/grafana
```

#### Pino Transport to Loki

```typescript
// For production, pipe Pino output to Loki via pino-loki transport
// In docker-compose, use Promtail to tail stdout logs from containers
// This is the preferred approach for containerized deployments
```

#### Log Retention Policies

| Environment | Retention | Storage |
|-------------|-----------|---------|
| Development | 7 days | Local disk |
| Staging | 30 days | Loki (compressed) |
| Production | 90 days (hot) + 1 year (cold) | Loki + S3 archival |

**Rules:**
- [ ] All logs shipped to centralized Loki instance
- [ ] No local log files in production containers (stdout only)
- [ ] Log rotation handled by container orchestrator (Kubernetes)
- [ ] Alerts configured for ERROR and FATAL log spikes
- [ ] Security-sensitive logs retained for minimum 1 year (audit compliance)

---

### 4.11 Performance Impact

| Technique | Impact |
|-----------|--------|
| **Async logging** (Pino default) | Logs are written via worker thread — zero impact on event loop |
| **Avoid string concatenation** | Use structured objects: `logger.info({ userId }, 'User created')` not `` logger.info(`User ${userId} created`) `` |
| **Log level gating** | Check level before expensive serialization: Pino handles this automatically |
| **Sampling** | For high-volume TRACE/DEBUG logs, use probabilistic sampling in production |
| **Batch transport** | Pino transports can batch writes to reduce I/O syscalls |

Reference: [AppSignal — Best Practices for Logging in Node.js](https://blog.appsignal.com/2021/09/01/best-practices-for-logging-in-nodejs.html)

---

## 5. Developer Task Workflow

### 5.1 Receiving Tasks from System Architect

Developer agents receive tasks exclusively from the System Architect (VM-1, port 18789). Each task arrives as a structured JSON payload via the Lobster pipeline.

#### Incoming Task Schema

```json
{
  "taskId": "TASK-042",
  "type": "feature",
  "priority": "high",
  "assignedTo": "dev-01",
  "title": "Implement user registration endpoint",
  "description": "Create POST /api/v1/auth/register with email verification",
  "blueprintRef": "blueprint/modules/auth/registration.md",
  "dependencies": ["TASK-040", "TASK-041"],
  "acceptanceCriteria": [
    "Endpoint accepts CreateUserDto with validation",
    "Sends verification email via notification-service",
    "Returns 201 with user ID (no password in response)",
    "Rate limited to 5 requests per minute per IP"
  ],
  "deadline": "2026-04-07T12:00:00Z",
  "estimatedMinutes": 120
}
```

#### Task Reception Checklist

- [ ] Verify `taskId` format is `TASK-XXX`
- [ ] Check `dependencies` — all must have status `completed`
- [ ] Locate and read the `blueprintRef` document
- [ ] Identify integration points (other services, external APIs)
- [ ] Estimate if task is achievable within `estimatedMinutes` (max 600s active coding)
- [ ] If blocked, report immediately (do not wait)

---

### 5.2 Reading the Blueprint Before Coding

The Blueprint is the **single source of truth** for all implementation details. It is owned by the System Architect and stored in the project repository.

**Process:**

1. **Read the referenced blueprint section** specified in `blueprintRef`
2. **Identify the module boundary** — what this service owns vs what other services own
3. **Review API contracts** — OpenAPI specs for endpoints, proto files for gRPC
4. **Check data models** — entity definitions, database schema
5. **Note integration points** — which services to call and via what protocol
6. **Review security requirements** — authentication, authorization, rate limiting

```
BEFORE writing any code:
  1. Read: blueprintRef document
  2. Read: libs/common/interfaces/ for shared types
  3. Read: relevant OpenAPI spec (if extending existing endpoints)
  4. Read: database migration history for schema context
  5. Confirm: no conflicting work from other dev agents
```

---

### 5.3 Structured Completion Report

Upon completing a task, submit a structured JSON report. This is mandatory for the QC pipeline.

```json
{
  "taskId": "TASK-042",
  "status": "completed",
  "completedAt": "2026-04-07T03:45:00Z",
  "deliverables": [
    {
      "type": "code",
      "filename": "apps/api-gateway/src/modules/auth/auth.controller.ts",
      "summary": "Added POST /api/v1/auth/register endpoint with validation"
    },
    {
      "type": "code",
      "filename": "apps/api-gateway/src/modules/auth/dto/register.dto.ts",
      "summary": "CreateUserDto with email, password, firstName, lastName validation"
    },
    {
      "type": "code",
      "filename": "apps/api-gateway/src/modules/auth/auth.service.ts",
      "summary": "Registration logic with email verification trigger"
    },
    {
      "type": "code",
      "filename": "apps/api-gateway/src/modules/auth/auth.controller.spec.ts",
      "summary": "Unit tests for registration endpoint (8 test cases)"
    },
    {
      "type": "api-doc",
      "filename": "docs/openapi/auth.yaml",
      "summary": "Updated OpenAPI spec with POST /register endpoint"
    }
  ],
  "gitBranch": "feature/TASK-042-user-registration",
  "integrationPoints": [
    {
      "targetModule": "notification-service",
      "interface": "event",
      "contract": "events/user-registered.event.ts"
    },
    {
      "targetModule": "user-service",
      "interface": "REST",
      "contract": "docs/openapi/users.yaml"
    }
  ],
  "testRequirements": [
    "Unit test: registration with valid data returns 201",
    "Unit test: registration with existing email returns 409",
    "Unit test: registration with weak password returns 400",
    "Unit test: registration rate limit triggers after 5 requests",
    "Integration test: full registration flow with email verification"
  ],
  "metrics": {
    "linesAdded": 342,
    "linesRemoved": 12,
    "filesChanged": 8,
    "testsPassed": 8,
    "testCoverage": 92.5
  },
  "notes": "Used event-based communication for notification-service integration. Email templates need to be configured by the operator."
}
```

---

### 5.4 Handling Blocked Status

When a task cannot proceed, immediately report a `blocked` status with dependencies:

```json
{
  "taskId": "TASK-042",
  "status": "blocked",
  "blockedAt": "2026-04-07T02:15:00Z",
  "blockedReason": "Dependency TASK-041 (user-service CreateUser endpoint) not yet completed",
  "blockedBy": [
    {
      "taskId": "TASK-041",
      "description": "user-service CreateUser endpoint is required for registration flow",
      "assignedTo": "dev-02",
      "currentStatus": "in-progress"
    }
  ],
  "partialDeliverables": [
    {
      "type": "code",
      "filename": "apps/api-gateway/src/modules/auth/dto/register.dto.ts",
      "summary": "DTO and validation completed (can proceed independently)"
    }
  ],
  "suggestedAction": "Complete TASK-041 first, then unblock this task",
  "canPartiallyProceed": true,
  "partialProceedPlan": "Will implement controller and DTO; service layer integration pending TASK-041"
}
```

**Blocked Status Rules:**
1. Report `blocked` status within **60 seconds** of identifying the blocker
2. Always include `blockedBy` with the dependency task ID
3. If partial work is possible, set `canPartiallyProceed: true` and continue with what's available
4. Never wait silently — the pipeline assumes progress unless told otherwise
5. Maximum 3 retries per task before escalation to human (the end-user)

---

### 5.5 Integration Testing Coordination with QC Agents

QC agents (VM-4, MiniMax 2.7) validate developer output. Coordination follows this protocol:

#### Handoff Process

```
Developer (VM-3)                    QC Agent (VM-4)
     │                                    │
     │  1. Push code to feature branch    │
     │  2. Submit completion report       │
     │────────────────────────────────────▶│
     │                                    │  3. Pull feature branch
     │                                    │  4. Run automated tests
     │                                    │  5. Run linting/formatting checks
     │                                    │  6. Verify acceptance criteria
     │                                    │  7. Check code quality metrics
     │◀────────────────────────────────────│
     │  8. Receive QC report              │
     │                                    │
     │  If PASS:                          │
     │    → Architect merges to develop   │
     │                                    │
     │  If FAIL:                          │
     │    → Developer receives fix list   │
     │    → Fix and resubmit             │
     │                                    │
```

#### QC Report Schema (received from QC agents)

```json
{
  "taskId": "TASK-042",
  "qcAgent": "qc-01",
  "verdict": "pass|fail|conditional-pass",
  "timestamp": "2026-04-07T04:00:00Z",
  "checks": {
    "compilation": { "status": "pass", "details": "Zero TypeScript errors" },
    "unitTests": { "status": "pass", "passed": 8, "failed": 0, "coverage": 92.5 },
    "linting": { "status": "pass", "errors": 0, "warnings": 2 },
    "formatting": { "status": "pass" },
    "securityScan": { "status": "pass", "vulnerabilities": 0 },
    "acceptanceCriteria": {
      "status": "pass",
      "criteria": [
        { "description": "Endpoint accepts CreateUserDto", "met": true },
        { "description": "Sends verification email", "met": true },
        { "description": "Returns 201 with user ID", "met": true },
        { "description": "Rate limited to 5 req/min", "met": true }
      ]
    }
  },
  "issues": [],
  "recommendations": [
    "Consider adding request body size validation in middleware"
  ]
}
```

#### Handling QC Failures

When a QC report comes back with `verdict: "fail"`:

1. Read each failed check and associated `issues` array
2. Create a fix branch: `fix/TASK-042-qc-feedback`
3. Address each issue systematically
4. Re-run local tests to verify fixes
5. Resubmit completion report with `status: "needs-review"` and reference the original QC report

```json
{
  "taskId": "TASK-042",
  "status": "needs-review",
  "resubmission": true,
  "previousQcReport": "qc-report-TASK-042-v1.json",
  "fixesSummary": [
    "Fixed: Added null check for user.profile in response serialization",
    "Fixed: Increased test coverage from 72% to 92.5%",
    "Fixed: Removed hardcoded rate limit value, moved to config"
  ],
  "deliverables": [ /* updated file list */ ],
  "gitBranch": "feature/TASK-042-user-registration"
}
```

---

## Appendix A: Quick Reference Card

### Environment Variables Template

```bash
# .env.example
# Application
NODE_ENV=development
PORT=3000
SERVICE_NAME=api-gateway
SERVICE_VERSION=1.0.0

# Database (PostgreSQL)
DB_HOST=localhost
DB_PORT=5432
DB_NAME=gateforge
DB_USERNAME=gateforge
DB_PASSWORD=change-me

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# JWT
JWT_ACCESS_SECRET=change-me-access-secret
JWT_REFRESH_SECRET=change-me-refresh-secret
JWT_ACCESS_EXPIRATION=15m
JWT_REFRESH_EXPIRATION=7d

# Logging
LOG_LEVEL=info

# OpenTelemetry
OTEL_EXPORTER_ENDPOINT=http://localhost:4318/v1/traces

# CORS
FRONTEND_URL=http://localhost:3000
```

### GateForge Network Reference

| VM | Role | Tailscale Domain | Port |
|----|------|------------------|------|
| VM-1 | System Architect | `tonic-architect.sailfish-bass.ts.net` | 18789 |
| VM-2 | System Designer | `tonic-designer.sailfish-bass.ts.net` | 18789 |
| VM-3 | Developers (dev-01..dev-N) | `tonic-developer.sailfish-bass.ts.net` | 18789 |
| VM-4 | QC Agents (qc-01..qc-N) | `tonic-qc.sailfish-bass.ts.net` | 18789 |
| VM-5 | Operator | `tonic-operator.sailfish-bass.ts.net` | 18789 |

> All inter-VM URLs use HTTPS via Tailscale Serve, e.g. `https://tonic-designer.sailfish-bass.ts.net:18789/hooks/agent`. Raw 100.x.x.x Tailscale IPs are not used anywhere in this project.

---

## Appendix B: Sources & References

- [NestJS Official Documentation](https://docs.nestjs.com/)
- [NestJS Microservices Guide — Talent500](https://talent500.com/blog/nestjs-microservices-guide/)
- [Build Microservice Architecture with NestJS — Telerik](https://www.telerik.com/blogs/build-microservice-architecture-nestjs)
- [Custom Exception Filters in NestJS — OneUptime](https://oneuptime.com/blog/post/2026-01-25-custom-exception-filters-nestjs/view)
- [nestjs-pino — GitHub](https://github.com/iamolegga/nestjs-pino)
- [NestJS Logger with Pino — Tom Ray](https://www.tomray.dev/nestjs-logging)
- [Pino vs Winston — BetterStack](https://betterstack.com/community/guides/scaling-nodejs/pino-vs-winston/)
- [Pino vs Winston — DEV Community](https://dev.to/wallacefreitas/pino-vs-winston-choosing-the-right-logger-for-your-nodejs-application-369n)
- [TypeScript Best Practices — AWS Prescriptive Guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/best-practices-cdk-typescript-iac/typescript-best-practices.html)
- [React & Next.js Best Practices 2025 — Strapi](https://strapi.io/blog/react-and-nextjs-in-2025-modern-best-practices)
- [Mastering React Query 2025 — DEV Community](https://dev.to/jdavissoftware/mastering-react-query-in-2025-a-deep-dive-into-data-fetching-for-modern-apps-22jf)
- [React Query vs TanStack Query vs SWR — Refine](https://refine.dev/blog/react-query-vs-tanstack-query-vs-swr-2025/)
- [React Native Project Structure — Tricentis](https://www.tricentis.com/learn/react-native-project-structure)
- [React Native Folder Structure — DEV Community](https://dev.to/ersuman/the-ultimate-guide-to-the-best-folder-structure-in-react-native-dc4)
- [Mobile Development Best Practices — NextNative](https://nextnative.dev/blog/mobile-development-best-practices)
- [Cross-Platform Best Practices — Mind IT Systems](https://minditsystems.com/best-practices-for-cross-platform-mobile-app-development/)
- [Mobile App Development 2025 — DEV Community](https://dev.to/sajan_kumarsingh_b556129/the-complete-guide-to-mobile-app-development-in-2025-native-cross-platform-and-hybrid-approaches-50om)
- [Offline-First Architecture React Native — OneUptime](https://oneuptime.com/blog/post/2026-01-15-react-native-offline-architecture/view)
- [Microservices Observability — Dash0](https://www.dash0.com/knowledge/microservices-observability)
- [Log Management in Microservices — Observo AI](https://www.observo.ai/post/log-management-and-observability-in-microservices)
- [Best Practices for Logging in Node.js — AppSignal](https://blog.appsignal.com/2021/09/01/best-practices-for-logging-in-nodejs.html)
- [NestJS Logger Documentation](https://docs.nestjs.com/techniques/logger)
- [OpenTelemetry Trace ID vs Span ID — SigNoz](https://signoz.io/comparisons/opentelemetry-trace-id-vs-span-id/)
- [Distributed Tracing NestJS — OneUptime](https://oneuptime.com/blog/post/2026-02-17-distributed-tracing-nestjs-cloud-run-opentelemetry-cloud-trace/view)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [React Folder Structure 2025 — LinkedIn](https://www.linkedin.com/pulse/ultimate-react-folder-structure-2025-sujan-adhikari-zxvzf)

---

---

## Appendix: Managed Output Documents

Developer agents produce and maintain the following documents in the Blueprint repository.

### Document Ownership Map

| Document | Path in Blueprint Repo | When to Create | When to Update |
|----------|----------------------|----------------|----------------|
| Module Documentation | `development/modules/<module>.md` | When assigned a new module | After every feature added, API changed, or dependency updated |
| Coding Standards | `development/coding-standards.md` | Reference only (Architect maintains) | Propose changes via structured report |

### Output Rules

1. **Use the module template** from `gateforge-blueprint-template/development/modules/README.md` — every module must have:
   - API endpoints table
   - Database tables owned
   - Events published/consumed
   - Dependencies on other modules
   - Change log

2. **Structured completion report to Architect**: After every task, produce:

```json
{
  "taskId": "TASK-NNN",
  "type": "implementation",
  "status": "completed",
  "module": "auth",
  "branch": "feature/TASK-001-jwt-login",
  "filesChanged": 12,
  "testsAdded": 8,
  "testsPass": true,
  "documentsUpdated": ["development/modules/auth.md"],
  "integrationPoints": ["patient-records service via REST", "Redis for token cache"],
  "testRequirements": ["JWT token generation", "refresh token rotation", "role-based access"],
  "openQuestions": [],
  "blockers": []
}
```

3. **Git commit convention**: Conventional commits as defined in Section 3.7
4. **Branch naming**: `feature/TASK-<NNN>-<description>` — never push to main/develop directly
5. **API documentation**: If API endpoints changed, update the relevant OpenAPI spec in `architecture/api-specifications/`

### Code → Document Traceability

Every code change must be traceable back to a backlog item:
- Code commit message references `TASK-NNN` or `BUG-NNN`
- Module documentation references the related functional requirements (FR-IDs)
- Test requirements in the completion report link to QA test cases

---

*This document is maintained by the GateForge System Architect (VM-1) and applies to all Developer Agents on VM-3. For questions or updates, route through the System Architect via the Lobster pipeline.*
