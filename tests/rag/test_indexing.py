from __future__ import annotations

import copy
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from rag.code_intel import analyze_file, build_repo_package_index
from rag.indexing import extract_facts, index_repo, iter_text_files
from rag.retrieval import build_retrieval_plan, semantic_line_hits, symbol_hits
from rag.settings import DEFAULT_CONFIG
from rag.storage import ensure_db


class FakeVector(list):
    def tolist(self):
        return list(self)


class FakeEmbedder:
    def embed(self, texts):
        for index, text in enumerate(texts):
            yield FakeVector([float((len(text) + index) % 7), 0.5, 1.0])


class FakeClient:
    def __init__(self) -> None:
        self.upserts = []
        self.deletes = []

    def upsert(self, collection_name, points, wait=True):
        self.upserts.append((collection_name, len(points), wait))

    def delete(self, collection_name, points_selector, wait=True):
        self.deletes.append((collection_name, points_selector, wait))


class IndexingTest(unittest.TestCase):
    def make_connection(self) -> sqlite3.Connection:
        conn = sqlite3.connect(":memory:")
        conn.row_factory = sqlite3.Row
        ensure_db(conn)
        return conn

    def analyze_source(self, root: Path, rel_path: str, content: str, language: str = "typescript"):
        file_path = root / rel_path
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text(content)
        package_index = build_repo_package_index(root, root.name, [file_path])
        return analyze_file(root, file_path, rel_path, content, language, package_index, {rel_path})

    def test_iter_text_files_ignores_dependency_and_virtualenv_dirs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            files = {
                "app/main.py": "print('app')\n",
                ".venv/lib/python3.14/site-packages/markdown_it/main.py": "print('dependency')\n",
                "backend/venv/lib/python3.14/site-packages/pkg/module.py": "print('dependency')\n",
                "backend/__pycache__/main.cpython-314.pyc": "binary-ish",
                "node_modules/pkg/index.js": "console.log('dependency')\n",
                ".gradle/cache.properties": "dependency=true\n",
            }
            for rel_path, content in files.items():
                path = root / rel_path
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)

            indexed = {path.relative_to(root).as_posix() for path in iter_text_files(root)}

        self.assertEqual(indexed, {"app/main.py"})

    def test_index_repo_builds_symbol_dependency_and_package_indexes(self) -> None:
        conn = self.make_connection()
        config = copy.deepcopy(DEFAULT_CONFIG)
        profile = {"facts": True, "file_summaries": True, "repo_memory": False}

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo_name = root.name
            (root / "package.json").write_text(
                json.dumps({"name": "workspace-root", "workspaces": ["packages/*"]})
            )
            (root / "packages/app/src").mkdir(parents=True)
            (root / "packages/shared/src").mkdir(parents=True)
            (root / "packages/app/package.json").write_text(json.dumps({"name": "@acme/app"}))
            (root / "packages/shared/package.json").write_text(json.dumps({"name": "@acme/shared"}))
            (root / "packages/app/src/helper.ts").write_text("export const helper = () => 'ok'\n")
            (root / "packages/shared/src/index.ts").write_text("export const sharedThing = () => 1\n")
            (root / "packages/app/src/index.ts").write_text(
                "import { helper } from './helper'\n"
                "import { sharedThing } from '@acme/shared'\n\n"
                "export class AppService {\n"
                "  run() {\n"
                "    return helper() + String(sharedThing())\n"
                "  }\n"
                "}\n"
            )

            client = FakeClient()
            progress_events: list[dict[str, object]] = []
            with patch("rag.indexing.ensure_collection"), patch("rag.indexing.get_embedder", return_value=FakeEmbedder()):
                changed_files, total_chunks = index_repo(
                    conn,
                    client,
                    config,
                    root,
                    changed_only=False,
                    profile=profile,
                    progress_callback=progress_events.append,
                )

        self.assertGreaterEqual(changed_files, 5)
        self.assertGreater(total_chunks, 0)
        self.assertTrue(client.upserts)
        self.assertEqual(progress_events[0]["event"], "start")
        self.assertEqual(progress_events[-1]["event"], "finish")
        self.assertTrue(any(event["event"] == "indexed" for event in progress_events))
        self.assertEqual(progress_events[-1]["changed_files"], changed_files)
        self.assertEqual(progress_events[-1]["total_chunks"], total_chunks)

        symbol_rows = conn.execute(
            "SELECT qualified_name, kind, parser FROM symbols WHERE repo = ? AND path = ? ORDER BY start_line",
            (repo_name, "packages/app/src/index.ts"),
        ).fetchall()
        qualified_names = {row["qualified_name"] for row in symbol_rows}
        self.assertIn("AppService", qualified_names)
        self.assertTrue(any(name.endswith("run") for name in qualified_names))
        self.assertTrue(all(row["parser"] in {"regex", "tree-sitter"} for row in symbol_rows))

        dependency_rows = conn.execute(
            "SELECT dependency, target_path, is_internal FROM file_dependencies WHERE repo = ? AND source_path = ? ORDER BY dependency",
            (repo_name, "packages/app/src/index.ts"),
        ).fetchall()
        dependency_map = {row["dependency"]: (row["target_path"], row["is_internal"]) for row in dependency_rows}
        self.assertEqual(dependency_map["./helper"], ("packages/app/src/helper.ts", 1))
        self.assertEqual(dependency_map["@acme/shared"], ("packages/shared", 1))

        semantic_rows = conn.execute(
            "SELECT symbol, content FROM semantic_lines WHERE repo = ? AND path = ? ORDER BY line_no",
            (repo_name, "packages/app/src/index.ts"),
        ).fetchall()
        self.assertTrue(any("helper" in row["content"] for row in semantic_rows))
        self.assertTrue(any((row["symbol"] or "").endswith("run") for row in semantic_rows))

        chunk_packages = conn.execute(
            "SELECT DISTINCT package FROM chunks WHERE repo = ? AND path = ?",
            (repo_name, "packages/app/src/index.ts"),
        ).fetchall()
        self.assertEqual({row[0] for row in chunk_packages}, {"@acme/app"})

        summary_row = conn.execute(
            "SELECT package, summary, dependencies FROM package_summaries WHERE repo = ? AND package = ?",
            (repo_name, "@acme/app"),
        ).fetchone()
        self.assertIsNotNone(summary_row)
        self.assertIn("indexed files", summary_row["summary"])
        self.assertIn("packages/shared", summary_row["dependencies"])

        plan = build_retrieval_plan("AppService run helper", repo_name, config=config, conn=conn)
        self.assertTrue(symbol_hits(conn, plan))
        self.assertTrue(semantic_line_hits(conn, config, plan))

    def test_extract_facts_captures_nest_relationships(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            content = """
import { Controller, Get, Injectable, Module, UseGuards } from '@nestjs/common'
import { ApiOperation } from '@nestjs/swagger'
import { Cron } from '@nestjs/schedule'
import { Processor, Process } from '@nestjs/bull'
import { Entity, ManyToOne } from '@mikro-orm/core'
import { EntityRepository } from '@mikro-orm/postgresql'

@Injectable()
export class AuthGuard {}

@Controller('users')
export class UsersController {
  @UseGuards(AuthGuard)
  @ApiOperation({ summary: 'Get one user' })
  @Get(':id')
  getOne() {
    return 'ok'
  }

  @Cron('0 * * * *')
  syncUsers() {}
}

@Injectable()
export class UsersService {}

@Entity()
export class UserEntity {
  @ManyToOne(() => Organization)
  organization!: Organization
}

export class CreateUserDto {}

@Processor('emails')
export class EmailProcessor {
  @Process('send')
  handleSend() {}
}

export class UserRepository extends EntityRepository<UserEntity> {}

@Module({
  imports: [AuthModule],
  controllers: [UsersController],
  providers: [UsersService, AuthGuard],
  exports: [UsersService],
})
export class UsersModule {}
"""
            analysis = self.analyze_source(root, "src/users.controller.ts", content)
            facts = extract_facts(root / "src/users.controller.ts", content, "typescript", "code", analysis=analysis)
        fact_set = {(fact.kind, fact.key, fact.value) for fact in facts}
        self.assertIn(("route-controller", "UsersController", "users"), fact_set)
        self.assertIn(("route-handler", "GET users/:id", "UsersController.getOne"), fact_set)
        self.assertIn(("guard", "UsersController.getOne", "AuthGuard"), fact_set)
        self.assertIn(("scheduled-job", "syncUsers", "Cron 0 * * * *"), fact_set)
        self.assertIn(("queue-processor", "EmailProcessor", "emails"), fact_set)
        self.assertIn(("queue-job", "handleSend", "send"), fact_set)
        self.assertIn(("module-provider", "UsersModule", "UsersService"), fact_set)
        self.assertIn(("module-controller", "UsersModule", "UsersController"), fact_set)
        self.assertIn(("repository", "UserRepository", "UserEntity"), fact_set)
        self.assertIn(("relation", "UserEntity", "ManyToOne:Organization"), fact_set)
        self.assertIn(("dto", "CreateUserDto", "class"), fact_set)
        self.assertTrue(any(fact.kind == "swagger-decorator" and "ApiOperation" in fact.key for fact in facts))

    def test_extract_facts_captures_express_fastify_and_frontend(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            backend = """
import express from 'express'
import fastify from 'fastify'

const router = express.Router()
router.get('/users', requireAuth, validateUser, listUsers)
fastify.route({
  method: ['GET', 'POST'],
  url: '/jobs',
  preHandler: [requireAuth],
  handler: handleJobs,
})
fastify.register(apiRoutes, { prefix: '/api' })
"""
            frontend = """
import { useQuery } from '@tanstack/react-query'
import { Route } from 'react-router-dom'
import { z } from 'zod'
import { create } from 'zustand'
import axios from 'axios'
import { useForm } from 'react-hook-form'

export function UsersPage() {
  const query = useQuery({ queryKey: ['users', 'detail'] })
  useForm()
  axios.get('/api/users')
  return <Route path="/users" element={<UsersLayout />} />
}

export function UsersLayout() {
  return <div />
}

export function AuthProvider({ children }) {
  return <div>{children}</div>
}

export function useUsersTable() {
  return query
}

export const UserSchema = z.object({ id: z.string() })
export const useUiStore = create(() => ({}))
"""
            backend_analysis = self.analyze_source(root, "src/server.ts", backend)
            frontend_analysis = self.analyze_source(root, "src/pages/users.tsx", frontend)
            backend_facts = extract_facts(root / "src/server.ts", backend, "typescript", "code", analysis=backend_analysis)
            frontend_facts = extract_facts(root / "src/pages/users.tsx", frontend, "typescript", "code", analysis=frontend_analysis)
        backend_set = {(fact.kind, fact.key, fact.value) for fact in backend_facts}
        frontend_set = {(fact.kind, fact.key, fact.value) for fact in frontend_facts}
        self.assertIn(("route-handler", "GET /users", "listUsers"), backend_set)
        self.assertIn(("route-middleware", "GET /users", "requireAuth -> validateUser"), backend_set)
        self.assertIn(("route-handler", "GET /jobs", "handleJobs"), backend_set)
        self.assertIn(("route-handler", "POST /jobs", "handleJobs"), backend_set)
        self.assertIn(("route-prefix", "apiRoutes", "/api"), backend_set)
        self.assertIn(("page", "UsersPage", "users.tsx"), frontend_set)
        self.assertIn(("layout", "UsersLayout", "users.tsx"), frontend_set)
        self.assertIn(("frontend-provider", "AuthProvider", "react-provider"), frontend_set)
        self.assertIn(("hook", "useUsersTable", "react-hook"), frontend_set)
        self.assertIn(("frontend-route", "/users", "users.tsx"), frontend_set)
        self.assertIn(("query-key", "users/detail", "users.tsx"), frontend_set)
        self.assertIn(("api-call", "GET /api/users", "axios.get"), frontend_set)
        self.assertIn(("schema", "UserSchema", "zod"), frontend_set)
        self.assertIn(("state-store", "useUiStore", "zustand"), frontend_set)
        self.assertIn(("form", "users", "react-hook-form"), frontend_set)

    def test_extract_facts_captures_tsconfig_and_tooling_configs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            tsconfig = json.dumps(
                {
                    "extends": "@tsconfig/node20/tsconfig.json",
                    "compilerOptions": {
                        "target": "ES2022",
                        "module": "NodeNext",
                        "jsx": "react-jsx",
                        "strict": True,
                        "baseUrl": ".",
                        "paths": {"@/*": ["src/*"]},
                    },
                    "include": ["src/**/*.ts", "src/**/*.tsx"],
                    "references": [{"path": "./packages/shared"}],
                }
            )
            vite_config = """
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  resolve: {
    alias: {
      '@': '/src',
    },
  },
  server: { port: 4173 },
  test: { environment: 'jsdom' },
})
"""
            playwright_config = """
import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './tests/e2e',
  use: { baseURL: 'http://localhost:3000' },
})
"""
            tsconfig_facts = extract_facts(root / "tsconfig.json", tsconfig, "json", "config")
            vite_analysis = self.analyze_source(root, "vite.config.ts", vite_config)
            vite_facts = extract_facts(root / "vite.config.ts", vite_config, "typescript", "code", analysis=vite_analysis)
            playwright_analysis = self.analyze_source(root, "playwright.config.ts", playwright_config)
            playwright_facts = extract_facts(root / "playwright.config.ts", playwright_config, "typescript", "code", analysis=playwright_analysis)
        tsconfig_set = {(fact.kind, fact.key, fact.value) for fact in tsconfig_facts}
        vite_set = {(fact.kind, fact.key, fact.value) for fact in vite_facts}
        playwright_set = {(fact.kind, fact.key, fact.value) for fact in playwright_facts}
        self.assertIn(("tsconfig-extends", "extends", "@tsconfig/node20/tsconfig.json"), tsconfig_set)
        self.assertIn(("tsconfig-option", "target", "ES2022"), tsconfig_set)
        self.assertIn(("tsconfig-option", "jsx", "react-jsx"), tsconfig_set)
        self.assertIn(("tsconfig-option", "strict", "true"), tsconfig_set)
        self.assertIn(("tsconfig-alias", "@/*", "src/*"), tsconfig_set)
        self.assertIn(("tsconfig-reference", "reference", "./packages/shared"), tsconfig_set)
        self.assertIn(("tool-config", "vite", "vite"), vite_set)
        self.assertIn(("tool-config", "vite", "@vitejs/plugin-react"), vite_set)
        self.assertIn(("tool-alias", "vite.@", "/src"), vite_set)
        self.assertIn(("tool-config", "vite.port", "4173"), vite_set)
        self.assertIn(("tool-config", "vite.environment", "jsdom"), vite_set)
        self.assertIn(("tool-config", "playwright", "@playwright/test"), playwright_set)
        self.assertIn(("tool-config", "playwright.testDir", "./tests/e2e"), playwright_set)
        self.assertIn(("tool-config", "playwright.baseURL", "http://localhost:3000"), playwright_set)

    def test_extract_facts_captures_systems_language_and_database_surfaces(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cargo_toml = """
[package]
name = "kernel-observer"
edition = "2021"

[dependencies]
serde = "1"
tokio = { version = "1", features = ["macros"] }

[features]
metrics = ["serde"]
"""
            rust_source = """
use crate::metrics::Collector;

#[derive(Debug, Clone)]
pub struct Worker {}

pub trait Runner {
    fn run(&self);
}

impl Worker {
    pub fn execute(&self) {}
}
"""
            go_mod = """
module github.com/acme/telemetry

go 1.22

require (
    github.com/prometheus/client_golang v1.19.0
)

replace github.com/acme/shared => ../shared
"""
            go_source = """
package telemetry

import "context"

type Reporter interface {
    Report(ctx context.Context) error
}

type Service struct{}

func Run() {}

func (s *Service) Ping() {}
"""
            c_source = """
#include <linux/module.h>
#define DRIVER_NAME "observer"

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Kernel observer");
module_param(debug_level, int, 0644);
module_init(observer_init);
module_exit(observer_exit);
EXPORT_SYMBOL(observer_ping);
static struct file_operations observer_fops = {};
static DEVICE_ATTR_RW(threshold);
int observer_ping(void) { return 0; }
"""
            sql_source = """
CREATE EXTENSION IF NOT EXISTS vector;
CREATE TYPE public.status AS ENUM ('pending', 'done');
CREATE TABLE public.users (
    id UUID PRIMARY KEY,
    org_id UUID REFERENCES public.orgs(id),
    email TEXT NOT NULL,
    CONSTRAINT users_email_unique UNIQUE (email)
);
CREATE UNIQUE INDEX users_email_idx ON public.users(email);
CREATE PROCEDURE [dbo].[SyncUsers]
AS
BEGIN
    SELECT 1;
END;
"""
            mongo_redis_source = """
import mongoose from 'mongoose'
import Redis from 'ioredis'

const UserSchema = new mongoose.Schema({ email: String })
mongoose.model('User', UserSchema)
db.collection('users').aggregate([{ $match: { active: true } }])
cache.set('session:user:42', 'ok')
"""
            rust_analysis = self.analyze_source(root, "src/lib.rs", rust_source, language="rust")
            go_analysis = self.analyze_source(root, "telemetry/service.go", go_source, language="go")
            c_analysis = self.analyze_source(root, "driver/observer.c", c_source, language="c")
            mongo_analysis = self.analyze_source(root, "src/store.ts", mongo_redis_source)

            cargo_facts = extract_facts(root / "Cargo.toml", cargo_toml, "toml", "config")
            rust_facts = extract_facts(root / "src/lib.rs", rust_source, "rust", "code", analysis=rust_analysis)
            go_mod_facts = extract_facts(root / "go.mod", go_mod, "text", "text")
            go_facts = extract_facts(root / "telemetry/service.go", go_source, "go", "code", analysis=go_analysis)
            c_facts = extract_facts(root / "driver/observer.c", c_source, "c", "code", analysis=c_analysis)
            sql_facts = extract_facts(root / "db/schema.sql", sql_source, "sql", "code")
            datastore_facts = extract_facts(root / "src/store.ts", mongo_redis_source, "typescript", "code", analysis=mongo_analysis)

        cargo_set = {(fact.kind, fact.key, fact.value) for fact in cargo_facts}
        rust_set = {(fact.kind, fact.key, fact.value) for fact in rust_facts}
        go_mod_set = {(fact.kind, fact.key, fact.value) for fact in go_mod_facts}
        go_set = {(fact.kind, fact.key, fact.value) for fact in go_facts}
        c_set = {(fact.kind, fact.key, fact.value) for fact in c_facts}
        sql_set = {(fact.kind, fact.key, fact.value) for fact in sql_facts}
        datastore_set = {(fact.kind, fact.key, fact.value) for fact in datastore_facts}

        self.assertIn(("cargo-package", "name", "kernel-observer"), cargo_set)
        self.assertIn(("cargo-dependency", "tokio", "features=['macros'], version=1"), cargo_set)
        self.assertIn(("cargo-feature", "metrics", "serde"), cargo_set)
        self.assertIn(("rust-struct", "Worker", "public"), rust_set)
        self.assertIn(("rust-trait", "Runner", "public"), rust_set)
        self.assertTrue(any(fact[0] == "rust-method" and fact[1].endswith("execute") for fact in rust_set))
        self.assertIn(("rust-derive", "Worker", "Debug"), rust_set)
        self.assertIn(("go-module", "module", "github.com/acme/telemetry"), go_mod_set)
        self.assertIn(("go-require", "github.com/prometheus/client_golang", "v1.19.0"), go_mod_set)
        self.assertIn(("go-replace", "github.com/acme/shared", "../shared"), go_mod_set)
        self.assertIn(("go-package", "package", "telemetry"), go_set)
        self.assertIn(("go-interface", "Reporter", "type Reporter interface {"), go_set)
        self.assertTrue(any(fact[0] == "go-method" and fact[1].endswith("Ping") for fact in go_set))
        self.assertIn(("kernel-module-meta", "license", "GPL"), c_set)
        self.assertIn(("kernel-param", "debug_level", "int mode=0644"), c_set)
        self.assertIn(("kernel-hook", "init", "observer_init"), c_set)
        self.assertIn(("sysfs-attribute", "threshold", "declared"), c_set)
        self.assertIn(("postgres-extension", "vector", "enabled"), sql_set)
        self.assertIn(("postgres-enum-label", "public.status", "pending"), sql_set)
        self.assertIn(("sql-column", "public.users.email", "TEXT"), sql_set)
        self.assertIn(("sql-reference", "public.users.org_id", "public.orgs"), sql_set)
        self.assertIn(("mssql-procedure", "[dbo].[SyncUsers]", "procedure"), sql_set)
        self.assertIn(("mongo-model", "User", "mongoose"), datastore_set)
        self.assertIn(("mongo-operation", "users", "aggregate"), datastore_set)
        self.assertIn(("redis-key", "session:user:42", "set"), datastore_set)

    def test_extract_facts_captures_infra_systemd_and_zsh_surfaces(self) -> None:
        compose_yaml = """
services:
  api:
    image: acme/api:latest
    ports:
      - "8080:8080"
    volumes:
      - ./data:/data
    networks:
      - backend
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
volumes:
  app-data:
networks:
  backend:
"""
        dockerfile = """
FROM python:3.12-slim AS base
WORKDIR /app
COPY pyproject.toml /app/
RUN pip install -r requirements.txt
EXPOSE 8080
ENTRYPOINT ["python", "-m", "app"]
"""
        grafana_dashboard = json.dumps(
            {
                "title": "API Overview",
                "uid": "api-overview",
                "templating": {"list": [{"name": "env", "type": "query"}]},
                "panels": [{"title": "Request Rate", "type": "timeseries"}],
            }
        )
        prometheus_yaml = """
scrape_configs:
  - job_name: api
    static_configs:
      - targets: ['localhost:9090']
groups:
  - name: api.rules
    rules:
      - alert: ApiDown
        expr: up == 0
"""
        service_unit = """
[Unit]
Description=API Service
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python -m app
Environment=ENV=prod
Restart=always

[Install]
WantedBy=multi-user.target
"""
        zshrc = """
source ~/.zsh/plugins.zsh
plugins=(git docker)
setopt autocd nocaseglob
bindkey '^P' up-line-or-search
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
autoload -Uz compinit
"""
        compose_facts = extract_facts(Path("compose.yml"), compose_yaml, "yaml", "config")
        docker_facts = extract_facts(Path("Dockerfile"), dockerfile, "dockerfile", "code")
        grafana_facts = extract_facts(Path("grafana/dashboard.json"), grafana_dashboard, "json", "config")
        prometheus_facts = extract_facts(Path("prometheus/prometheus.yml"), prometheus_yaml, "yaml", "config")
        systemd_facts = extract_facts(Path("systemd/api.service"), service_unit, "systemd", "config")
        zsh_facts = extract_facts(Path(".zshrc"), zshrc, "shell", "code")

        compose_set = {(fact.kind, fact.key, fact.value) for fact in compose_facts}
        docker_set = {(fact.kind, fact.key, fact.value) for fact in docker_facts}
        grafana_set = {(fact.kind, fact.key, fact.value) for fact in grafana_facts}
        prometheus_set = {(fact.kind, fact.key, fact.value) for fact in prometheus_facts}
        systemd_set = {(fact.kind, fact.key, fact.value) for fact in systemd_facts}
        zsh_set = {(fact.kind, fact.key, fact.value) for fact in zsh_facts}

        self.assertIn(("compose-service", "api", "declared"), compose_set)
        self.assertIn(("compose-volume", "api", "./data:/data"), compose_set)
        self.assertIn(("compose-network", "api", "backend"), compose_set)
        self.assertIn(("compose-healthcheck", "api", '["CMD", "curl", "-f", "http://localhost:8080/health"]'), compose_set)
        self.assertIn(("docker-base-image", "base", "python:3.12-slim"), docker_set)
        self.assertIn(("docker-copy", "/app/", "pyproject.toml"), docker_set)
        self.assertIn(("docker-expose", "EXPOSE", "8080"), docker_set)
        self.assertIn(("grafana-dashboard", "API Overview", "api-overview"), grafana_set)
        self.assertIn(("grafana-panel", "Request Rate", "timeseries"), grafana_set)
        self.assertIn(("grafana-variable", "env", "query"), grafana_set)
        self.assertIn(("prometheus-job", "api", "scrape"), prometheus_set)
        self.assertIn(("prometheus-target", "api", "localhost:9090"), prometheus_set)
        self.assertIn(("prometheus-alert", "ApiDown", "api.rules"), prometheus_set)
        self.assertIn(("systemd-unit", "api.service", "service"), systemd_set)
        self.assertIn(("systemd-exec", "api.service.ExecStart", "/usr/bin/python -m app"), systemd_set)
        self.assertIn(("systemd-dependency", "api.service.WantedBy", "multi-user.target"), systemd_set)
        self.assertIn(("dotfile-source", ".zshrc", "~/.zsh/plugins.zsh"), zsh_set)
        self.assertIn(("zsh-plugin", "git", "enabled"), zsh_set)
        self.assertIn(("zsh-option", "autocd", "set"), zsh_set)
        self.assertIn(("zsh-bindkey", "^P", "up-line-or-search"), zsh_set)
        self.assertIn(("zsh-style", ":completion:*", "matcher-list=m:{a-z}={A-Z}"), zsh_set)


if __name__ == "__main__":
    unittest.main()
