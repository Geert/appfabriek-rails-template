# AppFabriek Rails Template

Opinionated Rails starter template met bewezen architectuurpatronen.

## Wat zit er in

| Onderdeel | Keuze |
|-----------|-------|
| Auth | Passwordless magic links (geen wachtwoorden) |
| Primary keys | UUIDv7 base36 (25 chars) |
| Multi-tenancy | URL-pad gebaseerd (`/account_id/...`) |
| Background jobs | Solid Queue (geen Redis) |
| Frontend JS | Importmap + Turbo + Stimulus |
| Asset pipeline | Propshaft |
| Real-time | Turbo Streams + Action Cable (Solid Cable) |
| Cache | Solid Cache |
| Deployment | Kamal (Docker) |
| Testing | Minitest + fixtures + Capybara |

## Gebruik

```bash
rails new myapp -m ~/code/appfabriek-rails-template/template.rb
```

Of via GitHub template: klik op **Use this template** bovenaan.

## Wat de template doet

Bij `rails new myapp -m template.rb`:

1. Voegt gems toe (Solid Queue/Cable/Cache, Turbo, Stimulus, Propshaft, Kamal, etc.)
2. Kopieert core bestanden:
   - Auth: `Identity`, `MagicLink`, `Session`, `Current`, `Authentication` concern
   - Initializers: UUID PKs, multi-tenancy middleware, ActiveJob account context
   - Deployment: `Dockerfile`, `config/deploy.yml`, `.kamal/secrets.example`
   - Dev scripts: `bin/dev`, `bin/ci`
   - CI: `.github/workflows/ci.yml`
   - Docs: `AGENTS.md`, `STYLE.md`, `.claude/CLAUDE.md`
3. Genereert migraties voor `identities`, `sessions`, `magic_links`
4. Installeert Solid Queue, Solid Cable, Solid Cache
5. Installeert Importmap, Turbo, Stimulus
6. Draait `db:create` + `db:migrate`

## Na aanmaken

```bash
cd myapp

# 1. Deployment configureren
cp .kamal/secrets.example .kamal/secrets
# Vul .kamal/secrets in
# Update config/deploy.yml met je server hostname

# 2. Development starten
bin/dev

# 3. CI draaien
bin/ci
```

## Documentatie

- [AGENTS.md](AGENTS.md) — Architectuurgids voor ontwikkelaars en AI agents
- [STYLE.md](STYLE.md) — Coding conventions

## Multi-tenancy toevoegen

De multi-tenancy middleware (`AccountSlug::Extractor`) zit al in `config/initializers/tenanting/`. Zet `MULTI_TENANT=true` in je environment om het te activeren.

## Aanpassen

De template is een startpunt, geen keurslijf. Verwijder wat je niet nodig hebt. De patronen in `AGENTS.md` beschrijven hoe de architectuur werkt — volg ze of wijk bewust af.
