#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
const root=path.resolve(import.meta.dirname,".."), fixture=path.join(root,"tests/fixtures/basic"), cli=path.join(root,"code-doctor.mjs"), out=path.join(fixture,".code-doctor");
fs.rmSync(out,{recursive:true,force:true});
const r=spawnSync(process.execPath,[cli,"--project","tsconfig.json","--json","--fail-on","deprecated"],{cwd:fixture,encoding:"utf8"});
assert.equal(r.status,1); const report=JSON.parse(r.stdout); assert.equal(report.schemaVersion,1); assert.ok(report.findings.some(x=>x.ruleId==="deprecated-api"&&x.symbol==="oldApi")); assert.ok(report.findings.some(x=>x.ruleId==="ts-ignore")); assert.ok(report.findings.some(x=>x.ruleId==="undocumented-ts-expect-error")); assert.ok(report.findings.some(x=>x.ruleId==="explicit-any")); assert.ok(fs.existsSync(path.join(out,"AGENT_FIXES.md")));
console.log("Code Doctor fixture tests passed");
