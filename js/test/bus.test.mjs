import { expect } from "@open-wc/testing";
import { BusClient, noneTransport, envelope } from "../../priv/js/src/bus.mjs";

describe("envelope", () => {
  it("has exactly the §5 shape with v=1", () => {
    const env = envelope({ kind: "client-telemetry", site: "mysite", component: "persona-card", payload: { click: 1 } });
    expect(Object.keys(env)).to.deep.equal(["v", "kind", "site", "component", "ts", "idempotency_key", "payload"]);
    expect(env.v).to.equal(1);
    expect(env.kind).to.equal("client-telemetry");
    expect(env.site).to.equal("mysite");
    expect(env.component).to.equal("persona-card");
    expect(env.ts).to.be.a("number");
    expect(Math.abs(env.ts - Date.now())).to.be.at.most(5000);
    expect(env.payload).to.deep.equal({ click: 1 });
  });

  it("gets a fresh idempotency_key per envelope", () => {
    const a = envelope({ kind: "kv", payload: {} });
    const b = envelope({ kind: "kv", payload: {} });
    expect(a.idempotency_key).to.be.a("string").with.lengthOf.at.least(8);
    expect(a.idempotency_key).to.not.equal(b.idempotency_key);
  });

  it("defaults site/component to empty strings", () => {
    const env = envelope({ kind: "me", payload: {} });
    expect(env.site).to.equal("");
    expect(env.component).to.equal("");
  });
});

describe("BusClient with the default none transport", () => {
  let client;

  beforeEach(() => {
    client = new BusClient({ site: "demo", component: "persona-card" });
  });

  for (const method of ["kv", "pubsub", "me", "notify", "upload"]) {
    it(`${method}() resolves to no-transport`, async () => {
      const result = await client[method]({ some: "payload" });
      expect(result).to.deep.equal({ ok: false, reason: "no-transport" });
    });
  }

  it("resolves (never rejects) without options at all", async () => {
    const bare = new BusClient();
    expect(await bare.kv({})).to.deep.equal({ ok: false, reason: "no-transport" });
    expect(bare.transportName).to.equal("none");
  });

  it("exposes the none transport and never throws", async () => {
    expect(noneTransport.name).to.equal("none");
    expect(await noneTransport.send("kv", envelope({ kind: "kv", payload: {} }))).to.deep.equal({ ok: false, reason: "no-transport" });
  });
});

describe("BusClient with an injected transport", () => {
  it("passes kind + envelope through and returns the transport result", async () => {
    const seen = [];
    const transport = {
      name: "test",
      send: async (kind, env) => {
        seen.push([kind, env]);
        return { ok: true, value: 42 };
      },
    };
    const client = new BusClient({ transport, site: "s", component: "c" });
    const result = await client.kv({ key: "k", value: "v" });
    expect(result).to.deep.equal({ ok: true, value: 42 });
    expect(seen).to.have.lengthOf(1);
    expect(seen[0][0]).to.equal("kv");
    expect(seen[0][1].payload).to.deep.equal({ key: "k", value: "v" });
    expect(seen[0][1].site).to.equal("s");
    expect(seen[0][1].component).to.equal("c");
    expect(client.transportName).to.equal("test");
  });

  it("a throwing transport degrades to transport-error, never rejects", async () => {
    const transport = {
      name: "bad",
      send: async () => {
        throw new Error("socket blew up");
      },
    };
    const client = new BusClient({ transport });
    let result;
    try {
      result = await client.notify({ text: "hi" });
    } catch (err) {
      result = { threw: err };
    }
    expect(result).to.deep.equal({ ok: false, reason: "transport-error" });
  });

  it("a transport without a send function counts as no transport", async () => {
    const client = new BusClient({ transport: { name: "broken" } });
    expect(await client.me({})).to.deep.equal({ ok: false, reason: "no-transport" });
  });
});
