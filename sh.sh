#!/bin/bash

set -e

echo "🟢 Memulai setup WhatsApp Linux Bot..."

# Update & install dependencies
apt update && apt upgrade -y
apt install -y curl git build-essential

# Install Node.js LTS terbaru via NodeSource
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt install -y nodejs

# Cek versi Node.js
echo "✅ Node.js terpasang: $(node -v)"

# Dapatkan IP publik
IP_PUB=$(curl -s ifconfig.me || wget -qO- ifconfig.me)
echo "🌐 IP Publik VPS: $IP_PUB"

# Buat direktori bot
BOT_DIR="$HOME/wa-linux-bot"
rm -rf $BOT_DIR
mkdir -p $BOT_DIR
cd $BOT_DIR

# Inisialisasi project Node.js
npm init -y

# Install dependencies
npm install whatsapp-web.js qrcode express

# Buat file index.js
cat <<EOF > index.js
const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode');
const express = require('express');
const { exec } = require('child_process');

const app = express();
const port = 3000;

let currentQR = '';
const ADMIN_NUMBER = '6281234567890@c.us'; // Ganti dengan nomor kamu

const client = new Client({
    authStrategy: new LocalAuth(),
    puppeteer: { headless: true, args: ['--no-sandbox'] }
});

client.on('qr', async (qr) => {
    currentQR = qr;
    console.log('📲 QR tersedia. Akses lewat browser.');
});

app.get('/', async (req, res) => {
    if (!currentQR) return res.send('QR belum tersedia.');
    const qrImg = await qrcode.toDataURL(currentQR);
    res.send(\`<h2>Scan QR WhatsApp</h2><img src="\${qrImg}"/>\`);
});

app.listen(port, () => {
    console.log(\`🌐 QR Web aktif di http://${IP_PUB}:\${port}\`);
});

client.on('ready', () => {
    console.log('✅ Bot siap menerima perintah Linux.');
    client.sendMessage(ADMIN_NUMBER, '🤖 Bot siap! Kirim perintah Linux apa pun.');
});

client.on('message', async msg => {
    if (msg.from !== ADMIN_NUMBER) return;

    const command = msg.body;
    exec(command, { maxBuffer: 1024 * 1000 }, (error, stdout, stderr) => {
        let result = '';
        if (error) result += \`❌ ERROR:\\n\${error.message}\\n\`;
        if (stderr) result += \`⚠️ STDERR:\\n\${stderr}\\n\`;
        if (stdout) result += \`📤 STDOUT:\\n\${stdout}\\n\`;

        // Bagi output jika terlalu panjang
        const chunkSize = 3900;
        for (let i = 0; i < result.length; i += chunkSize) {
            client.sendMessage(msg.from, result.slice(i, i + chunkSize));
        }
    });
});

client.initialize();
EOF

# Buat file systemd service
cat <<EOF > /etc/systemd/system/wa-bot.service
[Unit]
Description=WhatsApp Linux Bot
After=network.target

[Service]
WorkingDirectory=$BOT_DIR
ExecStart=$(which node) $BOT_DIR/index.js
Restart=always
User=$USER
Environment=PATH=/usr/bin:/usr/local/bin
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

# Aktifkan service
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable wa-bot
systemctl restart wa-bot

echo "✅ Bot selesai diinstall dan aktif!"
echo "🌐 Akses QR Code: http://$IP_PUB:3000"
echo "✏️ Ubah nomor admin di: $BOT_DIR/index.js lalu restart: systemctl restart wa-bot"
