import express from "express"
import { createServer } from "http"
import { WebSocketServer, WebSocket } from "ws"
import { fileURLToPath } from "url"
import path from "path"
import { startSerial } from "./serial.js"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const PORT = Number(process.env.PORT ?? 3001)
const IS_PROD = process.env.NODE_ENV === "production"

const app = express()
const server = createServer(app)
const wss = new WebSocketServer({ server, path: "/ws" })

const clients = new Set<WebSocket>()

wss.on("connection", (ws) => {
  clients.add(ws)
  console.log(`[ws] client connected (total: ${clients.size})`)
  ws.on("close", () => {
    clients.delete(ws)
    console.log(`[ws] client disconnected (total: ${clients.size})`)
  })
})

function broadcast(data: object) {
  const msg = JSON.stringify(data)
  for (const ws of clients) {
    if (ws.readyState === WebSocket.OPEN) ws.send(msg)
  }
}

if (IS_PROD) {
  // Serve Vite build output
  app.use(express.static(path.join(__dirname, "../../dist")))
}

startSerial((point) => broadcast(point)).catch((err: Error) => {
  console.error("[serial] failed to open port:", err.message)
})

server.listen(PORT, () => {
  console.log(`[server] http://localhost:${PORT}`)
})
