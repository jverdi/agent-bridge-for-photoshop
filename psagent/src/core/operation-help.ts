import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const OPERATION_CATALOG_DOC = "operation-catalog.mdx";
const OPERATION_ARGUMENTS_DOC = "operation-arguments-and-examples.mdx";

export interface OperationCatalogGroup {
  name: string;
  operations: string[];
}

export interface OperationHelpEntry {
  name: string;
  aliases: string[];
  required: string;
  supportedArgs: string;
  example: string;
}

export interface OperationHelpDocs {
  groups: OperationCatalogGroup[];
  entries: OperationHelpEntry[];
  byName: Map<string, OperationHelpEntry>;
  catalogOperationNames: Set<string>;
}

function parseCatalogGroups(source: string): OperationCatalogGroup[] {
  const groups: OperationCatalogGroup[] = [];
  const lines = source.split(/\r?\n/u);
  let current: OperationCatalogGroup | null = null;

  for (const line of lines) {
    const headingMatch = line.match(/^##\s+(.+)$/u);
    if (headingMatch) {
      const heading = headingMatch[1].trim();
      if (heading === "Known behavior notes") {
        current = null;
        continue;
      }
      current = { name: heading, operations: [] };
      groups.push(current);
      continue;
    }

    if (!current) {
      continue;
    }

    const opMatch = line.match(/^- \[`([^`]+)`\]/u);
    if (!opMatch) {
      continue;
    }

    const operationName = opMatch[1];
    if (!current.operations.includes(operationName)) {
      current.operations.push(operationName);
    }
  }

  return groups;
}

function extractLineValue(source: string, prefix: string): string | null {
  for (const line of source.split(/\r?\n/u)) {
    if (!line.startsWith(prefix)) {
      continue;
    }
    return line.slice(prefix.length).trim();
  }
  return null;
}

function parseBacktickTokens(line: string | null): string[] {
  if (!line) {
    return [];
  }
  const tokens: string[] = [];
  for (const match of line.matchAll(/`([^`]+)`/gu)) {
    tokens.push(match[1]);
  }
  return tokens;
}

function parseOperationEntries(source: string): OperationHelpEntry[] {
  const headingRegex = /^###\s+`([^`]+)`\s*$/gmu;
  const headings = [...source.matchAll(headingRegex)];
  const entries: OperationHelpEntry[] = [];

  for (let index = 0; index < headings.length; index += 1) {
    const match = headings[index];
    const name = match[1];
    const sectionStart = (match.index ?? 0) + match[0].length;
    const sectionEnd = index + 1 < headings.length ? (headings[index + 1].index ?? source.length) : source.length;
    const section = source.slice(sectionStart, sectionEnd);

    const aliases = parseBacktickTokens(extractLineValue(section, "- Aliases: "));
    const required = extractLineValue(section, "- Required: ") ?? "None";
    const supportedArgs = extractLineValue(section, "- Supported args: ") ?? "No op-specific args";
    const exampleMatch = section.match(/```json\s*([\s\S]*?)```/u);

    entries.push({
      name,
      aliases,
      required,
      supportedArgs,
      example: exampleMatch ? exampleMatch[1].trim() : ""
    });
  }

  return entries;
}

function candidateDocPaths(filename: string): string[] {
  const moduleDir = path.dirname(fileURLToPath(import.meta.url));
  const docsRelative = path.join("docs", "reference", filename);
  const candidates = [
    path.resolve(process.cwd(), docsRelative),
    path.resolve(moduleDir, "../../../", docsRelative),
    path.resolve(moduleDir, "../../../../", docsRelative)
  ];
  return [...new Set(candidates)];
}

function resolveDocPath(filename: string): string | null {
  for (const candidate of candidateDocPaths(filename)) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }
  return null;
}

export function loadOperationHelpDocs(): OperationHelpDocs | null {
  const catalogPath = resolveDocPath(OPERATION_CATALOG_DOC);
  const argumentsPath = resolveDocPath(OPERATION_ARGUMENTS_DOC);
  if (!catalogPath || !argumentsPath) {
    return null;
  }

  const catalogSource = readFileSync(catalogPath, "utf8");
  const argumentsSource = readFileSync(argumentsPath, "utf8");

  const groups = parseCatalogGroups(catalogSource);
  const entries = parseOperationEntries(argumentsSource);
  const byName = new Map(entries.map((entry) => [entry.name, entry]));
  const catalogOperationNames = new Set<string>();

  for (const group of groups) {
    for (const operationName of group.operations) {
      catalogOperationNames.add(operationName);
    }
  }

  return {
    groups,
    entries,
    byName,
    catalogOperationNames
  };
}
