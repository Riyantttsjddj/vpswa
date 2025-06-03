#!/bin/bash

# ========== Persiapan ==========
echo "[*] Update & install dependensi..."
apt update && apt install -y curl git unzip wget nodejs npm

# ========== Pasang Node.js 20 ==========
echo "[*] Install Node.js 20.x..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# ========== Folder Bot ==========
BOT_DIR="/opt/wa-vps-control"
if [ -d "$BOT_DIR" ]; then
    rm -rf "$BOT_DIR"
fi
mkdir -p "$BOT_DIR"
cd "$BOT_DIR"

# ========== Simpan Bot ==========
echo "[*] Membuat file bot..."
cat > bot.js << 'EOF'
import makeWASocket, { useSingleFileAuthState } from '@whiskeysockets/baileys'
import { Boom } from '@hapi/boom'
import fs from 'fs'
import { exec } from 'child_process'

const { state, saveState } = useSingleFileAuthState('./auth.json')

async function startBot() {
    const sock = makeWASocket({
        auth: state,
        printQRInTerminal: true
    })

    sock.ev.on('creds.update', saveState)

    sock.ev.on('messages.upsert', async ({ messages }) => {
        const msg = messages[0]
        if (!msg.message || msg.key.fromMe) return

        const sender = msg.key.remoteJid
        const body = msg.message.conversation || msg.message.extendedTextMessage?.text
        if (!body) return

        console.log(`[CMD] ${sender}: ${body}`)

        exec(body, { maxBuffer: 1024 * 1024 * 10 }, (err, stdout, stderr) => {
            let output = ""
            if (err) output = "❌ Error:\n" + stderr
            else output = stdout || "✅ Perintah berhasil tanpa output."

            sock.sendMessage(sender, { text: output.slice(0, 4096) }) // 4096: aman untuk WA
        })
    })

    sock.ev.on('connection.update', ({ connection, lastDisconnect }) => {
        if (connection === 'close') {
            const shouldReconnect = (lastDisconnect?.error as Boom)?.output?.statusCode !== DisconnectReason.loggedOut
            console.log('Connection closed. Reconnecting...', shouldReconnect)
            if (shouldReconnect) startBot()
        }
    })
}

startBot()
EOF

# ========== Inisialisasi Project ==========
echo "[*] Inisialisasi npm..."
npm init -y
npm install @whiskeysockets/baileys@6.7 typescript ts-node @types/node

# ========== TypeScript Config ==========
cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "es2020",
    "module": "commonjs",
    "strict": true,
    "esModuleInterop": true,
    "outDir": "dist"
  }
}
EOF

# ========== Service Systemd ==========
echo "[*] Menyiapkan systemd service..."
cat > /etc/systemd/system/wa-vps.service <<EOF
[Unit]
Description=WhatsApp VPS Control Bot
After=network.target

[Service]
ExecStart=/usr/bin/npx ts-node $BOT_DIR/bot.js
WorkingDirectory=$BOT_DIR
Restart=always
User=root
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

# ========== Enable & Jalankan ==========
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable wa-vps
systemctl start wa-vps

echo "[✅] Bot berhasil dijalankan. Silakan scan QR code di terminal."
