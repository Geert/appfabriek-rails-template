# AppFabriek Rails Template — Architecture Guide

This file provides architectural guidance for AI coding agents and developers. It documents the canonical patterns used in projects generated with the **AppFabriek Rails Template**.

When in doubt about how to implement something, consult this document and follow the patterns described below.

## Development Commands

```bash
bin/setup              # Initial setup (installs gems, creates DB, loads schema)
bin/dev                # Start development server
bin/rails test         # Run unit tests
bin/rails test:system  # Run system tests (Capybara + Selenium)
bin/ci                 # Run full CI suite (style, security, tests)
PARALLEL_WORKERS=1 bin/rails test  # Disable parallelization if needed
```

## Architecture Overview

### Authentication — Passwordless Magic Links

No passwords. Users receive a 6-character, 15-minute magic link via email.

**Core models**: `Identity` (global, email-based) → `User` (account-scoped) → `Session` (signed cookie)

**Flow**:
1. User submits email → `Identity#send_magic_link` creates `MagicLink` and sends email
2. User clicks link → code consumed, `Session` created, signed cookie set
3. Bearer token auth also supported for API access

**Controller concern**: `Authentication` — included in `ApplicationController`
- `require_authentication` — default before_action
- `allow_unauthenticated_access` — skip for public actions
- `require_unauthenticated_access` — redirect logged-in users

### Multi-Tenancy — URL Path Based

Each Account has a numeric `external_account_id` in the URL path:
```
/1234567/boards/...  →  Account 1234567, path /boards/...
```

**Middleware** (`AccountSlug::Extractor`): Extracts account ID from `PATH_INFO`, moves it to `SCRIPT_NAME`, sets `Current.account`. Rails sees the app as "mounted" at the account prefix.

**Current attributes** (`Current < ActiveSupport::CurrentAttributes`):
```ruby
Current.account    # Current tenant
Current.user       # Current user within this account
Current.identity   # Global identity (email)
Current.session    # Current session
```

**Switching context**:
```ruby
Current.with_account(account) { ... }
Current.without_account { ... }
```

**Multi-tenant toggle**: `MULTI_TENANT=true` env var allows multiple signups.

### Database — UUID Primary Keys

All tables use UUID primary keys (binary(16), UUIDv7 format):

```ruby
# In migrations:
create_table :things, id: :uuid do |t|
  t.string :name
  t.timestamps
end

# UUIDs auto-generated on create — no manual assignment needed
```

Works with both SQLite (blob(16)) and MySQL (binary(16)) via custom type adapters.

**Fixture note**: Fixtures use deterministic UUIDs from CRC32 hash of fixture label, ensuring stable ordering in tests (`.first`/`.last` work correctly).

### Background Jobs — Solid Queue

Database-backed job queue. No Redis required.

**Key pattern**: Account context is automatically serialized into jobs and restored before execution.

```ruby
# Jobs delegate to model methods
class SomeJob < ApplicationJob
  def perform(record)
    record.do_the_thing_now
  end
end

# Models enqueue with _later convention
class SomeModel
  def do_the_thing_later
    SomeJob.perform_later(self)
  end

  def do_the_thing_now
    # actual logic here
  end
end
```

Jobs are automatically enqueued after the current database transaction commits (`enqueue_after_transaction_commit = true`).

**Recurring jobs**: Defined in `config/recurring.yml`. Always include cleanup jobs:
```yaml
production:
  cleanup_magic_links:
    command: "MagicLink.cleanup"
    schedule: every 4 hours
  clear_solid_queue_finished_jobs:
    command: "SolidQueue::Job.clear_finished_in_batches"
    schedule: every hour at minute 12
```

### Event System — Audit Trail

All significant domain actions create an `Event` record:
```ruby
after_create_commit { events.create!(action: :created, creator: Current.user) }
```

Events drive:
- Activity timeline
- Notifications to watchers
- Webhook dispatches
- Audit logging

### Controller Patterns — Pure CRUD

**No custom actions**. When an action doesn't map to CRUD, create a new resource:

```ruby
# Bad
resources :cards do
  post :close
  post :reopen
end

# Good
resources :cards do
  resource :closure    # Cards::ClosuresController#create / destroy
  resource :column     # Cards::ColumnsController#update
end
```

**Thin controllers**: Controllers call model methods directly. No service objects unless truly justified.

```ruby
class Cards::ClosuresController < ApplicationController
  def create
    @card.close
  end

  def destroy
    @card.reopen
  end
end
```

**Multi-format responses**:
```ruby
respond_to do |format|
  format.html { redirect_to @card }
  format.turbo_stream
  format.json { render :show }
end
```

