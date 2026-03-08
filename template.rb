# AppFabriek Rails Template
#
# Usage: rails new myapp -m ~/code/appfabriek-rails-template/template.rb
#
# Sets up a new Rails app with AppFabriek's proven architectural patterns:
# - UUID primary keys (binary(16), works with SQLite + MySQL)
# - Passwordless magic link authentication
# - Current attributes (account, user, identity, session)
# - Solid Queue/Cable/Cache (no Redis)
# - Importmap + Turbo + Stimulus (no webpack/vite)
# - Propshaft asset pipeline
# - Kamal deployment configuration
# - Minitest + fixtures testing setup
# - CI script (rubocop + brakeman + bundler-audit + tests)

APPFABRIEK_TEMPLATE_DIR = File.expand_path("~/code/appfabriek-rails-template")

def template_file(path)
  File.join(APPFABRIEK_TEMPLATE_DIR, path)
end

def copy_template(src, dest = src)
  copy_file template_file(src), dest
end

# ── Gems ─────────────────────────────────────────────────────────────────────

# Remove default gems that we replace
gsub_file "Gemfile", /^gem "sqlite3".*\n/, ""
gsub_file "Gemfile", /^gem "thruster".*\n/, ""

gem "sqlite3", "~> 2.0"                    # SQLite for development/OSS
gem "trilogy"                              # MySQL driver for production
gem "solid_queue"
gem "solid_cable"
gem "solid_cache"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "propshaft"
gem "bcrypt", "~> 3.1"
gem "geared_pagination"
gem "kamal", require: false
gem "thruster", require: false

gem_group :development do
  gem "letter_opener"
end

gem_group :development, :test do
  gem "rubocop-rails-omakase", require: false
end

gem_group :test do
  gem "capybara"
  gem "selenium-webdriver"
  gem "webmock"
  gem "mocha"
end

# ── Install gems ──────────────────────────────────────────────────────────────

after_bundle do
  # ── Core initializers ───────────────────────────────────────────────────────

  copy_template "config/initializers/uuid_primary_keys.rb"
  copy_template "config/initializers/active_job.rb"
  copy_template "config/initializers/multi_tenant.rb"
  copy_template "config/initializers/tenanting/account_slug.rb"

  # ── Models ──────────────────────────────────────────────────────────────────

  copy_template "app/models/current.rb"
  copy_template "app/models/identity.rb"
  copy_template "app/models/magic_link.rb"
  copy_template "app/models/session.rb"

  # ── Auth controller concern ──────────────────────────────────────────────────

  copy_template "app/controllers/concerns/authentication.rb"

  # Include Authentication in ApplicationController
  inject_into_class "app/controllers/application_controller.rb", "ApplicationController" do
    "  include Authentication\n"
  end

  # ── Mailers ─────────────────────────────────────────────────────────────────

  copy_template "app/mailers/magic_link_mailer.rb"

  # ── Migrations ──────────────────────────────────────────────────────────────

  generate "migration", "CreateIdentities email_address:string:uniq"
  generate "migration", "CreateSessions identity:references token_hash:string:uniq user_agent:string ip_address:string"
  generate "migration", "CreateMagicLinks identity:references code:string:uniq purpose:integer expires_at:datetime"

  # ── Routes ──────────────────────────────────────────────────────────────────

  route <<~RUBY
    # Authentication
    resource :session, only: [] do
      get  :new,     path: "sign-in"
      post :create,  path: "sign-in"
      delete :destroy, path: "sign-out"
    end

    resources :magic_links, only: [] do
      collection do
        get  :new,    path: "magic-link"
        post :create, path: "magic-link"
        get  :show,   path: "magic-link/:code"
      end
    end
  RUBY

  # ── Deployment ──────────────────────────────────────────────────────────────

  copy_template "config/deploy.yml"
  copy_template ".kamal/secrets.example"
  copy_template "config/recurring.yml"

  # ── Docker ──────────────────────────────────────────────────────────────────

  copy_template "Dockerfile"
  copy_template "bin/docker-entrypoint"
  chmod "bin/docker-entrypoint", 0o755

  # ── Development scripts ─────────────────────────────────────────────────────

  copy_template "bin/dev"
  chmod "bin/dev", 0o755

  copy_template "bin/ci"
  chmod "bin/ci", 0o755

  # ── CI/CD ───────────────────────────────────────────────────────────────────

  copy_template ".github/workflows/ci.yml"

  # ── Documentation ───────────────────────────────────────────────────────────

  copy_template "RAILS_AGENTS.md", "AGENTS.md"
  copy_template "RAILS_STYLE.md", "STYLE.md"

  directory ".claude", ".claude"

  # ── Solid Queue setup ───────────────────────────────────────────────────────

  rails_command "solid_queue:install"
  rails_command "solid_cable:install"
  rails_command "solid_cache:install"

  # ── Importmap setup ─────────────────────────────────────────────────────────

  rails_command "importmap:install"
  rails_command "turbo:install"
  rails_command "stimulus:install"

  # ── Database ────────────────────────────────────────────────────────────────

  rails_command "db:create"
  rails_command "db:migrate"

  # ── Git ─────────────────────────────────────────────────────────────────────

  git add: "."
  git commit: "-m 'Initial commit from AppFabriek Rails Template'"

  say "\n\n✅ App created with AppFabriek Rails Template!", :green
  say "Next steps:", :bold
  say "  1. Update config/deploy.yml with your server hostname"
  say "  2. Copy .kamal/secrets.example → .kamal/secrets and fill in values"
  say "  3. bin/dev   # Start development server"
  say "  4. See AGENTS.md for architectural guidance\n\n"
end
