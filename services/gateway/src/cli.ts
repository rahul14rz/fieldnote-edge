import { mkdirSync } from "node:fs";
import { join } from "node:path";

import { AuthStore } from "./auth/store.js";
import { EnvError, parseEnv } from "./env.js";

const usage = `Usage:
  fieldnote-gateway pair             Print a one-time pairing code for a phone
  fieldnote-gateway devices          List paired devices
  fieldnote-gateway revoke <id>      Revoke a device and end its sessions`;

function main(args: string[]): number {
  const env = parseEnv(process.env);
  mkdirSync(env.DATA_DIR, { recursive: true });
  const auth = new AuthStore(join(env.DATA_DIR, "gateway.sqlite"), () => new Date());
  try {
    switch (args[0]) {
      case "pair": {
        const { code, expiresAt } = auth.createPairingCode();
        console.log(`Pairing code: ${code}`);
        console.log(`Expires at:   ${expiresAt} (single use)`);
        return 0;
      }
      case "devices": {
        for (const d of auth.devices()) {
          console.log(
            `${d.deviceId}  ${d.name}  paired ${d.pairedAt}${d.revokedAt ? `  REVOKED ${d.revokedAt}` : ""}`,
          );
        }
        return 0;
      }
      case "revoke": {
        const id = args[1];
        if (id === undefined) break;
        if (!auth.revoke(id)) {
          console.error(`No active device ${id}`);
          return 1;
        }
        console.log(`Revoked ${id}`);
        return 0;
      }
    }
    console.error(usage);
    return 2;
  } finally {
    auth.close();
  }
}

try {
  process.exitCode = main(process.argv.slice(2));
} catch (error) {
  console.error(error instanceof EnvError ? error.message : error);
  process.exitCode = 1;
}
