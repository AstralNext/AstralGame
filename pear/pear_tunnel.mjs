// Holepunch Pear(HyperDHT) 组网侧车。
//
// 由 Rust 以子进程方式启动，stdin/stdout 走 NDJSON：
//   Rust -> 侧车: {"op":"send","to":<peerId>|null,"flood":bool,"except":<peerId>,"data":"<base64>"}
//                 {"op":"stop"}
//   侧车 -> Rust: {"op":"ready","role":"host|guest","selfKey":"<hex>"}
//                 {"op":"peer","id":<n>,"state":"open|close"}
//                 {"op":"data","from":<n>,"data":"<base64>"}
//                 {"op":"error","message":"..."}
//
// 房主用 HyperDHT 建立服务端（DHT 打洞，失败时由 Holepunch 中继转发），
// 每位成员一条加密连接；侧车只做链路多路复用，成员表 / 虚拟 IP / 帧转发
// 全部由 Rust 侧引擎处理，与 Steam 组网保持一致。
import DHT from 'hyperdht'

// 同时兼容内置的 Holepunch Bare 运行时与开发环境的 Node：
// Bare 没有全局 process / node:readline，stdin/stdout/exit 由 bare-process 提供。
const isBare = typeof Bare !== 'undefined'
const runtime = isBare
  ? (await import('bare-process')).default
  : globalThis.process

const dht = new DHT()
let role = null
let server = null
let hostSocket = null
let hostKey = null
let nextPeerId = 1
let stopped = false
const peers = new Map()

const out = (obj) => {
  const line = JSON.stringify(obj)
  try {
    // Bare 的 stdout.write 会攒到进程退出才真正刷出，console.log 是即时的。
    if (isBare) console.log(line)
    else runtime.stdout.write(line + '\n')
  } catch (_) {}
}
const b64 = (buf) => Buffer.from(buf).toString('base64')

function wirePeer(socket, id) {
  peers.set(id, socket)
  out({ op: 'peer', id, state: 'open' })
  socket.on('data', (buf) => out({ op: 'data', from: id, data: b64(buf) }))
  socket.on('error', () => {})
  socket.on('close', () => {
    peers.delete(id)
    out({ op: 'peer', id, state: 'close' })
  })
}

async function startHost() {
  role = 'host'
  const keyPair = DHT.keyPair()
  hostKey = keyPair.publicKey.toString('hex')
  server = dht.createServer((socket) => wirePeer(socket, nextPeerId++))
  await server.listen(keyPair)
  out({ op: 'ready', role: 'host', selfKey: hostKey })
}

async function startGuest(keyHex) {
  role = 'guest'
  const socket = dht.connect(Buffer.from(keyHex, 'hex'))
  socket.on('open', () => {
    hostSocket = socket
    // Rust 引擎靠这条事件把 guest_open 置真，之后才会发 HELLO 等握手帧。
    out({ op: 'peer', id: 1, state: 'open' })
    out({ op: 'ready', role: 'guest', selfKey: keyHex })
  })
  socket.on('data', (buf) => out({ op: 'data', from: 1, data: b64(buf) }))
  socket.on('error', (err) => out({ op: 'error', message: err.message }))
  socket.on('close', () => {
    if (hostSocket === socket) hostSocket = null
    out({ op: 'peer', id: 1, state: 'close' })
  })
}

function sendOut(to, flood, data, except) {
  const buf = Buffer.from(data, 'base64')
  if (role === 'guest') {
    if (hostSocket && hostSocket.writable) hostSocket.write(buf)
    return
  }
  if (flood || to == null) {
    for (const [id, socket] of peers.entries()) {
      if (except != null && id === Number(except)) continue
      if (socket.writable) socket.write(buf)
    }
    return
  }
  const socket = peers.get(Number(to))
  if (socket && socket.writable) socket.write(buf)
}

async function shutdown(code = 0) {
  if (stopped) return
  stopped = true
  try {
    for (const socket of peers.values()) socket.destroy()
    if (hostSocket) hostSocket.destroy()
    if (server) await server.close()
    await dht.destroy()
  } catch (_) {}
  runtime.exit(code)
}

function handleLine(line) {
  let msg
  try {
    msg = JSON.parse(line)
  } catch (_) {
    return
  }
  switch (msg.op) {
    case 'start':
      if (msg.role === 'host') {
        startHost().catch((err) => {
          out({ op: 'error', message: 'HyperDHT 启动失败: ' + err.message })
          shutdown(1)
        })
      } else if (msg.role === 'guest' && typeof msg.hostKey === 'string') {
        startGuest(msg.hostKey)
      } else {
        out({ op: 'error', message: '未知的启动参数' })
        shutdown(1)
      }
      break
    case 'send':
      sendOut(msg.to, msg.flood === true, msg.data || '', msg.except)
      break
    case 'stop':
      shutdown(0)
      break
    default:
      break
  }
}

// NDJSON 逐行读取 stdin。Bare 没有 node:readline，两种运行时都用同一套解析。
let pending = ''
runtime.stdin.on('data', (chunk) => {
  pending += chunk.toString()
  let idx
  while ((idx = pending.indexOf('\n')) >= 0) {
    const line = pending.slice(0, idx).trim()
    pending = pending.slice(idx + 1)
    if (line) handleLine(line)
  }
})
runtime.stdin.on('end', () => shutdown(0))
runtime.stdin.on('close', () => shutdown(0))
runtime.on('SIGINT', () => shutdown(0))
runtime.on('SIGTERM', () => shutdown(0))

// Rust 通过环境变量传入启动参数（避免 Bare 早期 stdin 丢数据）。
const env = runtime.env || {}
if (env.PEAR_ROLE === 'host') {
  startHost().catch((err) => {
    out({ op: 'error', message: 'HyperDHT 启动失败: ' + err.message })
    shutdown(1)
  })
} else if (env.PEAR_ROLE === 'guest' && typeof env.PEAR_HOST_KEY === 'string') {
  startGuest(env.PEAR_HOST_KEY)
}
