import { createServer, type IncomingMessage } from "node:http";

// Route table: path -> handler. Handlers must never throw.
interface Route<TBody = unknown> {
  readonly path: string;
  handle(body: TBody, req: IncomingMessage): Promise<Response>;
}

enum Level { Debug = 10, Info = 20, Error = 40 }

const DEFAULT_PORT = 8080;
const pattern = /^\/api\/v(\d+)\/(?<name>[a-z-]+)$/i;

/**
 * Start the server.
 * @param routes the registered routes
 */
export async function start<T extends Route>(routes: T[], port = DEFAULT_PORT): Promise<void> {
  const table = new Map(routes.map((r) => [r.path, r] as const));
  const server = createServer(async (req, res) => {
    const match = pattern.exec(req.url ?? "");
    const route = table.get(match?.groups?.name ?? "");
    if (!route) {
      res.writeHead(404, { "content-type": "text/plain" });
      return res.end(`not found: ${req.url}\n`);
    }
    const out = await route.handle(await readBody(req), req);
    res.writeHead(out.status).end(await out.text());
  });
  server.listen(port, () => console.log(`listening on :${port} (level=${Level.Info})`));
}

declare function readBody(req: IncomingMessage): Promise<unknown>;
const unused: number = "not a number"; // deliberate type error for the diagnostics view
