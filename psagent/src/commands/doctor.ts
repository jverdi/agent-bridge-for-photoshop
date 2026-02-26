import { Command } from "commander";
import { wrapAction, commandFromArgs } from "../core/command.js";
import { printData } from "../core/output.js";
import { buildRuntime } from "../core/runtime.js";

export function registerDoctorCommand(program: Command): void {
  program
    .command("doctor")
    .description("Inspect current setup")
    .action(
      wrapAction(async (...args) => {
        const command = commandFromArgs(args);
        const runtime = buildRuntime(command);

        const health = await runtime.adapter.health();
        const capabilities = runtime.adapter.capabilities();

        const payload = {
          mode: runtime.config.mode,
          profile: runtime.config.profile,
          configPath: runtime.config.configPath,
          projectConfigPath: runtime.config.projectConfigPath,
          pluginEndpoint: runtime.config.pluginEndpoint,
          session: runtime.session,
          health,
          capabilities
        };

        printData(runtime.config.outputMode, payload, [
          `mode=${payload.mode}`,
          `profile=${payload.profile}`,
          `healthOk=${String(payload.health.ok)}`,
          `healthDetail=${payload.health.detail}`,
          `pluginEndpoint=${payload.pluginEndpoint}`
        ]);

        if (!health.ok) {
          process.exitCode = 4;
        }
      })
    );
}
