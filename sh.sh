#!/bin/bash

# WhatsApp Shell Bot Installer (Final Version)
# by ChatGPT (2025)

set -e

# Pastikan dijalankan sebagai root
if [[ "$EUID" -ne 0 ]]; then
  echo "❌ Jalankan sebagai root!"
  exit 1
fi

echo "🚀 Instalasi WhatsApp Shell Bot dimulai..."

# Update dan install dependensi
apt update && apt upgrade -y
apt install -y curl git nodejs npm

# Pakai Node.js v18 jika belum ada
NODE_VERSION=$(node -v 2>/dev/null || echo "v0.0.0")
if [[ "$NODE_VERSION" < "v16" ]]; then
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt install -y nodejs
fi

# Konfigurasi NPM mirror dan bersihkan cache
npm config set registry https://registry.npmmirror.com
npm cache clean --force

# Siapkan folder bot
rm -rf /opt/wa-vps
mkdir -p /opt/wa-vps
cd /opt/wa-vps

# Buat file index.js
cat > index.js <<'EOF'
const { default: makeWASocket, useSingleFileAuthState } = require('@whiskeysockets/baileys')
const { exec } = require('child_process')
const fs = require('fs')

const config = JSON.parse(fs.readFileSync('./config.json'))
const { state, saveState } = useSingleFileAuthState('./auth.json')

async function startBot() {
  const sock = makeWASocket({
    auth: state,
    printQRInTerminal: true
  })

  sock.ev.on('creds.update', saveState)

  sock.ev.on('messages.upsert', async ({ messages }) => {
    const msg = messages[0]
    if (!msg?.message || !msg.key.remoteJid) return

    const sender = msg.key.remoteJid
    const isOwner = config.allowed.includes(sender.replace('@s.whatsapp.net', ''))
    const text = msg.message.conversation || msg.message.extendedTextMessage?.text || ''

    if (!isOwner) {
      await sock.sendMessage(sender, { text: '❌ Anda tidak diizinkan menggunakan bot ini.' })
      return
    }

    if (text.length > 0) {
      exec(text, { timeout: 30000, maxBuffer: 1024 * 1024 * 10 }, async (err, stdout, stderr) => {
        const result = err ? stderr || err.message : stdout || '[✅] Perintah dijalankan.'
        const reply = `📥 Perintah:\n\`\`\`${text}\`\`\``

        if (result.length <= 4000) {
          await sock.sendMessage(sender, {
            text: `${reply}\n\n📤 Output:\n\`\`\`\n${result.trim()}\n\`\`\``
          })
        } else {
          const path = '/tmp/output.txt'
          fs.writeFileSync(path, result)
          await sock.sendMessage(sender, {
            text: `${reply}\n\n📤 Output terlalu panjang. Dikirim sebagai file:`,
          })
          await sock.sendMessage(sender, {
            document: { url: path },
            fileName: 'output.txt',
            mimetype: 'text/plain'
          })
        }
      })
    }
  })
}

startBot()
EOF

# Buat package.json
cat > package.json <<'EOF'
{
  "name": "wa-vps",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "@whiskeysockets/baileys": "^6.6.0"
  }
}
EOF

# Input nomor owner
read -p "📱 Masukkan nomor WhatsApp Anda (format: 628xxxx): " OWNER

# Buat config.json
cat > config.json <<EOF
{
  "owner": "$OWNER",
  "allowed": ["$OWNER"]
}
EOF

# Install dependensi Node.js
npm install || {
  echo "❌ Gagal install. Coba ulangi dengan koneksi stabil."
  exit 1
}

# Buat systemd service
cat > /etc/systemd/system/wa-vps.service <<EOF
[Unit]
Description=WhatsApp Shell Bot
After=network.target

[Service]
ExecStart=/usr/bin/node /opt/wa-vps/index.js
WorkingDirectory=/opt/wa-vps
Restart=always
User=root
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

# Aktifkan dan jalankan
systemctl daemon-reload
systemctl enable wa-vps
systemctl restart wa-vps

echo "✅ Bot berhasil diinstal dan berjalan sebagai service!"
echo "ℹ️ Jalankan perintah berikut untuk scan QR code login WhatsApp:"
echo ""
echo "   journalctl -u wa-vps -f"
echo ""
echo "🟢 Setelah login, kirim perintah apapun via WhatsApp:"
echo "   uptime"
echo "   whoami"
echo "   ls -lah /etc"
