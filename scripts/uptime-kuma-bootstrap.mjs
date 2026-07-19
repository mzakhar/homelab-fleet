import { createRequire } from "node:module";

const require = createRequire("/app/package.json");
const { io } = require("socket.io-client");

const url = process.env.KUMA_URL || "http://127.0.0.1:3001";
const username = process.env.KUMA_USERNAME || "mark";
const password = process.env.KUMA_PASSWORD;

if (!password) {
  throw new Error("KUMA_PASSWORD is required");
}

const monitors = [
  http("Zakharhome apex", "https://zakharhome.org"),
  http("Zakharhome www", "https://www.zakharhome.org"),
  http("Dashboard Access", "https://dashboard.zakharhome.org"),
  http("Clean Mail Access", "https://cleanmail.zakharhome.org"),
  http("Synth public", "https://synth.zakharhome.org"),
  http("Books public", "https://books.zakharhome.org/books/"),
  http("Grafana LAN", "http://192.168.1.3:30300/api/health"),
  http("Prometheus LAN", "http://192.168.1.3:30090/-/ready"),
  http("Uptime Kuma LAN", "http://192.168.1.3:30081"),
  http("themachine node exporter", "http://192.168.1.3:9100/metrics"),
  http("homeserver node exporter", "http://192.168.1.2:9100/metrics"),
  http("Jellyfin LAN", "http://192.168.1.2:8096"),
  http("Plex LAN", "http://192.168.1.2:32400/web"),
];

function http(name, url) {
  return {
    type: "http",
    name,
    url,
    method: "GET",
    interval: 60,
    retryInterval: 60,
    resendInterval: 0,
    maxretries: 2,
    timeout: 30,
    active: true,
    upsideDown: false,
    expiryNotification: false,
    ignoreTls: false,
    maxredirects: 10,
    accepted_statuscodes: ["200-399"],
    notificationIDList: {},
    proxyId: null,
    parent: null,
    description: "",
    headers: null,
    body: null,
    authMethod: null,
    basic_auth_user: null,
    basic_auth_pass: null,
    keyword: null,
    invertKeyword: false,
    dns_resolve_type: "A",
    dns_resolve_server: "1.1.1.1",
    kafkaProducerBrokers: [],
    kafkaProducerSaslOptions: {},
    rabbitmqNodes: [],
    conditions: [],
  };
}

function emit(socket, event, ...args) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${event} timed out`)), 15000);
    socket.emit(event, ...args, (result) => {
      clearTimeout(timer);
      resolve(result);
    });
  });
}

const socket = io(url, {
  reconnection: false,
  timeout: 10000,
});

await new Promise((resolve, reject) => {
  socket.once("connect", resolve);
  socket.once("connect_error", reject);
});

const needsSetup = await emit(socket, "needSetup");
if (needsSetup) {
  const result = await emit(socket, "setup", username, password);
  if (!result?.ok) {
    throw new Error(`setup failed: ${result?.msg || JSON.stringify(result)}`);
  }
  console.log(`setup admin: ${username}`);
}

const login = await emit(socket, "login", { username, password });
if (!login?.ok) {
  throw new Error(`login failed: ${login?.msg || JSON.stringify(login)}`);
}

const current = await emit(socket, "getMonitorList");
const existingNames = new Set(Object.values(current || {}).map((monitor) => monitor.name));

for (const monitor of monitors) {
  if (existingNames.has(monitor.name)) {
    console.log(`skip existing: ${monitor.name}`);
    continue;
  }

  const added = await emit(socket, "add", monitor);
  if (!added?.ok) {
    throw new Error(`add failed for ${monitor.name}: ${added?.msg || JSON.stringify(added)}`);
  }
  console.log(`added: ${monitor.name}`);
}

socket.disconnect();
