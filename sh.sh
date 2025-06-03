#!/bin/bash

# === WhatsApp Shell Bot - Auto Installer ===
# Dibuat oleh ChatGPT untuk kontrol VPS via WhatsApp

set -e

echo "🟢 Mulai proses instalasi WhatsApp VPS Shell Bot..."

# Cek user root
if [[ "$EUID" -ne 0 ]]; then
  echo "❌ Jalankan skrip ini sebagai root!"
  exit 1
fi

# Update sistem
echo "🔧 Update sistem..."
apt update && apt upgrade -y

# Install dependensi
echo "📦 Menginstal dependensi..."
apt install -y curl git nodejs npm

# Install Node.js jika versi terlalu lama
NODE_VERSION=$(node -v 2>/dev/null || echo "v0.0.0")
if [[ "$NODE_VERSION" < "v16" ]]; then
  echo "🌀 Menginstal Node.js versi terbaru..."
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt install -y nodejs
fi

# Buat folder bot
echo "📂 Menyiapkan folder bot di /opt/wa-vps..."
rm -rf /opt/wa-vps
mkdir -p /opt/wa-vps
cd /opt/wa-vps

# Buat index.js (bot utama)
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
    if (!msg.message || !msg.key.remoteJid) return

    const sender = msg.key.remoteJid
    const isOwner = config.allowed.includes(sender.replace('@s.whatsapp.net', ''))
    const text = msg.message.conversation || msg.message.extendedTextMessage?.text || ''

    if (!isOwner) {
      await sock.sendMessage(sender, { text: '❌ Anda tidak diizinkan menggunakan bot ini.' })
      return
    }

    if (text.startsWith('/start ')) {
      const command = text.slice(7).trim()
      if (!command) {
        await sock.sendMessage(sender, { text: '⚠️ Format salah. Gunakan: /start <perintah>' })
        return
      }

      exec(command, { timeout: 15000 }, async (err, stdout, stderr) => {
        const result = err ? stderr || err.message : stdout || '[✅] Perintah dijalankan.'
        await sock.sendMessage(sender, {
          text: `📥 Perintah:\n\`\`\`${command}\`\`\`\n\n📤 Output:\n\`\`\`\n${result.trim().slice(0, 4000)}\n\`\`\``
        })
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

# Instal dependensi Node.js
echo "📦 Menginstal library WhatsApp..."
npm install

# Input nomor owner
read -p "📱 Masukkan nomor WhatsApp Anda (contoh 6281234567890): " OWNER

# Buat config.json
cat > config.json <<EOF
{
  "owner": "$OWNER",
  "allowed": ["$OWNER"],
  "shell_mode": true
}
EOF

# Buat systemd service
echo "⚙️ Membuat service systemd..."
cat > /etc/systemd/system/wa-vps.service <<EOF
[Unit]
Description=WhatsApp Shell Bot Service
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

# Reload systemd dan jalankan
echo "🚀 Mengaktifkan layanan WhatsApp VPS..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable wa-vps
systemctl start wa-vps

echo "✅ Bot berhasil dijalankan sebagai service systemd."
echo "📲 Silakan lihat QR code untuk login WhatsApp dengan menjalankan:"
echo "    journalctl -u wa-vps -f"