### Model Composition — Concerns

Break large models into single-responsibility concerns:

```ruby
# app/models/card.rb
class Card < ApplicationRecord
  include Closeable, Assignable, Commentable, Eventable, Searchable, Taggable
end

# app/models/card/closeable.rb
module Card::Closeable
  extend ActiveSupport::Concern

  included do
    scope :open, -> { where(closed_at: nil) }
    scope :closed, -> { where.not(closed_at: nil) }
  end

  def close
    update!(closed_at: Time.current)
    events.create!(action: :closed, creator: Current.user)
  end

  def reopen
    update!(closed_at: nil)
    events.create!(action: :reopened, creator: Current.user)
  end
end
```

### Secrets Management — Kamal + ENV

**Never hardcode secrets. Never commit secrets.**

All secrets injected at deploy time via Kamal:

```yaml
# config/deploy.yml
env:
  secret:          # From .kamal/secrets (never committed)
    - SECRET_KEY_BASE
    - SMTP_USERNAME
    - SMTP_PASSWORD
  clear:           # Non-sensitive config (committed)
    BASE_URL: https://myapp.example.com
    MAILER_FROM_ADDRESS: hello@example.com
    SMTP_ADDRESS: mail.example.com
```

**`.kamal/secrets`** (gitignored, on developer machines):
```bash
SECRET_KEY_BASE=$(cat /dev/urandom | base64 | head -c 128)
SMTP_USERNAME=myuser
SMTP_PASSWORD=mypassword
```

**In app code**: Always use `ENV["KEY"]` with sensible fallbacks for development.

### Frontend — Importmap + Hotwire

No Node.js build step. No webpack. No Vite.

- **Importmap**: Pin npm packages as browser ESM imports
- **Turbo**: Page navigation + Turbo Frames + Turbo Streams for real-time updates
- **Stimulus**: Sprinkle JS behavior via controllers
- **Propshaft**: Asset pipeline (fast, simple)

```ruby
# config/importmap.rb
pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
```

### Deployment — Kamal

Docker containers, deployed via Kamal. No Kubernetes.

```bash
bin/kamal deploy          # Deploy to production
bin/kamal console         # Rails console in production
bin/kamal logs            # Tail production logs
```

**Dockerfile pattern**:
- Multi-stage build (build stage + runtime stage)
- Non-root user (uid 1000)
- jemalloc for memory optimization
- Thruster for HTTP/2 + asset serving
- `SECRET_KEY_BASE_DUMMY=1` for asset precompile

### Testing

- **Framework**: Minitest (not RSpec)
- **Fixtures**: YAML fixtures with auto-loading (not FactoryBot)
- **Account context**: Set `Current.account` in test setup
- **System tests**: Capybara + Selenium

```ruby
class SomeTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:my_account)
  end

  test "it does the thing" do
    card = cards(:my_card)
    card.close
    assert card.closed?
  end
end
```

**UUID fixtures**: Use deterministic label-based IDs — `.first`/`.last` ordering works correctly because fixture timestamps precede runtime records.

## Key File Locations

```
app/
  controllers/
    application_controller.rb       # Base controller (includes Authentication)
    concerns/
      authentication.rb             # Auth concern (magic links + bearer tokens)
  jobs/
    application_job.rb              # Base job (account context auto-injected)
  models/
    current.rb                      # CurrentAttributes (account, user, identity, session)
    identity.rb                     # Global user (email, magic links, sessions)
    magic_link.rb                   # 15-min expiring auth code
    session.rb                      # Signed cookie session

config/
  initializers/
    uuid_primary_keys.rb            # UUID PK support for SQLite + MySQL
    active_job.rb                   # Account context serialization for jobs
    tenanting/
      account_slug.rb               # URL-based multi-tenancy middleware
      multi_tenant.rb               # MULTI_TENANT env var toggle
  deploy.yml                        # Kamal deployment config
  recurring.yml                     # Solid Queue recurring jobs

db/
  schema.rb                         # Main schema
  migrate/                          # Migrations (UUID PKs throughout)

Dockerfile                          # Multi-stage production container
bin/
  dev                               # Development server script
  ci                                # Full CI suite runner
```

## Coding Conventions

See `STYLE.md` for full coding style guide. Key rules:

1. Expanded `if/else` over guard clauses (except early returns at method start)
2. Method order: class → public (initialize first) → private
3. Methods ordered vertically by invocation order
4. `!` only when non-bang counterpart exists
5. No newline after `private`, indent private methods
6. CRUD controllers only — no custom actions, create new resources
7. Thin controllers + rich models
8. Job classes are shallow — delegate to model methods
