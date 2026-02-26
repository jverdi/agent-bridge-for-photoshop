import type { AdapterMode } from "../types.js";

export interface CapabilityMap {
  openDocument: boolean;
  manifest: boolean;
  listLayers: boolean;
  applyOps: boolean;
  render: boolean;
  checkpoints: boolean;
  events: boolean;
}

const desktopCapabilities: CapabilityMap = {
  openDocument: true,
  manifest: true,
  listLayers: true,
  applyOps: true,
  render: true,
  checkpoints: true,
  events: true
};

export function capabilitiesForMode(mode: AdapterMode): CapabilityMap {
  if (mode !== "desktop") {
    throw new Error(`Unsupported adapter mode: ${mode}`);
  }
  return desktopCapabilities;
}
