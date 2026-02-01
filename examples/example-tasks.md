# Implementation Tasks - Example

This is a complete example of a `.llm/tasks.md` file showing the recommended format for AI-assisted development.

## Project Context

- **Architecture**: Hexagonal (core/ports/adapters) with clear domain boundaries
- **Language**: TypeScript/Node.js
- **Framework**: Express for HTTP API
- **Database**: PostgreSQL with TypeORM
- **Testing**: Jest with TDD approach
- **Error Handling**: Result<T, E> pattern for explicit error types
- **Documentation**: JSDoc with examples on all public APIs

## Shared Types Registry

> This section grows as new reusable types are discovered during implementation.
> Keep it organized by domain and link to source files.

### Core Types

- `Result<T, E>`: Success/failure union (src/core/result.ts)
  - Used by: All domain operations
  - Pattern: Return `Ok(value)` for success, `Err(error)` for failure
- `ApiError`: Discriminated union of API-specific errors (src/api/errors.ts)
  - Used by: All HTTP handlers
  - Variants: Unauthorized, NotFound, ValidationError, ServerError

### Authentication Types

- `AuthToken`: JWT token wrapper (src/auth/types.ts)
- `Principal`: Authenticated user context (src/auth/types.ts)
- `Credentials`: Email + password pair (src/auth/types.ts)

### Domain Types

(Populated during implementation)

## Rules & Tips

> Patterns and conventions discovered while implementing. Add to this as you work.

### TDD Workflow

- Write failing test first, then implementation
- Each commit includes both test and implementation
- Keep tests focused on behavior, not implementation details

### Error Handling

- Never use generic `Error` - always use typed `ApiError`
- Wrap external errors: `ApiError.fromDb(nativeError)`
- Log errors with full context before returning to client

### API Patterns

- All endpoints return `{ data?: T, error?: ApiError }` structure
- Use HTTP status codes: 200 OK, 201 Created, 400 Bad Request, 401 Unauthorized, 404 Not Found, 500 Server Error
- Include error message only if it's safe for client (no stack traces)

## Task List

- [ ] 1.0 Implement Core Type System
  - Context:
    - Defines foundational types used by all other modules
    - File: `src/core/result.ts`, `src/core/types.ts`
    - Dependencies: None (foundation layer)
    - Must complete before any domain work
  - Assertions:
    - `Ok<T>` creates success result
    - `Err<E>` creates failure result
    - `.map()` chains success operations
    - `.mapErr()` chains error operations
    - `.getOrElse()` extracts value with default
  - [ ] 1.1 Implement Result<T, E> type and helpers
    - Create union type: `Result<T, E> = Ok<T> | Err<E>`
    - Add helper functions: ok(), err(), isOk(), isErr()
    - Add methods: map(), mapErr(), flatMap(), getOrElse()
    - Add TypeScript utilities: ResultType<R>, ExtractOk<R>
  - [ ] 1.2 Implement branded types for validation
    - Create Email branded type
    - Create UserId branded type
    - Add parsing functions with validation
  - [ ] 1.3 Write comprehensive tests for type utilities
    - Test Result monad laws
    - Test type narrowing with type guards
    - Test branded type validation

- [ ] 2.0 Implement Authentication Domain
  - Context:
    - Auth types and repositories
    - File: `src/auth/`
    - Dependencies: Core types (task 1.0)
    - Reuses: Result<T, E>, Email, UserId
    - Constraint: All operations return explicit error types
  - Assertions:
    - docs/spec/interfaces/auth.md test cases #1-8
  - [ ] 2.1 Create auth types and port interfaces
    - Types: Credentials, AuthToken, Principal
    - Ports: CredentialStore, TokenIssuer
    - Errors: InvalidCredentials, TokenExpired, UserNotFound
  - [ ] 2.2 Implement in-memory credential store (adapter)
    - Test doubles for development and testing
    - Not production use
  - [ ] 2.3 Implement JWT token issuer
    - Token generation with expiry
    - Token validation
    - Principal extraction from token

