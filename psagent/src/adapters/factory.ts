import type { ResolvedConfig } from "../types.js";
import type { PsAdapter } from "./base.js";
import { DesktopAdapter } from "./desktop.js";

export function createAdapter(config: ResolvedConfig): PsAdapter {
  return new DesktopAdapter(config.pluginEndpoint, config.timeoutMs);
}
