import { Bonjour } from "bonjour-service";

/** mDNS service type the phone browses for: _fieldnote._tcp.local */
export const SERVICE_TYPE = "fieldnote";

export interface Advertisement {
  name: string;
  type: string;
  port: number;
  txt: Record<string, string>;
}

export interface Publisher {
  publish(ad: Advertisement): void;
  stop(): Promise<void>;
}

/**
 * The TXT record carries the protocol version and the start of the
 * certificate fingerprint, so the phone can show which Mac it found. Trust
 * still comes only from the pairing proof (ADR 0010), never from mDNS.
 */
export function advertisement(port: number, fingerprint: string, hostName: string): Advertisement {
  return {
    name: `Fieldnote gateway on ${hostName}`,
    type: SERVICE_TYPE,
    port,
    txt: { v: "1", fp: fingerprint.slice(0, 16) },
  };
}

export function bonjourPublisher(): Publisher {
  const bonjour = new Bonjour();
  return {
    publish: (ad) => {
      bonjour.publish({ name: ad.name, type: ad.type, port: ad.port, txt: ad.txt });
    },
    stop: () =>
      new Promise((resolve) => {
        bonjour.unpublishAll(() => {
          bonjour.destroy();
          resolve();
        });
      }),
  };
}
