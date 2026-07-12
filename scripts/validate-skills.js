#!/usr/bin/env node
/**
 * validate-skills.js — Tier-1 structural validation for autoresearch-ai-plugin.
 *
 * Adapted from agent-skills' validator (github.com/addyosmani/agent-skills,
 * scripts/validate-skills.js). Changes for this plugin:
 *   - Frontmatter parser handles YAML block scalars (`description: >-`).
 *   - The "when to use" trigger regex accepts "Use this skill when …".
 *   - agent-skills' repo-specific required sections are replaced by a check
 *     this plugin actually needs: every skill-relative resource a SKILL.md
 *     references (scripts/, references/, examples/, assets/) must exist on
 *     disk — the guard against docs rotting away from the files they cite.
 *
 * Checks (errors block CI):
 *   - SKILL.md exists in every skill directory
 *   - frontmatter present with 'name' and 'description'
 *   - frontmatter 'name' matches the directory name
 *   - directory name is lowercase-hyphen-separated
 *   - description does not exceed 1024 characters (injected into system prompt)
 *   - description includes a 'when to use' trigger
 *   - every referenced skill resource exists
 *
 * Checks (warnings):
 *   - unrecognized frontmatter keys
 *
 * Exit codes: 0 = all clear, 1 = one or more errors
 */

'use strict';

const fs = require('fs');
const path = require('path');

const SKILLS_DIR = path.resolve(__dirname, '..', 'skills');

const MAX_DESCRIPTION_LENGTH = 1024;
const KEBAB_CASE = /^[a-z0-9]+(-[a-z0-9]+)*$/;

// Must state WHEN to use the skill, not just what it does. Accepts
// "Use when", "Use this skill when", "Use before/after/during".
const DESCRIPTION_TRIGGER = /\buse (this )?(skill )?when\b|\buse (before|after|during)\b/i;

// Frontmatter keys we expect; anything else gets a warning so typos
// ("descripton:") don't silently vanish.
const KNOWN_KEYS = new Set(['name', 'description', 'version', 'argument-hint', 'allowed-tools', 'license', 'metadata']);

// Resource references inside a SKILL.md body: `${CLAUDE_SKILL_DIR}/<path>`
// or a bare relative path starting with a known resource dir.
const RESOURCE_REF = /(?:\$\{CLAUDE_SKILL_DIR\}\/|(?<![\w/.]))((?:scripts|references|examples|assets)\/[A-Za-z0-9._/-]+[A-Za-z0-9])/g;

function parseFrontmatter(content) {
  const m = content.match(/^---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(\r?\n|$)/);
  if (!m) return null;
  const lines = m[1].split(/\r?\n/);
  const out = {};
  for (let i = 0; i < lines.length; i++) {
    const kv = lines[i].match(/^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$/);
    if (!kv) continue;
    const key = kv[1];
    let value = kv[2].trim();
    if (/^[>|][+-]?$/.test(value)) {
      // Block scalar: fold following more-indented (or blank) lines with spaces.
      const parts = [];
      while (i + 1 < lines.length && (lines[i + 1].trim() === '' || /^\s+\S/.test(lines[i + 1]))) {
        parts.push(lines[i + 1].trim());
        i++;
      }
      value = parts.filter(Boolean).join(' ');
    } else {
      value = value.replace(/^['"]|['"]$/g, '');
    }
    out[key] = value;
  }
  return out;
}

function extractResourceRefs(content) {
  const refs = new Set();
  let m;
  RESOURCE_REF.lastIndex = 0;
  while ((m = RESOURCE_REF.exec(content)) !== null) {
    refs.add(m[1]);
  }
  return refs;
}

function validateSkill(dirName) {
  const errors = [];
  const warnings = [];
  const skillDir = path.join(SKILLS_DIR, dirName);
  const skillPath = path.join(skillDir, 'SKILL.md');

  if (!fs.existsSync(skillPath)) {
    errors.push('Missing SKILL.md');
    return { errors, warnings };
  }

  let content;
  try {
    content = fs.readFileSync(skillPath, 'utf8');
  } catch (err) {
    errors.push(`Unreadable SKILL.md: ${err.message}`);
    return { errors, warnings };
  }

  const fm = parseFrontmatter(content);
  if (!fm) {
    errors.push('Missing or malformed YAML frontmatter (expected --- block at top of file)');
    return { errors, warnings };
  }

  if (!fm.name) {
    errors.push("Frontmatter missing required field: 'name'");
  } else if (fm.name !== dirName) {
    errors.push(`Frontmatter name '${fm.name}' does not match directory name '${dirName}'`);
  }

  if (!KEBAB_CASE.test(dirName)) {
    errors.push(`Directory name '${dirName}' is not lowercase-hyphen-separated`);
  }

  if (!fm.description) {
    errors.push("Frontmatter missing required field: 'description'");
  } else {
    if (fm.description.length > MAX_DESCRIPTION_LENGTH) {
      errors.push(
        `Description is ${fm.description.length} chars — exceeds the ${MAX_DESCRIPTION_LENGTH}-char limit` +
        ` (agents inject this into the system prompt)`
      );
    }
    if (!DESCRIPTION_TRIGGER.test(fm.description)) {
      errors.push(
        `Description has no 'when to use' trigger — add a "Use this skill when …" clause`
      );
    }
  }

  for (const key of Object.keys(fm)) {
    if (!KNOWN_KEYS.has(key)) {
      warnings.push(`Unrecognized frontmatter key '${key}'`);
    }
  }

  // Referenced resources must exist.
  for (const ref of extractResourceRefs(content)) {
    const target = path.join(skillDir, ref);
    if (!fs.existsSync(target)) {
      errors.push(`Referenced resource does not exist: ${ref}`);
    }
  }

  return { errors, warnings };
}

function main() {
  if (!fs.existsSync(SKILLS_DIR)) {
    console.error(`ERROR: skills directory not found at ${SKILLS_DIR}`);
    process.exit(1);
  }

  const skillDirs = fs.readdirSync(SKILLS_DIR)
    .filter((d) => fs.statSync(path.join(SKILLS_DIR, d)).isDirectory())
    .sort();

  let totalErrors = 0;
  let totalWarnings = 0;

  for (const dirName of skillDirs) {
    const { errors, warnings } = validateSkill(dirName);
    totalErrors += errors.length;
    totalWarnings += warnings.length;

    if (errors.length === 0 && warnings.length === 0) {
      console.log(`  ✓  ${dirName}`);
    } else {
      const icon = errors.length > 0 ? '  ✗ ' : '  ⚠ ';
      console.log(`${icon} ${dirName}`);
      for (const msg of errors) console.log(`       ERROR: ${msg}`);
      for (const msg of warnings) console.log(`       WARN:  ${msg}`);
    }
  }

  const status = totalErrors > 0 ? 'FAILED' : totalWarnings > 0 ? 'PASSED WITH WARNINGS' : 'PASSED';
  console.log(`\n${skillDirs.length} skills checked — ${totalErrors} error(s), ${totalWarnings} warning(s) — ${status}`);

  if (totalErrors > 0) process.exit(1);
}

try {
  main();
} catch (err) {
  console.error(`\nERROR: validate-skills failed unexpectedly: ${err.message}`);
  process.exit(1);
}