- [ ] 3.0 Implement API Layer
  - Context:
    - HTTP endpoints and middleware
    - File: `src/api/`
    - Dependencies: Auth (task 2.0), Core types (task 1.0)
    - Public API for clients
  - Assertions:
    - API returns proper status codes
    - All errors serialized as JSON
    - Authentication required for protected endpoints
  - [ ] 3.1 Setup Express app with middleware
    - CORS configuration
    - Body parser (JSON)
    - Error handling middleware
    - Request logging middleware
  - [ ] 3.2 Implement authentication endpoints
    - POST /auth/login - Authenticate user
    - POST /auth/refresh - Refresh token
    - POST /auth/logout - Invalidate token (optional)
  - [ ] 3.3 Implement protected endpoint example
    - GET /api/profile - Get current user profile
    - Requires valid token
    - Returns user info or 401 if unauthorized

- [ ] 4.0 Add Database Integration
  - Context:
    - Persistent storage layer
    - File: `src/db/`
    - Dependencies: Auth (task 2.0)
    - Note: Use TypeORM migrations for schema
  - Assertions:
    - Credentials persist across restarts
    - Concurrent access is safe (no race conditions)
  - [ ] 4.1 Setup TypeORM configuration
    - Database connection
    - Migrations directory
    - Entity mapping
  - [ ] 4.2 Implement User entity and repository
    - User table schema
    - Password hashing (bcrypt)
    - Query operations
  - [ ] 4.3 Create and run initial migration
    - Create users table
    - Add sample data for testing

- [ ] 5.0 Add API Documentation
  - Context:
    - OpenAPI/Swagger documentation
    - File: `docs/openapi.yaml`
    - For client implementation teams
  - Assertions:
    - All endpoints documented
    - Example requests and responses
    - Error cases documented
  - [ ] 5.1 Create OpenAPI schema
    - Define all endpoints
    - Define all models
    - Define error responses
  - [ ] 5.2 Setup Swagger UI
    - `/api/docs` endpoint
    - Interactive API exploration

- [ ] 6.0 Setup CI/CD Pipeline
  - Context:
    - Automated testing and deployment
    - File: `.github/workflows/`
    - Required for production safety
  - Assertions:
    - Tests run on every PR
    - Coverage > 80%
    - No secrets in code
  - [ ] 6.1 Create test workflow
    - Run Jest tests
    - Generate coverage report
    - Fail if coverage < 80%
  - [ ] 6.2 Create build workflow
    - Compile TypeScript
    - Run linter
    - Check for unused code
  - [ ] 6.3 Create deploy workflow (optional)
    - Build Docker image
    - Push to registry
    - Deploy to staging

## Implementation Guidelines

### Code Review Checklist

- [ ] Tests written and passing
- [ ] No ESLint warnings
- [ ] TypeScript strict mode passes
- [ ] New types added to Shared Types Registry
- [ ] JSDoc comments on all public functions
- [ ] Error handling follows Result pattern
- [ ] No console.log in code (use logger)
- [ ] Performance acceptable (< 100ms for typical operations)

### Commit Message Format

```
feat(auth): implement JWT token validation (task 2.2)

Add JWT token parsing and validation in the TokenIssuer adapter.
Validates expiry, signature, and claims. Returns proper error
types (TokenExpired, InvalidSignature, MissingClaims).

Implements: tests/auth/jwt.test.ts - all passing
Coverage: 85% auth/ module
```

### Definition of Done for a Task

1. ✅ All subtasks completed
2. ✅ Tests passing with > 80% coverage
3. ✅ ESLint and TypeScript checks pass
4. ✅ New types registered in Shared Types Registry (if applicable)
5. ✅ Updated Rules & Tips (if new pattern discovered)
6. ✅ Code reviewed and merged
7. ✅ Updated `.llm/tasks.md` - mark task as `[x]`

## Notes for AI Agents

### Before Starting Implementation

1. Read the Project Context section above
2. Check Shared Types Registry for reusable components
3. Review Rules & Tips for project patterns
4. Read the complete task including context and assertions

### During Implementation

1. Write test first (TDD), then implementation
2. Use types from Result pattern for error handling
3. Reference assertions as acceptance criteria
4. Commit frequently with clear messages

### When Stuck

1. Check if required types exist in Shared Types Registry
2. Look at similar implementations in the codebase
3. Review the referenced spec files
4. Ask for clarification if task is ambiguous

### After Completing a Task

1. Run full test suite: `npm test`
2. Check coverage: `npm run coverage`
3. Update Shared Types Registry if creating reusable types
4. Update Rules & Tips if discovering a project pattern
5. Mark task as complete: Change `[ ]` to `[x]`
6. Move to next unchecked task
